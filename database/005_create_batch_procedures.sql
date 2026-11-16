/*
  005_create_batch_procedures.sql
  Creates the 7 stored procedures for batches in the database named in DbName:
    trace.CreateBatch, trace.AddMovement, trace.ReplaceMovement, trace.CancelMovement,
    trace.CorrectBatch, trace.GetBatch, trace.ListBatches.
  Contract: docs/procedures.md. Locking choice: docs/adr/0003-verrou-sur-le-lot.md.
  Errors use THROW with the numbers listed in docs/procedures.md.
  Lot 11: CreateBatch and AddMovement also take the author of the movement (@AuthorId and
  @AuthorName, read from the validated token by the API). GetBatch returns the author name
  of each movement. Errors 50405 (empty author) and 50406 (author too long) are new.
  Lot 12a: ReplaceMovement and CancelMovement correct a movement without changing it: they add a
  row to trace.MovementCorrection. GetBatch returns the valid version of each movement, its
  original values, and the list of the corrections. New errors: 50103 (movement not found in the
  batch), 50304 to 50308 (business rules of the corrections), 50407 to 50409 (reason and comment).
  Lot 12b: CorrectBatch corrects the sheet of a batch (code, farm, variety, harvest date) without
  losing the old values: it adds a row to trace.BatchCorrection and updates trace.Batch in the same
  transaction. GetBatch also finds a batch by an old code, and returns the corrections of the sheet
  as a fourth result. The procedures that write refuse an old code. CreateBatch and ReplaceMovement
  refuse a harvest date after the reception. New errors: 50104 (old code used to write), 50203 (code
  kept for another batch), 50309 (harvest date after the reception).

  - Replayable: CREATE OR ALTER replaces a procedure that already exists.
  - Run 001 and 002 first, with the same DbName. A database created before lot 12a needs
    019_add_movement_correction.sql first, and one created before lot 12b needs
    020_add_batch_correction.sql too.
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
/* The author is recorded on that movement (lot 11).                  */
/* Lot 12b: an old code of another batch is refused (50203), and      */
/* so is a harvest date after the reception (50309).                  */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.CreateBatch
    @BatchCode   NVARCHAR(30),
    @FarmCode    NVARCHAR(20),
    @Variety     NVARCHAR(50),
    @HarvestDate DATE,
    @QuantityKg  DECIMAL(10,2),
    @StationCode NVARCHAR(20),
    @OccurredAt  DATETIME2,
    @AuthorId    NVARCHAR(200),
    @AuthorName  NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FarmId INT;
    DECLARE @StationId INT;
    DECLARE @BatchId INT;
    DECLARE @msg NVARCHAR(2048);

    -- 1. The author must be given (NULL or blank counts as empty). The API reads it from the
    --    validated token; the database does not trust that it did, and checks it too.
    IF @AuthorId IS NULL OR LEN(TRIM(@AuthorId)) = 0
       OR @AuthorName IS NULL OR LEN(TRIM(@AuthorName)) = 0
    BEGIN
        THROW 50405, N'The author must not be empty.', 1;
    END;

    -- 2. The author must fit in the columns (64 and 100 characters): never cut silently.
    --    The parameters are wider than the columns so that a long value reaches this check.
    IF LEN(@AuthorId) > 64 OR LEN(@AuthorName) > 100
    BEGIN
        THROW 50406, N'The author identifier or name is too long.', 1;
    END;

    -- 3. The batch code must not be empty (NULL counts as empty).
    IF @BatchCode IS NULL OR LEN(TRIM(@BatchCode)) = 0
    BEGIN
        THROW 50400, N'The code must not be empty.', 1;
    END;

    -- 4. The quantity must be greater than 0 (NULL counts as invalid).
    IF @QuantityKg IS NULL OR @QuantityKg <= 0
    BEGIN
        THROW 50401, N'The quantity must be greater than 0.', 1;
    END;

    -- 5. The farm must exist.
    SELECT @FarmId = FarmId
    FROM trace.Farm
    WHERE Code = @FarmCode;

    IF @FarmId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Farm ''', @FarmCode, N''' was not found.');
        THROW 50101, @msg, 1;
    END;

    -- 6. The station must exist.
    SELECT @StationId = StationId
    FROM trace.Station
    WHERE Code = @StationCode;

    IF @StationId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
        THROW 50102, @msg, 1;
    END;

    -- 7. The batch code must not be taken yet.
    IF EXISTS (SELECT 1 FROM trace.Batch WHERE BatchCode = @BatchCode)
    BEGIN
        SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' already exists.');
        THROW 50202, @msg, 1;
    END;

    -- 8. The batch code must not be an old code (lot 12b): the old code of a corrected batch stays
    --    kept for that batch, so that a label printed with it still leads to the right batch.
    IF EXISTS (SELECT 1 FROM trace.BatchCorrection WHERE OldBatchCode = @BatchCode)
    BEGIN
        SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' is the old code of another batch.');
        THROW 50203, @msg, 1;
    END;

    -- 9. The station must have the RECEPTION function.
    IF NOT EXISTS (SELECT 1 FROM trace.StationCapability
                   WHERE StationId = @StationId AND MovementType = N'RECEPTION')
    BEGIN
        SET @msg = CONCAT(N'Station ''', @StationCode, N''' does not have the function ''RECEPTION''.');
        THROW 50303, @msg, 1;
    END;

    -- 10. The harvest date must not be after the day of the reception (lot 12b). The same day is
    --     accepted. A NULL date is not compared here: the column refuses it below.
    IF @HarvestDate > CAST(@OccurredAt AS DATE)
    BEGIN
        SET @msg = CONCAT(N'The harvest date ', CONVERT(NVARCHAR(10), @HarvestDate, 23),
                          N' is after the reception date ',
                          CONVERT(NVARCHAR(10), CAST(@OccurredAt AS DATE), 23), N'.');
        THROW 50309, @msg, 1;
    END;

    -- The batch and its first movement: both are created, or none.
    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (@BatchCode, @FarmId, @Variety, @HarvestDate, @QuantityKg, N'RECEIVED');

        SET @BatchId = SCOPE_IDENTITY();

        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt, AuthorId, AuthorName)
        VALUES (@BatchId, @StationId, N'RECEPTION', @QuantityKg, @OccurredAt, @AuthorId, @AuthorName);

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
/* The author of the movement is given by the caller (lot 11).        */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.AddMovement
    @BatchCode    NVARCHAR(30),
    @StationCode  NVARCHAR(20),
    @MovementType NVARCHAR(20),
    @QuantityKg   DECIMAL(10,2),
    @OccurredAt   DATETIME2,
    @AuthorId     NVARCHAR(200),
    @AuthorName   NVARCHAR(200)
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

    -- 1. The author must be given (NULL or blank counts as empty). The API reads it from the
    --    validated token; the database does not trust that it did, and checks it too.
    IF @AuthorId IS NULL OR LEN(TRIM(@AuthorId)) = 0
       OR @AuthorName IS NULL OR LEN(TRIM(@AuthorName)) = 0
    BEGIN
        THROW 50405, N'The author must not be empty.', 1;
    END;

    -- 2. The author must fit in the columns (64 and 100 characters): never cut silently.
    --    The parameters are wider than the columns so that a long value reaches this check.
    IF LEN(@AuthorId) > 64 OR LEN(@AuthorName) > 100
    BEGIN
        THROW 50406, N'The author identifier or name is too long.', 1;
    END;

    -- 3. The quantity must be greater than 0 (NULL counts as invalid).
    IF @QuantityKg IS NULL OR @QuantityKg <= 0
    BEGIN
        THROW 50401, N'The quantity must be greater than 0.', 1;
    END;

    -- 4. The movement type must be known (NULL counts as unknown).
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

        -- 5. The batch must exist. It is read AND locked (UPDLOCK) until the end
        --    of the transaction, so nobody else can change it meanwhile.
        SELECT @BatchId = BatchId,
               @CurrentStatus = Status,
               @CurrentQuantity = QuantityKg
        FROM trace.Batch WITH (UPDLOCK)
        WHERE BatchCode = @BatchCode;

        IF @BatchId IS NULL
        BEGIN
            -- Lot 12b: the code may be an old code of a corrected batch. Writing needs the current
            -- code: the error says which one it is.
            DECLARE @CurrentCode NVARCHAR(30);

            SELECT TOP (1) @CurrentCode = b.BatchCode
            FROM trace.BatchCorrection AS c
            JOIN trace.Batch AS b ON b.BatchId = c.BatchId
            WHERE c.OldBatchCode = @BatchCode
            ORDER BY c.CorrectionId;

            IF @CurrentCode IS NOT NULL
            BEGIN
                SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' was replaced by ''', @CurrentCode, N'''.');
                THROW 50104, @msg, 1;
            END;

            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
            THROW 50100, @msg, 1;
        END;

        -- 6. The station must exist.
        SELECT @StationId = StationId
        FROM trace.Station
        WHERE Code = @StationCode;

        IF @StationId IS NULL
        BEGIN
            SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
            THROW 50102, @msg, 1;
        END;

        -- 7. A SHIPPED batch accepts no new movement.
        IF @CurrentStatus = N'SHIPPED'
        BEGIN
            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' is already SHIPPED: no new movement.');
            THROW 50300, @msg, 1;
        END;

        -- 8. The movement must be the next step (no step skipped, none repeated).
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

        -- 9. The station must have the function.
        IF NOT EXISTS (SELECT 1 FROM trace.StationCapability
                       WHERE StationId = @StationId AND MovementType = @MovementType)
        BEGIN
            SET @msg = CONCAT(N'Station ''', @StationCode, N''' does not have the function ''', @MovementType, N'''.');
            THROW 50303, @msg, 1;
        END;

        -- 10. The quantity must not go up (an equal quantity is accepted).
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

        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt, AuthorId, AuthorName)
        VALUES (@BatchId, @StationId, @MovementType, @QuantityKg, @OccurredAt, @AuthorId, @AuthorName);

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
/* trace.ReplaceMovement (lot 12a)                                    */
/* Corrects a movement: gives it a new station, quantity and time.    */
/* The movement type (the step) stays the same. trace.Movement is not */
/* changed: a row of kind REPLACE is added to trace.MovementCorrection. */
/* Any movement that is not cancelled can be corrected, also in a     */
/* SHIPPED batch. If it is the last valid movement, the quantity of   */
/* the batch follows. The status of the batch never changes here.     */
/* Lot 12b: the RECEPTION cannot be moved before the harvest (50309); */
/* an old code of the batch is refused (50104).                       */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.ReplaceMovement
    @BatchCode     NVARCHAR(30),
    @MovementId    BIGINT,
    @StationCode   NVARCHAR(20),
    @QuantityKg    DECIMAL(10,2),
    @OccurredAt    DATETIME2,
    @ReasonCode    NVARCHAR(50),
    @ReasonComment NVARCHAR(2000),
    @AuthorId      NVARCHAR(200),
    @AuthorName    NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId INT;
    DECLARE @StationId INT;
    DECLARE @MovementType NVARCHAR(20);
    DECLARE @CurrentKind NVARCHAR(10);
    DECLARE @CurrentStationId INT;
    DECLARE @CurrentQuantity DECIMAL(10,2);
    DECLARE @CurrentTime DATETIME2;
    DECLARE @PreviousQuantity DECIMAL(10,2);
    DECLARE @NextQuantity DECIMAL(10,2);
    DECLARE @IsLast BIT;
    DECLARE @HarvestDate DATE;
    DECLARE @msg NVARCHAR(2048);
    DECLARE @Valid TABLE (MovementId BIGINT NOT NULL PRIMARY KEY, MovementType NVARCHAR(20) NOT NULL,
                          QuantityKg DECIMAL(10,2) NOT NULL);

    -- 1. The author must be given (NULL or blank counts as empty). The API reads it from the
    --    validated token; the database does not trust that it did, and checks it too.
    IF @AuthorId IS NULL OR LEN(TRIM(@AuthorId)) = 0
       OR @AuthorName IS NULL OR LEN(TRIM(@AuthorName)) = 0
    BEGIN
        THROW 50405, N'The author must not be empty.', 1;
    END;

    -- 2. The author must fit in the columns (64 and 100 characters): never cut silently.
    IF LEN(@AuthorId) > 64 OR LEN(@AuthorName) > 100
    BEGIN
        THROW 50406, N'The author identifier or name is too long.', 1;
    END;

    -- 3. The new quantity must be greater than 0 (NULL counts as invalid).
    IF @QuantityKg IS NULL OR @QuantityKg <= 0
    BEGIN
        THROW 50401, N'The quantity must be greater than 0.', 1;
    END;

    -- 4. The reason must be a known code (NULL counts as unknown). The parameter is wider than the
    --    column so that a wrong value reaches this check.
    IF @ReasonCode IS NULL
       OR @ReasonCode NOT IN (N'DATA_ENTRY_ERROR', N'MEASUREMENT_ERROR', N'OTHER')
    BEGIN
        SET @msg = CONCAT(N'Unknown reason code ''', @ReasonCode, N'''.');
        THROW 50407, @msg, 1;
    END;

    -- The comparison above ignores the case: always use the code in capitals.
    SET @ReasonCode = UPPER(@ReasonCode);

    -- 5. The comment is optional (NULL counts as empty), at most 500 characters. The parameter is
    --    wider than the column so that a long comment reaches this check and is never cut silently.
    SET @ReasonComment = COALESCE(TRIM(@ReasonComment), N'');

    IF LEN(@ReasonComment) > 500
    BEGIN
        THROW 50409, N'The comment is too long (500 characters at most).', 1;
    END;

    -- 6. The reason OTHER needs a comment that says what happened.
    IF @ReasonCode = N'OTHER' AND LEN(@ReasonComment) = 0
    BEGIN
        THROW 50408, N'The reason OTHER needs a comment.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- The batch must exist. It is read AND locked (UPDLOCK) until the end of the
        -- transaction, like in AddMovement (ADR 0003): a correction and a new movement of the same
        -- batch are handled one after the other.
        SELECT @BatchId = BatchId
        FROM trace.Batch WITH (UPDLOCK)
        WHERE BatchCode = @BatchCode;

        IF @BatchId IS NULL
        BEGIN
            -- Lot 12b: the code may be an old code of a corrected batch. Writing needs the current
            -- code: the error says which one it is.
            DECLARE @CurrentCode NVARCHAR(30);

            SELECT TOP (1) @CurrentCode = b.BatchCode
            FROM trace.BatchCorrection AS c
            JOIN trace.Batch AS b ON b.BatchId = c.BatchId
            WHERE c.OldBatchCode = @BatchCode
            ORDER BY c.CorrectionId;

            IF @CurrentCode IS NOT NULL
            BEGIN
                SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' was replaced by ''', @CurrentCode, N'''.');
                THROW 50104, @msg, 1;
            END;

            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
            THROW 50100, @msg, 1;
        END;

        -- 7. The new station must exist.
        SELECT @StationId = StationId
        FROM trace.Station
        WHERE Code = @StationCode;

        IF @StationId IS NULL
        BEGIN
            SET @msg = CONCAT(N'Station ''', @StationCode, N''' was not found.');
            THROW 50102, @msg, 1;
        END;

        -- 8. The movement must belong to this batch (its type is read here).
        SELECT @MovementType = MovementType
        FROM trace.Movement
        WHERE MovementId = @MovementId AND BatchId = @BatchId;

        IF @MovementType IS NULL
        BEGIN
            SET @msg = CONCAT(N'Movement ', @MovementId, N' was not found in batch ''', @BatchCode, N'''.');
            THROW 50103, @msg, 1;
        END;

        -- 9. The valid version of this movement. A movement whose latest correction is a CANCEL is
        -- cancelled for good: it can no longer be corrected.
        SELECT @CurrentKind      = c.Kind,
               @CurrentStationId = COALESCE(c.StationId, m.StationId),
               @CurrentQuantity  = COALESCE(c.QuantityKg, m.QuantityKg),
               @CurrentTime      = COALESCE(c.OccurredAt, m.OccurredAt)
        FROM trace.Movement AS m
        OUTER APPLY (SELECT TOP (1) cc.Kind, cc.StationId, cc.QuantityKg, cc.OccurredAt
                     FROM trace.MovementCorrection AS cc
                     WHERE cc.MovementId = m.MovementId
                     ORDER BY cc.CorrectionId DESC) AS c
        WHERE m.MovementId = @MovementId;

        IF @CurrentKind = N'CANCEL'
        BEGIN
            SET @msg = CONCAT(N'Movement ', @MovementId, N' is cancelled: it can no longer be corrected.');
            THROW 50305, @msg, 1;
        END;

        -- 10. The new station must have the function of the movement (same type as before).
        IF NOT EXISTS (SELECT 1 FROM trace.StationCapability
                       WHERE StationId = @StationId AND MovementType = @MovementType)
        BEGIN
            SET @msg = CONCAT(N'Station ''', @StationCode, N''' does not have the function ''', @MovementType, N'''.');
            THROW 50303, @msg, 1;
        END;

        -- The valid version of every movement of the batch that is not cancelled: its row in
        -- trace.Movement with its latest correction (highest CorrectionId) applied.
        INSERT @Valid (MovementId, MovementType, QuantityKg)
        SELECT m.MovementId, m.MovementType, COALESCE(c.QuantityKg, m.QuantityKg)
        FROM trace.Movement AS m
        OUTER APPLY (SELECT TOP (1) cc.Kind, cc.QuantityKg
                     FROM trace.MovementCorrection AS cc
                     WHERE cc.MovementId = m.MovementId
                     ORDER BY cc.CorrectionId DESC) AS c
        WHERE m.BatchId = @BatchId
          AND (c.Kind IS NULL OR c.Kind <> N'CANCEL');

        SELECT TOP (1) @PreviousQuantity = QuantityKg
        FROM @Valid
        WHERE MovementId < @MovementId
        ORDER BY MovementId DESC;

        SELECT TOP (1) @NextQuantity = QuantityKg
        FROM @Valid
        WHERE MovementId > @MovementId
        ORDER BY MovementId ASC;

        SET @IsLast = IIF(EXISTS (SELECT 1 FROM @Valid WHERE MovementId > @MovementId), 0, 1);

        -- 11. The quantity still must not go up from one step to the next (an equal quantity is
        --     accepted): not above the step before, not below the step after. A step that is
        --     cancelled does not count. The first step has no step before, the last no step after.
        IF @QuantityKg > @PreviousQuantity
        BEGIN
            SET @msg = CONCAT(N'Quantity ', CAST(@QuantityKg AS NVARCHAR(20)),
                              N' is higher than the quantity of the previous step (',
                              CAST(@PreviousQuantity AS NVARCHAR(20)), N').');
            THROW 50304, @msg, 1;
        END;

        IF @QuantityKg < @NextQuantity
        BEGIN
            SET @msg = CONCAT(N'Quantity ', CAST(@QuantityKg AS NVARCHAR(20)),
                              N' is lower than the quantity of the next step (',
                              CAST(@NextQuantity AS NVARCHAR(20)), N').');
            THROW 50304, @msg, 1;
        END;

        -- 12. The reception cannot be moved before the harvest (lot 12b): the day of the new time
        --     must not be before the harvest date of the batch. The same day is accepted.
        IF @MovementType = N'RECEPTION'
        BEGIN
            SELECT @HarvestDate = HarvestDate
            FROM trace.Batch
            WHERE BatchId = @BatchId;

            IF CAST(@OccurredAt AS DATE) < @HarvestDate
            BEGIN
                SET @msg = CONCAT(N'The reception date ', CONVERT(NVARCHAR(10), CAST(@OccurredAt AS DATE), 23),
                                  N' is before the harvest date ', CONVERT(NVARCHAR(10), @HarvestDate, 23), N'.');
                THROW 50309, @msg, 1;
            END;
        END;

        -- 13. The new values must differ from the current ones.
        IF @StationId = @CurrentStationId AND @QuantityKg = @CurrentQuantity AND @OccurredAt = @CurrentTime
        BEGIN
            THROW 50308, N'The new values are the same as the current ones: nothing to correct.', 1;
        END;

        INSERT trace.MovementCorrection
            (MovementId, Kind, StationId, MovementType, QuantityKg, OccurredAt,
             ReasonCode, ReasonComment, AuthorId, AuthorName)
        VALUES
            (@MovementId, N'REPLACE', @StationId, @MovementType, @QuantityKg, @OccurredAt,
             @ReasonCode, @ReasonComment, @AuthorId, @AuthorName);

        -- The batch keeps the last known quantity: it follows only when the last valid movement changes.
        IF @IsLast = 1
        BEGIN
            UPDATE trace.Batch
            SET QuantityKg = @QuantityKg
            WHERE BatchId = @BatchId;
        END;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- raise the original error again
    END CATCH;
END;
GO

/* ------------------------------------------------------------------ */
/* trace.CancelMovement (lot 12a)                                     */
/* Says that a movement did not happen: a row of kind CANCEL is added */
/* to trace.MovementCorrection, with the values of the version it     */
/* cancels. Only the last valid movement of a batch can be cancelled, */
/* never the RECEPTION (a batch is never deleted). The batch goes     */
/* back to the status and the quantity of the step before. A SHIPPED  */
/* batch can be corrected too. A cancelled movement stays cancelled.  */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.CancelMovement
    @BatchCode     NVARCHAR(30),
    @MovementId    BIGINT,
    @ReasonCode    NVARCHAR(50),
    @ReasonComment NVARCHAR(2000),
    @AuthorId      NVARCHAR(200),
    @AuthorName    NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId INT;
    DECLARE @MovementType NVARCHAR(20);
    DECLARE @CurrentKind NVARCHAR(10);
    DECLARE @CurrentStationId INT;
    DECLARE @CurrentQuantity DECIMAL(10,2);
    DECLARE @CurrentTime DATETIME2;
    DECLARE @PreviousType NVARCHAR(20);
    DECLARE @PreviousQuantity DECIMAL(10,2);
    DECLARE @msg NVARCHAR(2048);
    DECLARE @Valid TABLE (MovementId BIGINT NOT NULL PRIMARY KEY, MovementType NVARCHAR(20) NOT NULL,
                          QuantityKg DECIMAL(10,2) NOT NULL);

    -- 1. The author must be given (NULL or blank counts as empty). The API reads it from the
    --    validated token; the database does not trust that it did, and checks it too.
    IF @AuthorId IS NULL OR LEN(TRIM(@AuthorId)) = 0
       OR @AuthorName IS NULL OR LEN(TRIM(@AuthorName)) = 0
    BEGIN
        THROW 50405, N'The author must not be empty.', 1;
    END;

    -- 2. The author must fit in the columns (64 and 100 characters): never cut silently.
    IF LEN(@AuthorId) > 64 OR LEN(@AuthorName) > 100
    BEGIN
        THROW 50406, N'The author identifier or name is too long.', 1;
    END;

    -- 3. The reason must be a known code (NULL counts as unknown). The parameter is wider than the
    --    column so that a wrong value reaches this check.
    IF @ReasonCode IS NULL
       OR @ReasonCode NOT IN (N'DATA_ENTRY_ERROR', N'MEASUREMENT_ERROR', N'OTHER')
    BEGIN
        SET @msg = CONCAT(N'Unknown reason code ''', @ReasonCode, N'''.');
        THROW 50407, @msg, 1;
    END;

    -- The comparison above ignores the case: always use the code in capitals.
    SET @ReasonCode = UPPER(@ReasonCode);

    -- 4. The comment is optional (NULL counts as empty), at most 500 characters. The parameter is
    --    wider than the column so that a long comment reaches this check and is never cut silently.
    SET @ReasonComment = COALESCE(TRIM(@ReasonComment), N'');

    IF LEN(@ReasonComment) > 500
    BEGIN
        THROW 50409, N'The comment is too long (500 characters at most).', 1;
    END;

    -- 5. The reason OTHER needs a comment that says what happened.
    IF @ReasonCode = N'OTHER' AND LEN(@ReasonComment) = 0
    BEGIN
        THROW 50408, N'The reason OTHER needs a comment.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- The batch must exist. It is read AND locked (UPDLOCK) until the end of the
        -- transaction, like in AddMovement (ADR 0003): a correction and a new movement of the same
        -- batch are handled one after the other.
        SELECT @BatchId = BatchId
        FROM trace.Batch WITH (UPDLOCK)
        WHERE BatchCode = @BatchCode;

        IF @BatchId IS NULL
        BEGIN
            -- Lot 12b: the code may be an old code of a corrected batch. Writing needs the current
            -- code: the error says which one it is.
            DECLARE @CurrentCode NVARCHAR(30);

            SELECT TOP (1) @CurrentCode = b.BatchCode
            FROM trace.BatchCorrection AS c
            JOIN trace.Batch AS b ON b.BatchId = c.BatchId
            WHERE c.OldBatchCode = @BatchCode
            ORDER BY c.CorrectionId;

            IF @CurrentCode IS NOT NULL
            BEGIN
                SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' was replaced by ''', @CurrentCode, N'''.');
                THROW 50104, @msg, 1;
            END;

            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
            THROW 50100, @msg, 1;
        END;

        -- 6. The movement must belong to this batch (its type is read here).
        SELECT @MovementType = MovementType
        FROM trace.Movement
        WHERE MovementId = @MovementId AND BatchId = @BatchId;

        IF @MovementType IS NULL
        BEGIN
            SET @msg = CONCAT(N'Movement ', @MovementId, N' was not found in batch ''', @BatchCode, N'''.');
            THROW 50103, @msg, 1;
        END;

        -- 7. The valid version of this movement. A movement whose latest correction is a CANCEL is
        -- cancelled for good: it can no longer be corrected.
        SELECT @CurrentKind      = c.Kind,
               @CurrentStationId = COALESCE(c.StationId, m.StationId),
               @CurrentQuantity  = COALESCE(c.QuantityKg, m.QuantityKg),
               @CurrentTime      = COALESCE(c.OccurredAt, m.OccurredAt)
        FROM trace.Movement AS m
        OUTER APPLY (SELECT TOP (1) cc.Kind, cc.StationId, cc.QuantityKg, cc.OccurredAt
                     FROM trace.MovementCorrection AS cc
                     WHERE cc.MovementId = m.MovementId
                     ORDER BY cc.CorrectionId DESC) AS c
        WHERE m.MovementId = @MovementId;

        IF @CurrentKind = N'CANCEL'
        BEGIN
            SET @msg = CONCAT(N'Movement ', @MovementId, N' is cancelled: it can no longer be corrected.');
            THROW 50305, @msg, 1;
        END;

        -- 8. The RECEPTION cannot be cancelled: a batch always has its reception, and is never deleted.
        IF @MovementType = N'RECEPTION'
        BEGIN
            THROW 50307, N'The RECEPTION of a batch cannot be cancelled.', 1;
        END;

        -- The valid version of every movement of the batch that is not cancelled: its row in
        -- trace.Movement with its latest correction (highest CorrectionId) applied.
        INSERT @Valid (MovementId, MovementType, QuantityKg)
        SELECT m.MovementId, m.MovementType, COALESCE(c.QuantityKg, m.QuantityKg)
        FROM trace.Movement AS m
        OUTER APPLY (SELECT TOP (1) cc.Kind, cc.QuantityKg
                     FROM trace.MovementCorrection AS cc
                     WHERE cc.MovementId = m.MovementId
                     ORDER BY cc.CorrectionId DESC) AS c
        WHERE m.BatchId = @BatchId
          AND (c.Kind IS NULL OR c.Kind <> N'CANCEL');

        -- 9. Only the last valid movement of the batch can be cancelled: a later step would be left
        --     without the step before it (no step skipped). To cancel an earlier step, cancel the
        --     later ones first.
        IF EXISTS (SELECT 1 FROM @Valid WHERE MovementId > @MovementId)
        BEGIN
            THROW 50306, N'Only the last valid movement of a batch can be cancelled.', 1;
        END;

        -- The step before: the batch goes back to its status and to its quantity.
        SELECT TOP (1) @PreviousType = MovementType, @PreviousQuantity = QuantityKg
        FROM @Valid
        WHERE MovementId < @MovementId
        ORDER BY MovementId DESC;

        INSERT trace.MovementCorrection
            (MovementId, Kind, StationId, MovementType, QuantityKg, OccurredAt,
             ReasonCode, ReasonComment, AuthorId, AuthorName)
        VALUES
            (@MovementId, N'CANCEL', @CurrentStationId, @MovementType, @CurrentQuantity, @CurrentTime,
             @ReasonCode, @ReasonComment, @AuthorId, @AuthorName);

        UPDATE trace.Batch
        SET Status = CASE @PreviousType
                         WHEN N'RECEPTION' THEN N'RECEIVED'
                         WHEN N'SORTING'   THEN N'SORTED'
                         WHEN N'PACKING'   THEN N'PACKED'
                         WHEN N'SHIPMENT'  THEN N'SHIPPED'
                     END,
            QuantityKg = @PreviousQuantity
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
/* trace.CorrectBatch (lot 12b)                                       */
/* Corrects the sheet of a batch: code, farm, variety, harvest date.  */
/* The four new values are always given (a field that does not change */
/* repeats its current value). The old values are kept: a row is      */
/* added to trace.BatchCorrection, and trace.Batch gets the new       */
/* values in the same transaction. The status and the quantity of the */
/* batch never change here. A SHIPPED batch can be corrected too. The */
/* batch is found by its CURRENT code (an old code gives 50104).      */
/* ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE trace.CorrectBatch
    @BatchCode     NVARCHAR(30),
    @NewBatchCode  NVARCHAR(30),
    @FarmCode      NVARCHAR(20),
    @Variety       NVARCHAR(50),
    @HarvestDate   DATE,
    @ReasonCode    NVARCHAR(50),
    @ReasonComment NVARCHAR(2000),
    @AuthorId      NVARCHAR(200),
    @AuthorName    NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchId INT;
    DECLARE @FarmId INT;
    DECLARE @OldBatchCode NVARCHAR(30);
    DECLARE @OldFarmId INT;
    DECLARE @OldVariety NVARCHAR(50);
    DECLARE @OldHarvestDate DATE;
    DECLARE @CurrentCode NVARCHAR(30);
    DECLARE @ReceptionTime DATETIME2;
    DECLARE @msg NVARCHAR(2048);

    -- 1. The author must be given (NULL or blank counts as empty). The API reads it from the
    --    validated token; the database does not trust that it did, and checks it too.
    IF @AuthorId IS NULL OR LEN(TRIM(@AuthorId)) = 0
       OR @AuthorName IS NULL OR LEN(TRIM(@AuthorName)) = 0
    BEGIN
        THROW 50405, N'The author must not be empty.', 1;
    END;

    -- 2. The author must fit in the columns (64 and 100 characters): never cut silently.
    IF LEN(@AuthorId) > 64 OR LEN(@AuthorName) > 100
    BEGIN
        THROW 50406, N'The author identifier or name is too long.', 1;
    END;

    -- 3. The reason must be accepted for a batch correction: DATA_ENTRY_ERROR or OTHER (NULL counts
    --    as not accepted). The parameter is wider than the column so that a wrong value reaches
    --    this check.
    IF @ReasonCode IS NULL
       OR @ReasonCode NOT IN (N'DATA_ENTRY_ERROR', N'OTHER')
    BEGIN
        SET @msg = CONCAT(N'Reason code ''', @ReasonCode, N''' is not accepted for a batch correction.');
        THROW 50407, @msg, 1;
    END;

    -- The comparison above ignores the case: always use the code in capitals.
    SET @ReasonCode = UPPER(@ReasonCode);

    -- 4. The comment is optional (NULL counts as empty), at most 500 characters. The parameter is
    --    wider than the column so that a long comment reaches this check and is never cut silently.
    SET @ReasonComment = COALESCE(TRIM(@ReasonComment), N'');

    IF LEN(@ReasonComment) > 500
    BEGIN
        THROW 50409, N'The comment is too long (500 characters at most).', 1;
    END;

    -- 5. The reason OTHER needs a comment that says what happened.
    IF @ReasonCode = N'OTHER' AND LEN(@ReasonComment) = 0
    BEGIN
        THROW 50408, N'The reason OTHER needs a comment.', 1;
    END;

    -- 6. The new batch code must not be empty (NULL counts as empty).
    IF @NewBatchCode IS NULL OR LEN(TRIM(@NewBatchCode)) = 0
    BEGIN
        THROW 50400, N'The code must not be empty.', 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 7. The batch must exist under its CURRENT code. It is read AND locked (UPDLOCK) until the
        -- end of the transaction, like in AddMovement (ADR 0003). The values it has now are read
        -- here: they become the "old" values of the correction.
        SELECT @BatchId = BatchId,
               @OldBatchCode = BatchCode,
               @OldFarmId = FarmId,
               @OldVariety = Variety,
               @OldHarvestDate = HarvestDate
        FROM trace.Batch WITH (UPDLOCK)
        WHERE BatchCode = @BatchCode;

        IF @BatchId IS NULL
        BEGIN
            -- The code may be an old code of a corrected batch: the error says which code is the
            -- right one.
            SELECT TOP (1) @CurrentCode = b.BatchCode
            FROM trace.BatchCorrection AS c
            JOIN trace.Batch AS b ON b.BatchId = c.BatchId
            WHERE c.OldBatchCode = @BatchCode
            ORDER BY c.CorrectionId;

            IF @CurrentCode IS NOT NULL
            BEGIN
                SET @msg = CONCAT(N'Batch code ''', @BatchCode, N''' was replaced by ''', @CurrentCode, N'''.');
                THROW 50104, @msg, 1;
            END;

            SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
            THROW 50100, @msg, 1;
        END;

        -- 8. The farm must exist.
        SELECT @FarmId = FarmId
        FROM trace.Farm
        WHERE Code = @FarmCode;

        IF @FarmId IS NULL
        BEGIN
            SET @msg = CONCAT(N'Farm ''', @FarmCode, N''' was not found.');
            THROW 50101, @msg, 1;
        END;

        -- 9. The new code must be free: not the current code of another batch, not an old code of
        --    another batch. The own codes of this batch (current or old) are accepted: a batch can
        --    take back a code it had.
        IF EXISTS (SELECT 1 FROM trace.Batch
                   WHERE BatchCode = @NewBatchCode AND BatchId <> @BatchId)
        BEGIN
            SET @msg = CONCAT(N'Batch code ''', @NewBatchCode, N''' already exists.');
            THROW 50202, @msg, 1;
        END;

        IF EXISTS (SELECT 1 FROM trace.BatchCorrection
                   WHERE OldBatchCode = @NewBatchCode AND BatchId <> @BatchId)
        BEGIN
            SET @msg = CONCAT(N'Batch code ''', @NewBatchCode, N''' is the old code of another batch.');
            THROW 50203, @msg, 1;
        END;

        -- 10. The harvest date must not be after the day of the valid reception of the batch (its
        --     latest correction applied; the reception is never cancelled). The same day is
        --     accepted. A batch without reception is not checked: there is nothing to compare.
        SELECT @ReceptionTime = COALESCE(c.OccurredAt, m.OccurredAt)
        FROM trace.Movement AS m
        OUTER APPLY (SELECT TOP (1) cc.OccurredAt
                     FROM trace.MovementCorrection AS cc
                     WHERE cc.MovementId = m.MovementId
                     ORDER BY cc.CorrectionId DESC) AS c
        WHERE m.BatchId = @BatchId AND m.MovementType = N'RECEPTION';

        IF @ReceptionTime IS NOT NULL AND @HarvestDate > CAST(@ReceptionTime AS DATE)
        BEGIN
            SET @msg = CONCAT(N'The harvest date ', CONVERT(NVARCHAR(10), @HarvestDate, 23),
                              N' is after the reception date ',
                              CONVERT(NVARCHAR(10), CAST(@ReceptionTime AS DATE), 23), N'.');
            THROW 50309, @msg, 1;
        END;

        -- 11. At least one value must change. The codes and the variety are compared with a binary
        --     collation, so that a change of case only (lot-1 to LOT-1) is a change.
        IF @FarmId = @OldFarmId
           AND @NewBatchCode COLLATE Latin1_General_BIN2 = @OldBatchCode COLLATE Latin1_General_BIN2
           AND @Variety COLLATE Latin1_General_BIN2 = @OldVariety COLLATE Latin1_General_BIN2
           AND @HarvestDate = @OldHarvestDate
        BEGIN
            THROW 50308, N'The new values are the same as the current ones: nothing to correct.', 1;
        END;

        INSERT trace.BatchCorrection
            (BatchId, OldBatchCode, NewBatchCode, OldFarmId, NewFarmId, OldVariety, NewVariety,
             OldHarvestDate, NewHarvestDate, ReasonCode, ReasonComment, AuthorId, AuthorName)
        VALUES
            (@BatchId, @OldBatchCode, @NewBatchCode, @OldFarmId, @FarmId, @OldVariety, @Variety,
             @OldHarvestDate, @HarvestDate, @ReasonCode, @ReasonComment, @AuthorId, @AuthorName);

        -- The batch keeps the current values: it now has the corrected sheet.
        UPDATE trace.Batch
        SET BatchCode = @NewBatchCode,
            FarmId = @FarmId,
            Variety = @Variety,
            HarvestDate = @HarvestDate
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
/* were recorded, cancelled ones included. Result 3: the corrections  */
/* of these movements, in the order they were made.                   */
/* Lot 12b: the batch is found by its code, or else by an old code    */
/* (it is then read with its current code). Result 4: the             */
/* corrections of the sheet, in the order they were made.             */
/* Each movement carries the name of its author (lot 11).             */
/* Lot 12a: StationCode, QuantityKg and OccurredAt of a movement are  */
/* its VALID values (its latest correction applied); the Original     */
/* columns are the values first entered. IsCancelled says that the    */
/* movement did not happen. CorrectionCount counts its corrections.   */
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

    -- Lot 12b: if the code is not the current code of a batch, it may be an old code of a corrected
    -- batch: that batch is read (with its current code).
    IF @BatchId IS NULL
    BEGIN
        SELECT TOP (1) @BatchId = BatchId
        FROM trace.BatchCorrection
        WHERE OldBatchCode = @BatchCode
        ORDER BY CorrectionId;
    END;

    IF @BatchId IS NULL
    BEGIN
        SET @msg = CONCAT(N'Batch ''', @BatchCode, N''' was not found.');
        THROW 50100, @msg, 1;
    END;

    SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    JOIN trace.Farm AS f ON f.FarmId = b.FarmId
    WHERE b.BatchId = @BatchId;

    SELECT m.MovementId,
           m.MovementType,
           COALESCE(vs.Code, s.Code)             AS StationCode,
           COALESCE(c.QuantityKg, m.QuantityKg)  AS QuantityKg,
           COALESCE(c.OccurredAt, m.OccurredAt)  AS OccurredAt,
           m.AuthorName,
           CAST(IIF(c.Kind = N'CANCEL', 1, 0) AS BIT) AS IsCancelled,
           (SELECT COUNT(*) FROM trace.MovementCorrection AS n
            WHERE n.MovementId = m.MovementId)   AS CorrectionCount,
           s.Code                                AS OriginalStationCode,
           m.QuantityKg                          AS OriginalQuantityKg,
           m.OccurredAt                          AS OriginalOccurredAt
    FROM trace.Movement AS m
    JOIN trace.Station AS s ON s.StationId = m.StationId
    OUTER APPLY (SELECT TOP (1) cc.Kind, cc.StationId, cc.QuantityKg, cc.OccurredAt
                 FROM trace.MovementCorrection AS cc
                 WHERE cc.MovementId = m.MovementId
                 ORDER BY cc.CorrectionId DESC) AS c
    LEFT JOIN trace.Station AS vs ON vs.StationId = c.StationId
    WHERE m.BatchId = @BatchId
    ORDER BY m.MovementId;

    SELECT c.CorrectionId, c.MovementId, c.Kind, c.MovementType, s.Code AS StationCode,
           c.QuantityKg, c.OccurredAt, c.ReasonCode, c.ReasonComment, c.AuthorName, c.CorrectedAt
    FROM trace.MovementCorrection AS c
    JOIN trace.Movement AS m ON m.MovementId = c.MovementId
    JOIN trace.Station AS s ON s.StationId = c.StationId
    WHERE m.BatchId = @BatchId
    ORDER BY c.CorrectionId;

    -- Lot 12b: the corrections of the sheet of the batch (code, farm, variety, harvest date), in the
    -- order they were made. Empty if the sheet was never corrected.
    SELECT bc.CorrectionId,
           bc.OldBatchCode, bc.NewBatchCode,
           fo.Code AS OldFarmCode, fn.Code AS NewFarmCode,
           bc.OldVariety, bc.NewVariety,
           bc.OldHarvestDate, bc.NewHarvestDate,
           bc.ReasonCode, bc.ReasonComment, bc.AuthorName, bc.CorrectedAt
    FROM trace.BatchCorrection AS bc
    JOIN trace.Farm AS fo ON fo.FarmId = bc.OldFarmId
    JOIN trace.Farm AS fn ON fn.FarmId = bc.NewFarmId
    WHERE bc.BatchId = @BatchId
    ORDER BY bc.CorrectionId;
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

    -- CAST to BIGINT: a huge page number must not overflow the calculation.
    SELECT b.BatchCode, f.Code AS FarmCode, b.Variety, b.HarvestDate, b.QuantityKg, b.Status
    FROM trace.Batch AS b
    JOIN trace.Farm AS f ON f.FarmId = b.FarmId
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId)
    ORDER BY b.BatchId
    OFFSET (CAST(@PageNumber AS BIGINT) - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;

    -- The total uses the same filters as the page.
    SELECT COUNT(*) AS TotalCount
    FROM trace.Batch AS b
    WHERE (@Status IS NULL OR b.Status = @Status)
      AND (@FarmId IS NULL OR b.FarmId = @FarmId);
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
