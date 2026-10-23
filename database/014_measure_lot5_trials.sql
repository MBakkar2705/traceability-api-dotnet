/*
  014_measure_lot5_trials.sql
  Trials of lot 5 on TraceabilityDev. READ ONLY: it changes nothing.
  Trial G1: the page of trace.ListBatches (last page) without parallelism.
  Trial G2: the page of trace.ListBatches with the paging done BEFORE the join with Farm.

  - Runs ONLY on TraceabilityDev, with the full set of 1000000 batches (007 + 008) and the
    procedure trace.ListBatches of 005. The name is written in the script, so SQLCMD mode
    is not needed.
  - Contains no UPDATE, DROP, TRUNCATE, DELETE, CREATE or ALTER. Its only INSERT (block G2c)
    writes into a table variable that disappears at the end of the batch. The procedure is NOT
    changed: the query of its page (the first statement) is replayed with sys.sp_executesql,
    with the same text, the same parameter types and @FarmId as a local variable, as in the
    procedure. The only difference between the two variants is OPTION (MAXDOP 1).
  - Hypothesis G1 and its thresholds: docs/mesures.md, section 8 (written BEFORE this test).
  - Hypothesis G2 and its thresholds: docs/mesures.md, section 9.5 (written BEFORE this test).

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

/* ================================================================== */
/* G2 - the page with the paging done BEFORE the join with Farm.       */
/* "default" = the page query of the procedure; "candidate" = the     */
/* same query with the OFFSET/FETCH inside a derived table on Batch,   */
/* then the join with Farm for the rows of the page only.              */
/* ================================================================== */

