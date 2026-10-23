/*
  016_measure_lot5_costs.sql
  Costs of the candidate change of lot 5 on TraceabilityDev (docs/mesures.md, section 9.4):
    - W1: the cost of the index IX_Batch_FarmId on writes (trace.CreateBatch).
    - C2: the cost of OPTION (RECOMPILE) on the total of trace.ListBatches.
    - C3: the total without filter with OPTION (RECOMPILE).
    - D1: a diagnostic of the result of C2 (docs/mesures.md, section 9.4): the same statement,
      two forms, with the reads and the compile time.

  !!! W1 IS NOT READ ONLY !!!
  W1 calls trace.CreateBatch 500 times in ONE transaction, 5 times in a row, and every
  transaction is ROLLED BACK. No batch and no movement remains in the database (the script
  counts them before and after). What is NOT undone:
    - the IDENTITY numbers used by the rolled back inserts: BatchId and MovementId advance by
      2500 each (a gap in the numbering, no effect on the data or on the last page);
    - the transaction log grows a little.
  C2 and C3 are read only.

  - Runs ONLY on TraceabilityDev, with the full set of 1000000 batches (007 + 008), the
    procedure trace.CreateBatch of 005, and no transaction already open. The name is written
    in the script, so SQLCMD mode is not needed.
  - W1 uses farm F001 and the first station that has the RECEPTION function. The batch codes
    start with ZZ-LOT5- and do not exist.
  - Hypotheses C1 to C3 and their thresholds: docs/mesures.md, section 9.4 (written BEFORE).

  How to use it in SSMS:
    - Do NOT run the whole file with F5. Select ONE block (from its title comment to its GO).
    - Order: the first checks, then W1, then C2, then C3 (with the index IX_Batch_FarmId in
      place); then the index is dropped by hand and W1 is run again WITHOUT the index.
    - W1 and C2: turn the actual execution plan OFF (Ctrl+M). C3: turn it ON.

  What to note:
    - W1: the 5 lines "write run": elapsed ms, log bytes, log bytes per call; and the two
      lines with the counts before and after (they must be equal).
    - C2: the 5 lines "round": ms per call with and without OPTION (RECOMPILE).
    - C3: tab Messages (logical reads of Batch, for each of the two statements) and the plan
      (the index used by the first statement).
*/

USE TraceabilityDev;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'TraceabilityDev'
BEGIN
    THROW 50001, N'Wrong database. This script runs only on TraceabilityDev. Nothing was done.', 1;
END;

IF @@TRANCOUNT <> 0
BEGIN
    THROW 50007, N'A transaction is already open in this window. Nothing was done.', 1;
END;

IF (SELECT COUNT(*) FROM trace.Batch) <> 1000000
BEGIN
    THROW 50003, N'The full set of 1000000 batches is needed. Run 007 with 1000000 and check with 008. Nothing was done.', 1;
END;

IF OBJECT_ID(N'trace.CreateBatch', N'P') IS NULL OR OBJECT_ID(N'trace.ListBatches', N'P') IS NULL
BEGIN
    THROW 50006, N'Procedure not found. Run 005 first. Nothing was done.', 1;
END;

IF NOT EXISTS (SELECT 1 FROM trace.Farm WHERE Code = N'F001')
   OR NOT EXISTS (SELECT 1 FROM trace.Station AS s
                  JOIN trace.StationCapability AS c ON c.StationId = s.StationId
                  WHERE c.MovementType = N'RECEPTION')
BEGIN
    THROW 50008, N'Farm F001 or a station with the RECEPTION function is missing. Nothing was done.', 1;
END;
GO

/* ================================================================== */
/* W1 - cost of the index on writes. NOT READ ONLY: 5 x 500 CreateBatch*/
/* calls, each series in ONE transaction that is ROLLED BACK.          */
/* ================================================================== */

/* ---------- W1: 5 series of 500 CreateBatch, each rolled back ---------- */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
IF @@TRANCOUNT <> 0 THROW 50007, N'A transaction is already open in this window. Nothing was done.', 1;
DECLARE @station NVARCHAR(20) =
    (SELECT TOP (1) s.Code
     FROM trace.Station AS s
     JOIN trace.StationCapability AS c ON c.StationId = s.StationId
     WHERE c.MovementType = N'RECEPTION'
     ORDER BY s.Code);
DECLARE @harvest DATE = '2026-10-23';
DECLARE @now DATETIME2 = SYSUTCDATETIME();
DECLARE @batchesBefore INT = (SELECT COUNT(*) FROM trace.Batch);
DECLARE @movementsBefore INT = (SELECT COUNT(*) FROM trace.Movement);
DECLARE @run INT = 1;
DECLARE @i INT;
DECLARE @code NVARCHAR(30);
DECLARE @start DATETIME2(3);
DECLARE @ms INT;
DECLARE @logBytes BIGINT;
DECLARE @indexPresent NVARCHAR(3) =
    CASE WHEN EXISTS (SELECT 1 FROM sys.indexes
                      WHERE object_id = OBJECT_ID(N'trace.Batch') AND name = N'IX_Batch_FarmId')
         THEN N'yes' ELSE N'no' END;
