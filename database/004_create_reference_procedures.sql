/*
  004_create_reference_procedures.sql
  Creates the 3 stored procedures for reference data in the database named in DbName:
    trace.CreateFarm, trace.CreateStation, trace.AddStationCapability.
  Contract: docs/procedures.md. Errors use THROW with the numbers listed there.

  - Replayable: CREATE OR ALTER replaces a procedure that already exists.
  - Run 001 and 002 first, with the same DbName.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode).
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
/* trace.CreateFarm                                                   */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.CreateFarm
    @Code   NVARCHAR(20),
    @Name   NVARCHAR(100),
    @Region NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(2048);

    -- 1. The code must not be empty (NULL counts as empty).
    IF @Code IS NULL OR LEN(TRIM(@Code)) = 0
    BEGIN
        THROW 50400, N'The code must not be empty.', 1;
    END;

    -- 2. The code must not be taken yet (the comparison ignores the case).
    IF EXISTS (SELECT 1 FROM trace.Farm WHERE Code = @Code)
    BEGIN
        SET @msg = CONCAT(N'Farm code ''', @Code, N''' already exists.');
        THROW 50200, @msg, 1;
    END;

    -- OUTPUT sends the created row back to the caller.
    INSERT trace.Farm (Code, Name, Region)
    OUTPUT inserted.FarmId, inserted.Code, inserted.Name, inserted.Region
    VALUES (@Code, @Name, @Region);
END;
GO

/* ------------------------------------------------------------------ */
/* trace.CreateStation                                                */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.CreateStation
    @Code NVARCHAR(20),
    @Name NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @msg NVARCHAR(2048);

    -- 1. The code must not be empty (NULL counts as empty).
    IF @Code IS NULL OR LEN(TRIM(@Code)) = 0
    BEGIN
        THROW 50400, N'The code must not be empty.', 1;
    END;

    -- 2. The code must not be taken yet.
    IF EXISTS (SELECT 1 FROM trace.Station WHERE Code = @Code)
    BEGIN
        SET @msg = CONCAT(N'Station code ''', @Code, N''' already exists.');
        THROW 50201, @msg, 1;
    END;

    INSERT trace.Station (Code, Name)
    OUTPUT inserted.StationId, inserted.Code, inserted.Name
    VALUES (@Code, @Name);
END;
GO

/* ------------------------------------------------------------------ */
/* trace.AddStationCapability                                         */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.AddStationCapability
    @StationCode  NVARCHAR(20),
    @MovementType NVARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StationId INT;
    DECLARE @msg NVARCHAR(2048);

    -- 1. The movement type must be known (NULL counts as unknown).
    IF @MovementType IS NULL
       OR @MovementType NOT IN (N'RECEPTION', N'SORTING', N'PACKING', N'SHIPMENT')
    BEGIN
        SET @msg = CONCAT(N'Unknown movement type ''', @MovementType, N'''.');
        THROW 50402, @msg, 1;
    END;

    -- The comparison above ignores the case: always store the type in capitals.
    SET @MovementType = UPPER(@MovementType);

    -- 2. The station must exist.
    SELECT @StationId = StationId
    FROM trace.Station
    WHERE Code = @StationCode;

    IF @StationId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
        THROW 50102, @msg, 1;
    END;

    -- 3. The function must not be declared yet for this station.
    IF EXISTS (SELECT 1 FROM trace.StationCapability
               WHERE StationId = @StationId AND MovementType = @MovementType)
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' already has the function ''', @MovementType, N'''.');
        THROW 50203, @msg, 1;
    END;

    INSERT trace.StationCapability (StationId, MovementType)
    VALUES (@StationId, @MovementType);
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
