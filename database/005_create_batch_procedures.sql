/*
  005_create_batch_procedures.sql
  Creates the 4 stored procedures for batches in the database named in DbName:
    trace.CreateBatch, trace.AddMovement, trace.GetBatch, trace.ListBatches.
  Contract: docs/procedures.md. Locking choice: docs/adr/0003-verrou-sur-le-lot.md.
  Errors use THROW with the numbers listed in docs/procedures.md.

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
/* trace.CreateBatch                                                  */
/* Creates the batch (status RECEIVED) and its first movement         */
/* (RECEPTION) in one transaction.                                    */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.CreateBatch
    @BatchCode   NVARCHAR(30),
    @FarmCode    NVARCHAR(20),
    @Variety     NVARCHAR(50),
    @HarvestDate DATE,
    @QuantityKg  DECIMAL(10,2),
    @StationCode NVARCHAR(20),
    @OccurredAt  DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FarmId INT;
    DECLARE @StationId INT;
    DECLARE @BatchId INT;
    DECLARE @msg NVARCHAR(2048);

    -- 1. The batch code must not be empty (NULL counts as empty).
    IF @BatchCode IS NULL OR LEN(TRIM(@BatchCode)) = 0
    BEGIN
        THROW 50400, N'The code must not be empty.', 1;
    END;

    -- 2. The quantity must be greater than 0 (NULL counts as invalid).
    IF @QuantityKg IS NULL OR @QuantityKg <= 0
    BEGIN
        THROW 50401, N'The quantity must be greater than 0.', 1;
    END;

    -- 3. The farm must exist.
    SELECT @FarmId = FarmId
    FROM trace.Farm
    WHERE Code = @FarmCode;

    IF @FarmId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Farm ''', @FarmCode, N''' was not found.');
        THROW 50101, @msg, 1;
    END;

    -- 4. The station must exist.
    SELECT @StationId = StationId
    FROM trace.Station
    WHERE Code = @StationCode;

    IF @StationId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
        THROW 50102, @msg, 1;
    END;

    -- 5. The batch code must not be taken yet.
    IF EXISTS (SELECT 1 FROM trace.Batch WHERE BatchCode = @BatchCode)
    BEGIN
        SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' already exists.');
        THROW 50202, @msg, 1;
    END;

    -- 6. The station must have the RECEPTION function.
    IF NOT EXISTS (SELECT 1 FROM trace.StationCapability
                   WHERE StationId = @StationId AND MovementType = N'RECEPTION')
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' does not have the function ''RECEPTION''.');
        THROW 50303, @msg, 1;
    END;

    -- The batch and its first movement: both are created, or none.
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (@BatchCode, @FarmId, @Variety, @HarvestDate, @QuantityKg, N'RECEIVED');

        SET @BatchId = SCOPE_IDENTITY();

        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        VALUES (@BatchId, @StationId, N'RECEPTION', @QuantityKg, @OccurredAt);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- raise the original error again
    END CATCH;
END;
GO

