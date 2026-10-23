/*
  015_measure_lot5_t2.sql
  Trial T2 of lot 5 on TraceabilityDev: the total of trace.ListBatches, before and after a
  trial index. READ ONLY: this script changes nothing.

  - Runs ONLY on TraceabilityDev, with the full set of 1000000 batches (007 + 008) and the
    procedure trace.ListBatches of 005. The name is written in the script, so SQLCMD mode
    is not needed.
  - Contains no INSERT, UPDATE, DROP, TRUNCATE or DELETE statement, and no index creation:
    the trial index is created and dropped by hand, in a separate throwaway SSMS window that
    is not saved. The commands are written in docs/mesures.md, section 9.3.
  - Hypothesis T2 and the decision rule: docs/mesures.md, sections 6.3 and 6.4.
  - Run it BEFORE the first trial index (the "before" is already in docs/mesures.md, section
    7, and is measured again here to compare in the same conditions), then AFTER each trial
    index, and once more after each DROP.

  How to use it in SSMS:
    - Do NOT run the whole file with F5. Select ONE block (from its title comment to its GO)
      and run it. Each block sets what it needs and checks the database name.
    - T2a-1 to T2a-4 (plans): turn the actual execution plan ON first (Ctrl+M). One run each.
    - T2b (repeated runs): turn the actual execution plan OFF (Ctrl+M). 5 runs of each of the
      4 cases.
    - T2c: the indexes of trace.Batch and their size. No plan needed.

  What to note:
    - T2a: tab Messages (logical reads of Batch for EACH statement: the page FIRST, then the
      total) and, in the plan of the SECOND statement (the total), the operator on trace.Batch:
      Scan or Seek, and on which index; the rows read.
    - T2b: for each run, the logical reads of the total (second statement) and the line
      "elapsed ms".
    - T2c: the list of indexes with their size.
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
/* T2a - plans (Ctrl+M ON). One run per block.                         */
/* ================================================================== */

/* ---------- T2a-1: the total without filter ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== T2a-1: ListBatches, no filter, page 1 of 15 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = NULL, @PageNumber = 1, @PageSize = 15;
GO

/* ---------- T2a-2: the total for farm F001 (25000 batches) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== T2a-2: ListBatches, farm F001, page 1 of 15 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = N'F001', @PageNumber = 1, @PageSize = 15;
GO

/* ---------- T2a-3: the total for farm F021 (2777 batches) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== T2a-3: ListBatches, farm F021, page 1 of 15 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = N'F021', @PageNumber = 1, @PageSize = 15;
GO

/* ---------- T2a-4: the total for status RECEIVED (100000 batches) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== T2a-4: ListBatches, status RECEIVED, page 1 of 15 ===';
EXEC trace.ListBatches @Status = N'RECEIVED', @FarmCode = NULL, @PageNumber = 1, @PageSize = 15;
GO

/* ================================================================== */
/* T2b - repeated runs (Ctrl+M OFF). 5 runs of each of the 4 cases.    */
/* ================================================================== */

/* ---------- T2b: 4 cases, 5 runs each ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @case INT = 1;
DECLARE @i INT;
DECLARE @start DATETIME2(3);
DECLARE @status NVARCHAR(20);
DECLARE @farm NVARCHAR(20);
DECLARE @label NVARCHAR(40);
WHILE @case <= 4
BEGIN
    SELECT @status = CASE WHEN @case = 4 THEN N'RECEIVED' ELSE NULL END,
           @farm = CASE WHEN @case = 2 THEN N'F001' WHEN @case = 3 THEN N'F021' ELSE NULL END,
           @label = CHOOSE(@case, N'no filter', N'farm F001', N'farm F021', N'status RECEIVED');
    SET @i = 1;
    WHILE @i <= 5
    BEGIN
        PRINT CONCAT(N'--- T2b ', @label, N', run ', @i, N' ---');
        SET @start = SYSDATETIME();
        EXEC trace.ListBatches @Status = @status, @FarmCode = @farm, @PageNumber = 1, @PageSize = 15;
        PRINT CONCAT(N'elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));
        SET @i += 1;
    END;
    SET @case += 1;
END;
GO

/* ================================================================== */
/* T2c - the indexes of trace.Batch and their size (read only)         */
/* ================================================================== */

/* ---------- T2c: indexes and size ---------- */
SET NOCOUNT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
SELECT i.name AS index_name,
       i.type_desc,
       SUM(ps.used_page_count) AS used_pages,
       CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS DECIMAL(10, 2)) AS used_mb
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS ps
    ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'trace.Batch')
GROUP BY i.name, i.type_desc
ORDER BY i.name;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
