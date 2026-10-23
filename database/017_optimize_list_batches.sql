/*
  017_optimize_list_batches.sql
  Lot 5: makes trace.ListBatches cheaper, in the database named in DbName.
    1. Creates the index IX_Batch_FarmId on trace.Batch (FarmId), only if it does not exist.
    2. Replaces trace.ListBatches (CREATE OR ALTER):
       - the page is cut in trace.Batch alone BEFORE the join with trace.Farm, so that SQL
         Server reads the primary key in order and does not sort the whole table;
       - the total is written with OPTION (RECOMPILE), so that its plan is built for the
         filters of the call and can use IX_Batch_FarmId.
  The contract does not change: same parameters, same errors (50403, 50101, 50404), same two
  result sets in the same order (the page, then the total), same columns, same rows, same order.
  Why and how it was measured: docs/mesures.md (sections 7 to 9.5) and docs/adr/0008.

  - Replayable: the index is created only if it does not exist; CREATE OR ALTER replaces the
    procedure.
  - Run 001, 002, 004 and 005 first, with the same DbName.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode).
  - Run it on TraceabilityDev (for the API) and on TraceabilityTest (for the tests).
  - Stop the API first. On TraceabilityDev (1000000 batches) the index takes about 1 min 30 to
    build and uses about 14 MB (13.57 MB measured, docs/mesures.md 9.3).
  - Contains no DROP, TRUNCATE or DELETE statement. It does not change any row.
  - To undo: run the ListBatches part of 005 again (CREATE OR ALTER puts the previous text back)
    and remove the index IX_Batch_FarmId (see docs/adr/0008).
*/

:setvar DbName TraceabilityDev

USE $(DbName);
GO

-- Safety: if the connection is not on $(DbName) (wrong database, or SQLCMD mode
-- is off), nothing below is executed. SET NOEXEC ON makes SQL Server read the
-- next batches without running them. It is turned off again at the end.
IF DB_NAME() <> N'$(DbName)'
BEGIN
    RAISERROR(N'Wrong database or SQLCMD mode is off. Expected $(DbName). Nothing was created.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------ */
/* 1. IX_Batch_FarmId                                                 */
/* Lets SQL Server count the batches of one farm by reading a small   */
/* index instead of the whole table (docs/mesures.md, sections 9.3    */
/* and 9.4). It is used only when the plan is built for the farm, see */
/* OPTION (RECOMPILE) below.                                          */
/* ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1
               FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'trace.Batch')
                 AND name = N'IX_Batch_FarmId')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Batch_FarmId
        ON trace.Batch (FarmId);
    PRINT N'Index IX_Batch_FarmId created.';
END
ELSE
BEGIN
    PRINT N'Index IX_Batch_FarmId already exists. Nothing done.';
END;
GO

/* ------------------------------------------------------------------ */
/* trace.ListBatches                                                  */
/* Result 1: one page of batches, by batch number. Both filters       */
/* are optional (NULL = no filter).                                   */
/* Result 2: the total number of batches that match the filters       */
/* (one row, one column), read by a separate query, without a lock.   */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.ListBatches
    @Status     NVARCHAR(20) = NULL,
    @FarmCode   NVARCHAR(20) = NULL,
    @PageNumber INT,
    @PageSize   INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FarmId INT;
    DECLARE @msg NVARCHAR(2048);

    -- 1. The status must be known (if given).
    IF @Status IS NOT NULL
       AND @Status NOT IN (N'RECEIVED', N'SORTED', N'PACKED', N'SHIPPED')
    BEGIN
        SET @msg = CONCAT(N'Unknown status ''', @Status, N'''.');
        THROW 50403, @msg, 1;
    END;

    -- 2. The farm must exist (if given).
    IF @FarmCode IS NOT NULL
    BEGIN
        SELECT @FarmId = FarmId
        FROM trace.Farm
        WHERE Code = @FarmCode;

        IF @FarmId IS NULL
        BEGIN
            SET @msg = CONCAT(N'Farm ''', @FarmCode, N''' was not found.');
            THROW 50101, @msg, 1;
        END;
    END;

    -- 3. Page number from 1, page size from 1 to 1000.
    IF @PageNumber IS NULL OR @PageNumber < 1
       OR @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 1000
    BEGIN
        THROW 50404, N'Invalid page number or page size.', 1;
    END;

    -- The page is cut in trace.Batch alone, then joined with trace.Farm for the rows of the
    -- page only: SQL Server reads the primary key in order and has nothing to sort.
    -- CAST to BIGINT: a huge page number must not overflow the calculation.
    -- The outer ORDER BY keeps the order of the page after the join.
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
    ORDER BY p.BatchId;

    -- The total uses the same filters as the page. OPTION (RECOMPILE): the plan is built for
    -- the filters of this call, so that SQL Server can use IX_Batch_FarmId (a plan built once
    -- for all the calls reads the whole table). Keep it a returned result (SELECT COUNT(*)),
    -- not an assignment to a variable: with an assignment, SQL Server read the whole table
    -- in the measurements (docs/mesures.md, 9.4).
    SELECT COUNT(*) AS TotalCount
    FROM trace.Batch AS b
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId)
    OPTION (RECOMPILE);
END;
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO

-- Check (read only): the indexes of trace.Batch and the procedure ListBatches.
SELECT i.name AS index_name, i.type_desc
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'trace.Batch') AND i.name IS NOT NULL
ORDER BY i.name;

SELECT s.name AS schema_name, p.name AS procedure_name, p.modify_date
FROM sys.procedures AS p
JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'trace' AND p.name = N'ListBatches';
GO
