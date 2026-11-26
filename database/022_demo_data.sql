/*
  022_demo_data.sql
  Loads a small demonstration data set into the database named in DbName (lot 14, docker compose):
  2 farms, 4 stations, 20 batches spread over the four steps, and one example of each kind of
  correction (2 replaced movements, 1 cancelled movement, 2 corrected batch sheets).

  - It only calls the stored procedures, so the rules apply exactly as in real use.
  - The times come from the clock of SQL Server: all on the day before yesterday, in order, so they
    are in the past and valid whatever the day it is run (rule 12 of docs/fonctionnel.md).
  - NOT replayable on purpose: if the database already has a farm, it does nothing.
  - The data is signed "demo-seed", a fictitious author (not a Keycloak account).
  - Run 001, 002, 004, 005, 011 and 017 first, with the same DbName.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode), or with sqlcmd (docker/db-init.sh).
  - Contains no DROP, TRUNCATE or DELETE.
*/

:setvar DbName TraceabilityDev

USE $(DbName);
GO

-- Safety: if the connection is not on $(DbName) (wrong database, or SQLCMD mode is off),
-- nothing below is executed. It is turned off again at the end.
IF DB_NAME() <> N'$(DbName)'
BEGIN
    RAISERROR(N'Wrong database or SQLCMD mode is off. Expected $(DbName). Nothing was created.', 16, 1);
    SET NOEXEC ON;
END;
GO

SET XACT_ABORT ON;
SET NOCOUNT ON;

IF EXISTS (SELECT 1 FROM trace.Farm)
BEGIN
    PRINT N'The database already has a farm. Nothing changed.';
