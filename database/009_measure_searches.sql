/*
  009_measure_searches.sql
  Measures the searches of the API on TraceabilityDev. READ ONLY: it changes nothing.

  - Runs ONLY on TraceabilityDev, with the full set of 1000000 batches (007 + 008).
    The name is written in the script, so SQLCMD mode is not needed.
  - Replayable at any time. Contains no INSERT, UPDATE, DROP, TRUNCATE or DELETE.
  - It calls the real procedures of lot 2a (trace.GetBatch, trace.ListBatches),
    so it measures what the API will really do.
  - Used BEFORE and AFTER each index (see docs/mesures.md, sections 3 and 4).

  How to use it in SSMS:
    1. Turn on the actual execution plan: Ctrl+M (menu Query > Include Actual Execution Plan).
    2. Run the whole script (F5), or select ONE case and run only that block.
    3. Tab Messages: for each statement, read "logical reads" (and the elapsed time).
       Tab Execution plan: for each table, note Scan or Seek.
    - Logical reads are the reference measure (they do not change from one run to the next).
      The time is only an indication.

  Cases (the letters R1 to R5 are the hypotheses of docs/mesures.md):
    R1 + R2  GetBatch for one lot (lookup by code, then its movements)
    R3       ListBatches for a big farm, then a small farm (page 1 of 50)
    R4       ListBatches for SHIPPED, then RECEIVED (page 1 of 50)
    R5       ListBatches without filter, page 900 of 1000 (jump of 899000 rows)
*/

USE TraceabilityDev;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'TraceabilityDev'
BEGIN
    THROW 50001, N'Wrong database. This script runs only on TraceabilityDev. Nothing was done.', 1;
END;

IF (SELECT COUNT(*) FROM trace.Batch) <> 1000000
BEGIN
    THROW 50003, N'The full set of 1000000 batches is needed. Run 007 with 1000000 and check with 008. Nothing was done.', 1;
END;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* ---------- R1 + R2: one lot by its code, then its movements ---------- */
PRINT N'=== R1 + R2: trace.GetBatch for LOT-0500000 ===';
EXEC trace.GetBatch @BatchCode = N'LOT-0500000';
GO

/* ---------- R3: batches of one farm (page 1 of 50) ---------- */
PRINT N'=== R3 big farm: trace.ListBatches, farm F001, page 1 of 50 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = N'F001', @PageNumber = 1, @PageSize = 50;
GO

PRINT N'=== R3 small farm: trace.ListBatches, farm F021, page 1 of 50 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = N'F021', @PageNumber = 1, @PageSize = 50;
GO

/* ---------- R4: batches of one status (page 1 of 50) ---------- */
PRINT N'=== R4 SHIPPED: trace.ListBatches, status SHIPPED, page 1 of 50 ===';
EXEC trace.ListBatches @Status = N'SHIPPED', @FarmCode = NULL, @PageNumber = 1, @PageSize = 50;
GO

PRINT N'=== R4 RECEIVED: trace.ListBatches, status RECEIVED, page 1 of 50 ===';
EXEC trace.ListBatches @Status = N'RECEIVED', @FarmCode = NULL, @PageNumber = 1, @PageSize = 50;
GO

/* ---------- R5: a far page, no filter ---------- */
PRINT N'=== R5: trace.ListBatches, no filter, page 900 of 1000 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = NULL, @PageNumber = 900, @PageSize = 1000;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