/* ------------------------------------------------------------------ */
/* trace.AddMovement                                                  */
/* Adds the next movement of a batch and updates the batch, in one    */
/* transaction. The batch row is locked first (ADR 0003): a second    */
/* call on the same batch waits, then reads the updated batch.        */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.AddMovement
    @BatchCode    NVARCHAR(30),
    @StationCode  NVARCHAR(20),
    @MovementType NVARCHAR(20),
    @QuantityKg   DECIMAL(10,2),
    @OccurredAt   DATETIME2
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId INT;
    DECLARE @StationId INT;
    DECLARE @CurrentStatus NVARCHAR(20);
    DECLARE @CurrentQuantity DECIMAL(10,2);
    DECLARE @ExpectedType NVARCHAR(20);
    DECLARE @NewStatus NVARCHAR(20);
    DECLARE @msg NVARCHAR(2048);

    -- 1. The quantity must be greater than 0 (NULL counts as invalid).
    IF @QuantityKg IS NULL OR @QuantityKg <= 0
    BEGIN
        THROW 50401, N'The quantity must be greater than 0.', 1;
    END;

    -- 2. The movement type must be known (NULL counts as unknown).
    IF @MovementType IS NULL
       OR @MovementType NOT IN (N'RECEPTION', N'SORTING', N'PACKING', N'SHIPMENT')
    BEGIN
        SET @msg = CONCAT(N'Unknown movement type ''', @MovementType, N'''.');
        THROW 50402, @msg, 1;
    END;

    -- The comparison above ignores the case: always use the type in capitals.
    SET @MovementType = UPPER(@MovementType);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 3. The batch must exist. It is read AND locked (UPDLOCK) until the end
        --    of the transaction, so nobody else can change it meanwhile.
        SELECT @BatchId = BatchId,
               @CurrentStatus = Status,
               @CurrentQuantity = QuantityKg
        FROM trace.Batch WITH (UPDLOCK)
        WHERE BatchCode = @BatchCode;

        IF @BatchId IS NULL
        BEGIN
            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
            THROW 50100, @msg, 1;
        END;

        -- 4. The station must exist.
        SELECT @StationId = StationId
        FROM trace.Station
        WHERE Code = @StationCode;

        IF @StationId IS NULL
        BEGIN
            SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
            THROW 50102, @msg, 1;
        END;

        -- 5. A SHIPPED batch accepts no new movement.
        IF @CurrentStatus = N'SHIPPED'
        BEGIN
            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' is already SHIPPED: no new movement.');
            THROW 50300, @msg, 1;
        END;

        -- 6. The movement must be the next step (no step skipped, none repeated).
        SET @ExpectedType = CASE @CurrentStatus
                                WHEN N'RECEIVED' THEN N'SORTING'
                                WHEN N'SORTED'   THEN N'PACKING'
                                WHEN N'PACKED'   THEN N'SHIPMENT'
                            END;

        IF @ExpectedType IS NULL OR @MovementType <> @ExpectedType
        BEGIN
            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' is ', @CurrentStatus,
                              N': the next movement must be ', @ExpectedType,
                              N', not ', @MovementType, N'.');
            THROW 50301, @msg, 1;
        END;

        -- 7. The station must have the function.
        IF NOT EXISTS (SELECT 1 FROM trace.StationCapability
                       WHERE StationId = @StationId AND MovementType = @MovementType)
        BEGIN
            SET @msg = CONCAT(N'Station ''', @StationCode, N''' does not have the function ''', @MovementType, N'''.');
            THROW 50303, @msg, 1;
        END;

        -- 8. The quantity must not go up (an equal quantity is accepted).
        IF @QuantityKg > @CurrentQuantity
        BEGIN
            SET @msg = CONCAT(N'Quantity ', CAST(@QuantityKg AS NVARCHAR(20)),
                              N' is higher than the current quantity ',
                              CAST(@CurrentQuantity AS NVARCHAR(20)), N'.');
            THROW 50302, @msg, 1;
        END;

        SET @NewStatus = CASE @MovementType
                             WHEN N'SORTING'  THEN N'SORTED'
                             WHEN N'PACKING'  THEN N'PACKED'
                             WHEN N'SHIPMENT' THEN N'SHIPPED'
                         END;

        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        VALUES (@BatchId, @StationId, @MovementType, @QuantityKg, @OccurredAt);

        UPDATE trace.Batch
        SET Status = @NewStatus,
            QuantityKg = @QuantityKg
        WHERE BatchId = @BatchId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- raise the original error again
    END CATCH;
END;
GO

/* ------------------------------------------------------------------ */
/* trace.GetBatch                                                     */
/* Result 1: the batch. Result 2: its movements, in the order they    */
/* were recorded.                                                     */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.GetBatch
    @BatchCode NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BatchId INT;
    DECLARE @msg NVARCHAR(2048);

    SELECT @BatchId = BatchId
    FROM trace.Batch
    WHERE BatchCode = @BatchCode;

    IF @BatchId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
        THROW 50100, @msg, 1;
    END;

    SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    JOIN trace.Farm AS f ON f.FarmId = b.FarmId
    WHERE b.BatchId = @BatchId;

    SELECT m.MovementId, m.MovementType, s.Code AS StationCode, m.QuantityKg, m.OccurredAt
    FROM trace.Movement AS m
    JOIN trace.Station AS s ON s.StationId = m.StationId
    WHERE m.BatchId = @BatchId
    ORDER BY m.MovementId;
END;
GO

/* ------------------------------------------------------------------ */
/* trace.ListBatches                                                  */
/* One page of batches, by batch number. Both filters are optional    */
/* (NULL = no filter).                                                */
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

    -- CAST to BIGINT: a huge page number must not overflow the calculation.
    SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    JOIN trace.Farm AS f ON f.FarmId = b.FarmId
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId)
    ORDER BY b.BatchId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
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