END
ELSE
BEGIN
    DECLARE @AuthorId   NVARCHAR(200) = N'demo-seed';
    DECLARE @AuthorName NVARCHAR(200) = N'demo-seed';

    -- Farms and stations (each station has the one function that matches its name).
    EXEC trace.CreateFarm    @Code = N'FERME-NORD', @Name = N'Ferme du Nord', @Region = N'Nord';
    EXEC trace.CreateFarm    @Code = N'FERME-SUD',  @Name = N'Ferme du Sud',  @Region = N'Sud';
    EXEC trace.CreateStation @Code = N'STA-RECEPTION',  @Name = N'Station de reception';
    EXEC trace.CreateStation @Code = N'STA-TRI',        @Name = N'Station de tri';
    EXEC trace.CreateStation @Code = N'STA-EMBALLAGE',  @Name = N'Station emballage';
    EXEC trace.CreateStation @Code = N'STA-EXPEDITION', @Name = N'Station expedition';
    EXEC trace.AddStationCapability @StationCode = N'STA-RECEPTION',  @MovementType = N'RECEPTION';
    EXEC trace.AddStationCapability @StationCode = N'STA-TRI',        @MovementType = N'SORTING';
    EXEC trace.AddStationCapability @StationCode = N'STA-EMBALLAGE',  @MovementType = N'PACKING';
    EXEC trace.AddStationCapability @StationCode = N'STA-EXPEDITION', @MovementType = N'SHIPMENT';

    -- 20 batches. 1-5 received only, 6-10 sorted, 11-15 packed, 16-20 shipped.
    -- Harvest: 3 days ago. Reception between 06:10 and 09:20 the day before yesterday,
    -- then +2 hours per step (the last step ends at 15:20 at the latest).
    DECLARE @Today   DATE      = CAST(SYSUTCDATETIME() AS DATE);
    DECLARE @T0      DATETIME2 = DATEADD(DAY, -2, CAST(@Today AS DATETIME2));
    DECLARE @Harvest DATE      = DATEADD(DAY, -3, @Today);
    DECLARE @i INT = 1, @Steps INT, @Code NVARCHAR(30), @Farm NVARCHAR(20),
            @Variety NVARCHAR(50), @Qty DECIMAL(10,2), @T DATETIME2;

    WHILE @i <= 20
    BEGIN
        SET @Code    = N'DEMO-LOT-' + RIGHT(N'0' + CAST(@i AS NVARCHAR(2)), 2);
        SET @Farm    = CASE WHEN @i % 2 = 1 THEN N'FERME-NORD' ELSE N'FERME-SUD' END;
        SET @Variety = CHOOSE((@i % 4) + 1, N'Cerise', N'Grappe', N'Roma', N'Coeur de boeuf');
        SET @Steps   = CASE WHEN @i <= 5 THEN 1 WHEN @i <= 10 THEN 2 WHEN @i <= 15 THEN 3 ELSE 4 END;
        SET @Qty     = 400 + @i * 10;                       -- 410.00 to 600.00 kg
        SET @T       = DATEADD(MINUTE, 360 + @i * 10, @T0);

        -- Two entry mistakes, corrected further down (corrections 4 and 5).
        IF @i = 4 SET @Variety = N'Cerize';
        IF @i = 5 SET @Code    = N'DEMO-LOT-5';

        EXEC trace.CreateBatch @BatchCode = @Code, @FarmCode = @Farm, @Variety = @Variety,
             @HarvestDate = @Harvest, @QuantityKg = @Qty, @StationCode = N'STA-RECEPTION',
             @OccurredAt = @T, @AuthorId = @AuthorId, @AuthorName = @AuthorName;

        IF @Steps >= 2
        BEGIN
            SET @Qty = @Qty - 30;  SET @T = DATEADD(HOUR, 2, @T);
            EXEC trace.AddMovement @BatchCode = @Code, @StationCode = N'STA-TRI', @MovementType = N'SORTING',
                 @QuantityKg = @Qty, @OccurredAt = @T, @AuthorId = @AuthorId, @AuthorName = @AuthorName;
        END;
        IF @Steps >= 3
        BEGIN
            SET @Qty = @Qty - 10;  SET @T = DATEADD(HOUR, 2, @T);
            EXEC trace.AddMovement @BatchCode = @Code, @StationCode = N'STA-EMBALLAGE', @MovementType = N'PACKING',
                 @QuantityKg = @Qty, @OccurredAt = @T, @AuthorId = @AuthorId, @AuthorName = @AuthorName;
        END;
        IF @Steps >= 4
        BEGIN
            SET @T = DATEADD(HOUR, 2, @T);
            EXEC trace.AddMovement @BatchCode = @Code, @StationCode = N'STA-EXPEDITION', @MovementType = N'SHIPMENT',
                 @QuantityKg = @Qty, @OccurredAt = @T, @AuthorId = @AuthorId, @AuthorName = @AuthorName;
        END;

        SET @i += 1;
    END;

    -- Corrections (one example of each kind, for the supervisor and auditor roles).
    DECLARE @MovementId BIGINT, @StationCode NVARCHAR(20), @OccurredAt DATETIME2, @HarvestDate DATE;

    -- 1. Batch 08 (sorted): the sorting quantity was mistyped (movement replaced).
    SELECT @MovementId = m.MovementId, @StationCode = s.Code, @OccurredAt = m.OccurredAt
    FROM trace.Movement AS m
    JOIN trace.Batch    AS b ON b.BatchId = m.BatchId
    JOIN trace.Station  AS s ON s.StationId = m.StationId
    WHERE b.BatchCode = N'DEMO-LOT-08' AND m.MovementType = N'SORTING';
    EXEC trace.ReplaceMovement @BatchCode = N'DEMO-LOT-08', @MovementId = @MovementId,
         @StationCode = @StationCode, @QuantityKg = 445.00, @OccurredAt = @OccurredAt,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = N'',
         @AuthorId = @AuthorId, @AuthorName = @AuthorName;

    -- 2. Batch 12 (packed): the packing quantity was weighed again (reason OTHER, with a comment).
    SELECT @MovementId = m.MovementId, @StationCode = s.Code, @OccurredAt = m.OccurredAt
    FROM trace.Movement AS m
    JOIN trace.Batch    AS b ON b.BatchId = m.BatchId
    JOIN trace.Station  AS s ON s.StationId = m.StationId
    WHERE b.BatchCode = N'DEMO-LOT-12' AND m.MovementType = N'PACKING';
    EXEC trace.ReplaceMovement @BatchCode = N'DEMO-LOT-12', @MovementId = @MovementId,
         @StationCode = @StationCode, @QuantityKg = 478.50, @OccurredAt = @OccurredAt,
         @ReasonCode = N'OTHER', @ReasonComment = N'Pesee verifiee a la balance du quai.',
         @AuthorId = @AuthorId, @AuthorName = @AuthorName;

    -- 3. Batch 17: the shipment was entered by mistake (movement cancelled: the batch goes back to PACKED).
    SELECT @MovementId = m.MovementId
    FROM trace.Movement AS m
    JOIN trace.Batch    AS b ON b.BatchId = m.BatchId
    WHERE b.BatchCode = N'DEMO-LOT-17' AND m.MovementType = N'SHIPMENT';
    EXEC trace.CancelMovement @BatchCode = N'DEMO-LOT-17', @MovementId = @MovementId,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = N'',
         @AuthorId = @AuthorId, @AuthorName = @AuthorName;

    -- 4. Batch 04: the variety was mistyped ("Cerize"): batch sheet corrected.
    SELECT @Farm = f.Code, @HarvestDate = b.HarvestDate
    FROM trace.Batch AS b JOIN trace.Farm AS f ON f.FarmId = b.FarmId
    WHERE b.BatchCode = N'DEMO-LOT-04';
    EXEC trace.CorrectBatch @BatchCode = N'DEMO-LOT-04', @NewBatchCode = N'DEMO-LOT-04',
         @FarmCode = @Farm, @Variety = N'Cerise', @HarvestDate = @HarvestDate,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = N'',
         @AuthorId = @AuthorId, @AuthorName = @AuthorName;

    -- 5. Batch 05: the code was mistyped ("DEMO-LOT-5"): the old code stays readable.
    SELECT @Farm = f.Code, @Variety = b.Variety, @HarvestDate = b.HarvestDate
    FROM trace.Batch AS b JOIN trace.Farm AS f ON f.FarmId = b.FarmId
    WHERE b.BatchCode = N'DEMO-LOT-5';
    EXEC trace.CorrectBatch @BatchCode = N'DEMO-LOT-5', @NewBatchCode = N'DEMO-LOT-05',
         @FarmCode = @Farm, @Variety = @Variety, @HarvestDate = @HarvestDate,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = N'',
         @AuthorId = @AuthorId, @AuthorName = @AuthorName;

    -- Check (read only): number of batches by status.
    SELECT Status, COUNT(*) AS Batches FROM trace.Batch GROUP BY Status ORDER BY Status;
END;
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO
