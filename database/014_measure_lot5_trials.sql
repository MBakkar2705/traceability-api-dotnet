/*
  014_measure_lot5_trials.sql
  Trials of lot 5 on TraceabilityDev. READ ONLY: it changes nothing.
  Trial G1: the page of trace.ListBatches (last page) without parallelism.

  - Runs ONLY on TraceabilityDev, with the full set of 1000000 batches (007 + 008) and the
    procedure trace.ListBatches of 005. The name is written in the script, so SQLCMD mode
    is not needed.
  - Contains no INSERT, UPDATE, DROP, TRUNCATE, DELETE, CREATE or ALTER. The procedure is NOT
    changed: the query of its page (the first statement) is replayed with sys.sp_executesql,
    with the same text, the same parameter types and @FarmId as a local variable, as in the
    procedure. The only difference between the two variants is OPTION (MAXDOP 1).
  - Hypothesis G1 and its thresholds: docs/mesures.md, section 8 (written BEFORE this test).

  How to use it in SSMS:
    - Do NOT run the whole file with F5. Select ONE block (from its title comment to its GO)
      and run it. Each block sets what it needs and checks the database name.
    - G1a (plans): turn the actual execution plan ON first (Ctrl+M). One run of each variant.
    - G1b (repeated runs): turn the actual execution plan OFF (Ctrl+M). 5 pairs of runs, the
      two variants alternated, so that they are compared in the same period (the duration of
      the same page varied from 7.9 s to 146 s in docs/mesures.md, section 7.3).
      It can last about 10 minutes. The red square (cancel) is safe: nothing is written.

  What to note:
    - G1a: tab Messages (logical reads of Batch and Farm, for each run) and, in the plan of
      each variant, the main operators: parallelism or not, Sort or not, and whether the
      Sort spills to tempdb (warning of its tooltip), actual rows.
    - G1b: for each pair, the line "default elapsed ms" and the line "maxdop1 elapsed ms",
      and the logical reads of Batch and Farm of each run.
  The logical reads are the reference measure. The time is only an indication.
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

IF OBJECT_ID(N'trace.ListBatches', N'P') IS NULL
BEGIN
    THROW 50006, N'Procedure not found. Run 005 first. Nothing was done.', 1;
END;
GO

/* ================================================================== */
/* G1a - plans (Ctrl+M ON). One run of each variant.                   */
/* The first run (default) is the control: its plan must look like the */
/* plan of A3 (docs/mesures.md, section 7.2): parallel, with a Sort    */
/* that spills to tempdb. If it does not, the trial says nothing about */
/* the procedure.                                                      */
/* ================================================================== */

/* ---------- G1a: default, then OPTION (MAXDOP 1) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @head NVARCHAR(MAX) = N'DECLARE @FarmId INT = NULL;
SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
FROM trace.Batch AS b
JOIN trace.Farm AS f ON f.FarmId = b.FarmId
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
ORDER BY b.BatchId
OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY';
DECLARE @sqlDefault NVARCHAR(MAX) = @head + N';';
DECLARE @sqlSerial NVARCHAR(MAX) = @head + N' OPTION (MAXDOP 1);';
DECLARE @params NVARCHAR(200) = N'@Status NVARCHAR(20), @PageNumber INT, @PageSize INT';
PRINT N'=== G1a default: page 66667 of 15, same text as the page query of the procedure ===';
EXEC sys.sp_executesql @sqlDefault, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
PRINT N'=== G1a maxdop1: the same statement with OPTION (MAXDOP 1) ===';
EXEC sys.sp_executesql @sqlSerial, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
GO

/* ================================================================== */
/* G1b - repeated runs (Ctrl+M OFF). 5 pairs, variants alternated.     */
/* ================================================================== */

/* ---------- G1b: 5 pairs (default, then OPTION (MAXDOP 1)) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @head NVARCHAR(MAX) = N'DECLARE @FarmId INT = NULL;
SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
FROM trace.Batch AS b
JOIN trace.Farm AS f ON f.FarmId = b.FarmId
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
ORDER BY b.BatchId
OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY';
DECLARE @sqlDefault NVARCHAR(MAX) = @head + N';';
DECLARE @sqlSerial NVARCHAR(MAX) = @head + N' OPTION (MAXDOP 1);';
DECLARE @params NVARCHAR(200) = N'@Status NVARCHAR(20), @PageNumber INT, @PageSize INT';
DECLARE @i INT = 1;
DECLARE @start DATETIME2(3);
WHILE @i <= 5
BEGIN
    PRINT CONCAT(N'--- G1b pair ', @i, N': default ---');
    SET @start = SYSDATETIME();
    EXEC sys.sp_executesql @sqlDefault, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
    PRINT CONCAT(N'default elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));

    PRINT CONCAT(N'--- G1b pair ', @i, N': maxdop1 ---');
    SET @start = SYSDATETIME();
    EXEC sys.sp_executesql @sqlSerial, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
    PRINT CONCAT(N'maxdop1 elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));

    SET @i += 1;
END;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
