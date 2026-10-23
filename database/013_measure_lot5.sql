/*
  013_measure_lot5.sql
  Measures the total and the last page of trace.ListBatches on TraceabilityDev (lot 5).
  READ ONLY: it changes nothing.

  - Runs ONLY on TraceabilityDev, with the full set of 1000000 batches (007 + 008) and the
    procedure trace.ListBatches of 005 (the script stops with an error if they are missing).
    The name is written in the script, so SQLCMD mode is not needed.
  - Contains no INSERT, UPDATE, DROP, TRUNCATE, DELETE, CREATE or ALTER.
  - It calls the real procedure, so it measures what the API does.
  - Used BEFORE and AFTER each trial of lot 5 (see docs/mesures.md, section 6).

  How to use it in SSMS:
    - Do NOT run the whole file with F5. Select ONE block (from its title comment to its GO)
      and run it. Each block sets what it needs and checks the database name.
    - Part A (plans): turn the actual execution plan ON first (Ctrl+M).
    - Part B (repeated runs): turn the actual execution plan OFF (Ctrl+M).
    - Part C (plan cache): run it right AFTER one call of the API on the last page
      (the "Last" button of the interface, or GET /batches?pageNumber=66667&pageSize=15).
      It reads system views and may fail or return no row (a read of
      sys.dm_exec_procedure_stats returned 0 rows in lot 4a).

  What to note for each run:
    - Tab Messages: "logical reads" of Batch and Farm, for EACH statement of the procedure.
      ListBatches runs two statements: the page FIRST, then the total (a COUNT on Batch).
    - Tab Execution plan (part A): for each statement, the main operators (Scan or Seek and
      on which index, parallelism, Sort and whether it spills to tempdb, actual rows).
    - Part B: the "elapsed ms" line of each run (the whole procedure, page and total).
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
/* PART A - plans (Ctrl+M ON). One run per block.                      */
/* ================================================================== */

/* ---------- A1 (T1): the total without filter ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== A1: ListBatches, no filter, page 1 of 15. The total is the SECOND statement ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = NULL, @PageNumber = 1, @PageSize = 15;
GO

/* ---------- A2 (T2, "before"): the total with a filter ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== A2a: ListBatches, farm F001 (25000 batches), page 1 of 15 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = N'F001', @PageNumber = 1, @PageSize = 15;
PRINT N'=== A2b: ListBatches, farm F021 (2777 batches), page 1 of 15 ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = N'F021', @PageNumber = 1, @PageSize = 15;
PRINT N'=== A2c: ListBatches, status RECEIVED (100000 batches), page 1 of 15 ===';
EXEC trace.ListBatches @Status = N'RECEIVED', @FarmCode = NULL, @PageNumber = 1, @PageSize = 15;
GO

/* ---------- A3 (F2): the last page, no filter ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
PRINT N'=== A3: ListBatches, no filter, page 66667 of 15 (999990 rows skipped) ===';
EXEC trace.ListBatches @Status = NULL, @FarmCode = NULL, @PageNumber = 66667, @PageSize = 15;
GO

/* ================================================================== */
/* PART B - repeated runs (Ctrl+M OFF). 5 runs per block.              */
/* ================================================================== */

/* ---------- B1: the last page, 5 runs ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @i INT = 1;
DECLARE @start DATETIME2(3);
WHILE @i <= 5
BEGIN
    PRINT CONCAT(N'--- B1 run ', @i, N': page 66667 of 15, no filter ---');
    SET @start = SYSDATETIME();
    EXEC trace.ListBatches @Status = NULL, @FarmCode = NULL, @PageNumber = 66667, @PageSize = 15;
    PRINT CONCAT(N'elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));
    SET @i += 1;
END;
GO

/* ---------- B2: the first page, 5 runs (the cost of the total is in each run) ---------- */
SET NOCOUNT ON;
SET STATISTICS IO ON;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
DECLARE @i INT = 1;
DECLARE @start DATETIME2(3);
WHILE @i <= 5
BEGIN
    PRINT CONCAT(N'--- B2 run ', @i, N': page 1 of 15, no filter ---');
    SET @start = SYSDATETIME();
    EXEC trace.ListBatches @Status = NULL, @FarmCode = NULL, @PageNumber = 1, @PageSize = 15;
    PRINT CONCAT(N'elapsed ms: ', DATEDIFF(MILLISECOND, @start, SYSDATETIME()));
    SET @i += 1;
END;
GO

/* ================================================================== */
/* PART C - plans kept in memory for trace.ListBatches (read only).    */
/* Run it right after one call of the API on the last page.            */
/* One row per statement and per plan. set_options differs between    */
/* SSMS and the API; the bit 4096 is ARITHABORT (see the documentation */
/* of sys.dm_exec_plan_attributes). Click query_plan to open the plan. */
/* ================================================================== */

/* ---------- C1: plans in the cache ---------- */
SET NOCOUNT ON;
SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
IF DB_NAME() <> N'TraceabilityDev' THROW 50001, N'Wrong database. Nothing was done.', 1;
SELECT
    qs.creation_time,
    qs.last_execution_time,
    qs.execution_count,
    CAST(pa.value AS INT) AS set_options,
    CASE WHEN (CAST(pa.value AS INT) & 4096) = 4096 THEN N'ON' ELSE N'OFF' END AS arithabort,
    qs.last_dop,
    qs.last_grant_kb,
    qs.last_spills,
    qs.last_logical_reads,
    qs.last_elapsed_time / 1000 AS last_elapsed_ms,
    qs.max_elapsed_time / 1000 AS max_elapsed_ms,
    qs.total_worker_time / 1000 AS total_cpu_ms,
    SUBSTRING(
        st.text,
        (qs.statement_start_offset / 2) + 1,
        ((CASE WHEN qs.statement_end_offset = -1
               THEN DATALENGTH(st.text)
               ELSE qs.statement_end_offset END
          - qs.statement_start_offset) / 2) + 1) AS statement_text,
    qp.query_plan
FROM sys.dm_exec_query_stats AS qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
OUTER APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
WHERE st.dbid = DB_ID()
  AND st.objectid = OBJECT_ID(N'trace.ListBatches')
  AND pa.attribute = N'set_options'
ORDER BY qs.last_execution_time DESC, qs.statement_start_offset;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