PRINT CONCAT(N'index IX_Batch_FarmId present: ', @indexPresent, N' | station: ', @station);
BEGIN TRY
    WHILE @run <= 5
    BEGIN
        BEGIN TRANSACTION;
        SET @i = 1;
        SET @start = SYSDATETIME();
        WHILE @i <= 500
        BEGIN
            SET @code = CONCAT(N'ZZ-LOT5-', @run, N'-', RIGHT(CONCAT(N'0000', @i), 4));
            EXEC trace.CreateBatch @BatchCode = @code, @FarmCode = N'F001', @Variety = N'roma',
                 @HarvestDate = @harvest, @QuantityKg = 100.00, @StationCode = @station,
                 @OccurredAt = @now;
            SET @i += 1;
        END;
        SET @ms = DATEDIFF(MILLISECOND, @start, SYSDATETIME());
        SELECT @logBytes = dt.database_transaction_log_bytes_used
        FROM sys.dm_tran_database_transactions AS dt
        JOIN sys.dm_tran_current_transaction AS ct ON ct.transaction_id = dt.transaction_id
        WHERE dt.database_id = DB_ID();
        ROLLBACK TRANSACTION;
        PRINT CONCAT(N'write run ', @run, N': 500 CreateBatch, elapsed ms: ', @ms,
                     N' | log bytes: ', @logBytes, N' | log bytes per call: ', @logBytes / 500);
        SET @run += 1;
    END;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
DECLARE @batchesAfter INT = (SELECT COUNT(*) FROM trace.Batch);
DECLARE @movementsAfter INT = (SELECT COUNT(*) FROM trace.Movement);
PRINT CONCAT(N'batches before / after: ', @batchesBefore, N' / ', @batchesAfter);
PRINT CONCAT(N'movements before / after: ', @movementsBefore, N' / ', @movementsAfter);
GO

/* ================================================================== */
/* C2 - cost of OPTION (RECOMPILE) on the total (read only, Ctrl+M OFF)*/
/* The total of farm F001, written as in the procedure, in a loop.     */
/* This is the statement of the total, not the procedure.              */
/* ================================================================== */

/* ---------- C2: 5 rounds, 100 calls with and 20 calls without RECOMPILE ---------- */
SET NOCOUNT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @FarmId INT = (SELECT FarmId FROM trace.Farm WHERE Code = N'F001');
DECLARE @Status NVARCHAR(20) = NULL;
DECLARE @round INT = 1;
DECLARE @i INT;
DECLARE @c INT;
DECLARE @start DATETIME2(7);
DECLARE @usWith INT;
DECLARE @usWithout INT;
WHILE @round <= 5
BEGIN
    SET @i = 1;
    SET @start = SYSDATETIME();
    WHILE @i <= 100
    BEGIN
        SELECT @c = COUNT(*)
        FROM trace.Batch AS b
        WHERE (@Status IS NULL OR b.Status = @Status)
          AND (@FarmId IS NULL OR b.FarmId = @FarmId)
        OPTION (RECOMPILE);
        SET @i += 1;
    END;
    SET @usWith = DATEDIFF(MICROSECOND, @start, SYSDATETIME());

    SET @i = 1;
    SET @start = SYSDATETIME();
    WHILE @i <= 20
    BEGIN
        SELECT @c = COUNT(*)
        FROM trace.Batch AS b
        WHERE (@Status IS NULL OR b.Status = @Status)
          AND (@FarmId IS NULL OR b.FarmId = @FarmId);
        SET @i += 1;
    END;
    SET @usWithout = DATEDIFF(MICROSECOND, @start, SYSDATETIME());

    PRINT CONCAT(N'round ', @round, N': with RECOMPILE ',
                 CAST(@usWith / 1000.0 / 100 AS DECIMAL(10, 3)), N' ms per call (100 calls); without ',
                 CAST(@usWithout / 1000.0 / 20 AS DECIMAL(10, 3)), N' ms per call (20 calls)');
    SET @round += 1;
END;
GO

/* ================================================================== */
/* C3 - the total without filter (read only, Ctrl+M ON)                */
/* ================================================================== */

/* ---------- C3: no filter, with and without OPTION (RECOMPILE) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @FarmId INT = NULL;
DECLARE @Status NVARCHAR(20) = NULL;
PRINT N'=== C3a: total without filter, OPTION (RECOMPILE) ===';
SELECT COUNT(*) AS TotalCount
FROM trace.Batch AS b
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
OPTION (RECOMPILE);
PRINT N'=== C3b: the same total without OPTION (RECOMPILE), for comparison ===';
SELECT COUNT(*) AS TotalCount
FROM trace.Batch AS b
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId);
GO

/* ================================================================== */
/* D1 - diagnostic of C2 (read only, Ctrl+M ON)                        */
/* The total of farm F001 with OPTION (RECOMPILE), in the two forms:   */
/* as in the loop of C2 (the result goes into a variable) and as in    */
/* T3 (the result is returned). Two runs of each.                      */
/* ================================================================== */

/* ---------- D1: two forms, two runs each ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @FarmId INT = (SELECT FarmId FROM trace.Farm WHERE Code = N'F001');
DECLARE @Status NVARCHAR(20) = NULL;
DECLARE @c INT;
PRINT N'=== D1a run 1: the result goes into a variable, as in C2 ===';
SELECT @c = COUNT(*)
FROM trace.Batch AS b
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
OPTION (RECOMPILE);
PRINT N'=== D1a run 2 ===';
SELECT @c = COUNT(*)
FROM trace.Batch AS b
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
OPTION (RECOMPILE);
PRINT N'=== D1b run 1: the result is returned, as in T3 ===';
SELECT COUNT(*) AS TotalCount
FROM trace.Batch AS b
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
OPTION (RECOMPILE);
PRINT N'=== D1b run 2 ===';
SELECT COUNT(*) AS TotalCount
FROM trace.Batch AS b
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
OPTION (RECOMPILE);
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
