/*
  011_create_list_procedures.sql
  Creates the 3 stored procedures that read reference data in the database named in DbName:
    trace.ListFarms, trace.ListStations, trace.GetStation.
  Contract: docs/procedures.md. Errors use THROW with the numbers listed there.

  - Replayable: CREATE OR ALTER replaces a procedure that already exists.
  - Run 001, 002, 004 and 005 first, with the same DbName.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode).
  - Run it on TraceabilityDev (for the API) and on TraceabilityTest (for the tests).
  - Contains no DROP, TRUNCATE or DELETE.
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
/* trace.ListFarms                                                    */
/* Result 1: one page of farms, in the order they were created.       */
/* Result 2: the total number of farms (one row, one column).         */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.ListFarms
    @PageNumber INT,
    @PageSize   INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Page number from 1, page size from 1 to 1000 (NULL counts as invalid).
    IF @PageNumber IS NULL OR @PageNumber < 1
       OR @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 1000
    BEGIN
        THROW 50404, N'Invalid page number or page size.', 1;
    END;

    -- CAST to BIGINT: a huge page number must not overflow the calculation.
    SELECT Code, Name, Region
    FROM trace.Farm
    ORDER BY FarmId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    -- The total is read by a separate query, without a lock (like GetBatch).
    SELECT COUNT(*) AS TotalCount
    FROM trace.Farm;
END;
GO

/* ------------------------------------------------------------------ */
/* trace.ListStations                                                 */
/* Result 1: one page of stations, in the order they were created.    */
/* Result 2: the total number of stations (one row, one column).      */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.ListStations
    @PageNumber INT,
    @PageSize   INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Page number from 1, page size from 1 to 1000 (NULL counts as invalid).
    IF @PageNumber IS NULL OR @PageNumber < 1
       OR @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 1000
    BEGIN
        THROW 50404, N'Invalid page number or page size.', 1;
    END;

    SELECT Code, Name
    FROM trace.Station
    ORDER BY StationId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM trace.Station;
END;
GO

/* ------------------------------------------------------------------ */
/* trace.GetStation                                                   */
/* Result 1: the station. Result 2: its functions, in the order of    */
/* the life cycle (RECEPTION, SORTING, PACKING, SHIPMENT). The second */
/* result is empty if the station has no function yet.                */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.GetStation
    @StationCode NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StationId INT;
    DECLARE @msg NVARCHAR(2048);

    -- 1. The station must exist (a NULL code finds nothing, so it is refused too).
    SELECT @StationId = StationId
    FROM trace.Station
    WHERE Code = @StationCode;

    IF @StationId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
        THROW 50102, @msg, 1;
    END;

    SELECT Code, Name
    FROM trace.Station
    WHERE StationId = @StationId;

    SELECT MovementType
    FROM trace.StationCapability
    WHERE StationId = @StationId
    ORDER BY CASE MovementType
                 WHEN N'RECEPTION' THEN 1
                 WHEN N'SORTING'   THEN 2
                 WHEN N'PACKING'   THEN 3
                 WHEN N'SHIPMENT'  THEN 4
             END;
END;
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO

-- Check (read only): the procedures of the schema trace.
SELECT s.name AS schema_name, p.name AS procedure_name
FROM sys.procedures AS p
JOIN sys.schemas AS s ON s.schema_id = p.schema_id
WHERE s.name = N'trace'
ORDER BY p.name;
GO