/* ---------- G2a: plans and reads (Ctrl+M ON): page 66667 and page 1, default then candidate ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @sqlDefault NVARCHAR(MAX) = N'DECLARE @FarmId INT = NULL;
SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
FROM trace.Batch AS b
JOIN trace.Farm AS f ON f.FarmId = b.FarmId
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
ORDER BY b.BatchId
OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;';
DECLARE @sqlCandidate NVARCHAR(MAX) = N'DECLARE @FarmId INT = NULL;
SELECT p.BatchCode, f.Code AS FarmCode, p.Variety, p.HarvestDate, p.QuantityKg, p.Status
FROM (
    SELECT b.BatchId, b.BatchCode, b.FarmId, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId)
    ORDER BY b.BatchId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
) AS p
JOIN trace.Farm AS f ON f.FarmId = p.FarmId
ORDER BY p.BatchId;';
DECLARE @params NVARCHAR(200) = N'@Status NVARCHAR(20), @PageNumber INT, @PageSize INT';
PRINT N'=== G2a-1 default: page 66667 of 15 ===';
EXEC sys.sp_executesql @sqlDefault, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
PRINT N'=== G2a-2 candidate: page 66667 of 15 ===';
EXEC sys.sp_executesql @sqlCandidate, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
PRINT N'=== G2a-3 default: page 1 of 15 ===';
EXEC sys.sp_executesql @sqlDefault, @params, @Status = NULL, @PageNumber = 1, @PageSize = 15;
PRINT N'=== G2a-4 candidate: page 1 of 15 ===';
EXEC sys.sp_executesql @sqlCandidate, @params, @Status = NULL, @PageNumber = 1, @PageSize = 15;
GO

/* ---------- G2b: 5 pairs on page 66667 (Ctrl+M OFF), default then candidate ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @sqlDefault NVARCHAR(MAX) = N'DECLARE @FarmId INT = NULL;
SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
FROM trace.Batch AS b
JOIN trace.Farm AS f ON f.FarmId = b.FarmId
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
ORDER BY b.BatchId
OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;';
DECLARE @sqlCandidate NVARCHAR(MAX) = N'DECLARE @FarmId INT = NULL;
SELECT p.BatchCode, f.Code AS FarmCode, p.Variety, p.HarvestDate, p.QuantityKg, p.Status
FROM (
    SELECT b.BatchId, b.BatchCode, b.FarmId, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId)
    ORDER BY b.BatchId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
) AS p
JOIN trace.Farm AS f ON f.FarmId = p.FarmId
ORDER BY p.BatchId;';
DECLARE @params NVARCHAR(200) = N'@Status NVARCHAR(20), @PageNumber INT, @PageSize INT';
DECLARE @i INT = 1;
DECLARE @start DATETIME2(3);
WHILE @i <= 5
BEGIN
    PRINT CONCAT(N'--- G2b pair ', @i, N': default ---');
    SET @start = SYSDATETIME();
    EXEC sys.sp_executesql @sqlDefault, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
    PRINT CONCAT(N'default elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));

    PRINT CONCAT(N'--- G2b pair ', @i, N': candidate ---');
    SET @start = SYSDATETIME();
    EXEC sys.sp_executesql @sqlCandidate, @params, @Status = NULL, @PageNumber = 66667, @PageSize = 15;
    PRINT CONCAT(N'candidate elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));

    SET @i += 1;
END;
GO

/* ---------- G2c: identical rows, same order, for 6 cases (the results go into table variables) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @sqlDefault NVARCHAR(MAX) = N'SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
FROM trace.Batch AS b
JOIN trace.Farm AS f ON f.FarmId = b.FarmId
WHERE (@Status IS NULL OR b.Status = @Status)
  AND (@FarmId IS NULL OR b.FarmId = @FarmId)
ORDER BY b.BatchId
OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
FETCH NEXT @PageSize ROWS ONLY;';
DECLARE @sqlCandidate NVARCHAR(MAX) = N'SELECT p.BatchCode, f.Code AS FarmCode, p.Variety, p.HarvestDate, p.QuantityKg, p.Status
FROM (
    SELECT b.BatchId, b.BatchCode, b.FarmId, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId)
    ORDER BY b.BatchId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY
) AS p
JOIN trace.Farm AS f ON f.FarmId = p.FarmId
ORDER BY p.BatchId;';
DECLARE @params NVARCHAR(200) = N'@Status NVARCHAR(20), @FarmId INT, @PageNumber INT, @PageSize INT';
DECLARE @f001 INT = (SELECT FarmId FROM trace.Farm WHERE Code = N'F001');
DECLARE @f021 INT = (SELECT FarmId FROM trace.Farm WHERE Code = N'F021');
DECLARE @a TABLE (Seq INT IDENTITY(1, 1), BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
                  HarvestDate DATE, QuantityKg DECIMAL(10, 2), Status NVARCHAR(20));
DECLARE @b TABLE (Seq INT IDENTITY(1, 1), BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
                  HarvestDate DATE, QuantityKg DECIMAL(10, 2), Status NVARCHAR(20));
DECLARE @k INT = 1;
DECLARE @s NVARCHAR(20);
DECLARE @fid INT;
DECLARE @pn INT;
WHILE @k <= 6
BEGIN
    SELECT @s = CASE WHEN @k = 3 THEN N'RECEIVED' WHEN @k = 5 THEN N'SHIPPED' ELSE NULL END,
           @fid = CASE WHEN @k = 4 THEN @f001 WHEN @k = 5 THEN @f021 ELSE NULL END,
           @pn = CASE @k WHEN 1 THEN 1 WHEN 2 THEN 66667 WHEN 3 THEN 2 WHEN 4 THEN 3 WHEN 5 THEN 1 ELSE 66668 END;
    INSERT INTO @a (BatchCode, FarmCode, Variety, HarvestDate, QuantityKg, Status)
        EXEC sys.sp_executesql @sqlDefault, @params, @Status = @s, @FarmId = @fid, @PageNumber = @pn, @PageSize = 15;
    INSERT INTO @b (BatchCode, FarmCode, Variety, HarvestDate, QuantityKg, Status)
        EXEC sys.sp_executesql @sqlCandidate, @params, @Status = @s, @FarmId = @fid, @PageNumber = @pn, @PageSize = 15;
    SET @k += 1;
END;
DECLARE @nA INT = (SELECT COUNT(*) FROM @a);
DECLARE @nB INT = (SELECT COUNT(*) FROM @b);
DECLARE @listA NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(BatchCode, N'|', FarmCode, N'|', Variety, N'|', HarvestDate, N'|', QuantityKg, N'|', Status), N';')
                                       WITHIN GROUP (ORDER BY Seq) FROM @a);
DECLARE @listB NVARCHAR(MAX) = (SELECT STRING_AGG(CONCAT(BatchCode, N'|', FarmCode, N'|', Variety, N'|', HarvestDate, N'|', QuantityKg, N'|', Status), N';')
                                       WITHIN GROUP (ORDER BY Seq) FROM @b);
PRINT CONCAT(N'cases: 6 | rows default: ', @nA, N' | rows candidate: ', @nB,
             N' | identical, same order: ',
             CASE WHEN @listA = @listB OR (@listA IS NULL AND @listB IS NULL) THEN N'yes' ELSE N'no' END);
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
