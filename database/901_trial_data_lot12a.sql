/*
  901_trial_data_lot12a.sql

  Creates the small set of data used to try the interface of lot 12a by hand
  (see section 22 of docs/verification.md): one farm, three stations with their
  functions, and two batches.

    <prefix>-L1  Roma    RECEPTION 500 kg, SORTING 470 kg, PACKING 465 kg, SHIPMENT 460 kg  -> SHIPPED, 460 kg
    <prefix>-L2  Cherry  RECEPTION 500 kg, SORTING 470 kg                                   -> SORTED,  470 kg

  Stations: <prefix>-S1 (RECEPTION, SORTING), <prefix>-S2 (PACKING), <prefix>-S3 (SHIPMENT).
  Every row is written by the procedures of 004 and 005, with the fictitious author
  "Donnees SQL (essai)" (no Keycloak account is involved).

  - Only TraceabilityTest is accepted. Any other database is refused and nothing is done.
  - The codes come from @prefix (as written: ESSAI-12A). To try the script without touching
    the batches that already exist, change @prefix (for example ESSAI-REJEU, 11 characters at
    most). Do NOT save that change in the file.
  - Run it once per prefix: a second run with the same prefix stops at the first duplicate code.
  - Run 002, 004 and 005 (and 019 on an existing database) before.
  - Note: every run of "dotnet test" empties TraceabilityTest, so these data must be created again.
*/

USE TraceabilityTest;
GO

IF DB_NAME() <> N'TraceabilityTest'
BEGIN
    RAISERROR(N'Only TraceabilityTest is accepted. Nothing done.', 16, 1);
    RETURN;
END;

DECLARE @prefix     NVARCHAR(11) = N'ESSAI-12A';
DECLARE @authorId   NVARCHAR(64) = N'sql-essai';
DECLARE @authorName NVARCHAR(100) = N'Donnees SQL (essai)';

DECLARE @farm NVARCHAR(20) = @prefix + N'-F1';
DECLARE @s1   NVARCHAR(20) = @prefix + N'-S1';
DECLARE @s2   NVARCHAR(20) = @prefix + N'-S2';
DECLARE @s3   NVARCHAR(20) = @prefix + N'-S3';
DECLARE @l1   NVARCHAR(30) = @prefix + N'-L1';
DECLARE @l2   NVARCHAR(30) = @prefix + N'-L2';

DECLARE @harvest DATE = '2026-11-10';
DECLARE @t0630 DATETIME2 = '2026-11-10T06:30:00';
DECLARE @t0915 DATETIME2 = '2026-11-10T09:15:00';
DECLARE @t1340 DATETIME2 = '2026-11-10T13:40:00';
DECLARE @t1705 DATETIME2 = '2026-11-10T17:05:00';

-- Farm, stations and functions.
EXEC trace.CreateFarm    @Code = @farm, @Name = N'Ferme d''essai 12a', @Region = N'Essai';
EXEC trace.CreateStation @Code = @s1, @Name = N'Station d''essai 1';
EXEC trace.CreateStation @Code = @s2, @Name = N'Station d''essai 2';
EXEC trace.CreateStation @Code = @s3, @Name = N'Station d''essai 3';
EXEC trace.AddStationCapability @StationCode = @s1, @MovementType = N'RECEPTION';
EXEC trace.AddStationCapability @StationCode = @s1, @MovementType = N'SORTING';
EXEC trace.AddStationCapability @StationCode = @s2, @MovementType = N'PACKING';
EXEC trace.AddStationCapability @StationCode = @s3, @MovementType = N'SHIPMENT';

-- Batch 1: goes all the way to the shipment.
EXEC trace.CreateBatch @BatchCode = @l1, @FarmCode = @farm, @Variety = N'Roma', @HarvestDate = @harvest,
     @QuantityKg = 500, @StationCode = @s1, @OccurredAt = @t0630, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l1, @StationCode = @s1, @MovementType = N'SORTING',
     @QuantityKg = 470, @OccurredAt = @t0915, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l1, @StationCode = @s2, @MovementType = N'PACKING',
     @QuantityKg = 465, @OccurredAt = @t1340, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l1, @StationCode = @s3, @MovementType = N'SHIPMENT',
     @QuantityKg = 460, @OccurredAt = @t1705, @AuthorId = @authorId, @AuthorName = @authorName;

-- Batch 2: stops after the sorting.
EXEC trace.CreateBatch @BatchCode = @l2, @FarmCode = @farm, @Variety = N'Cherry', @HarvestDate = @harvest,
     @QuantityKg = 500, @StationCode = @s1, @OccurredAt = @t0630, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l2, @StationCode = @s1, @MovementType = N'SORTING',
     @QuantityKg = 470, @OccurredAt = @t0915, @AuthorId = @authorId, @AuthorName = @authorName;

-- What was created: expected SHIPPED 460.00 for L1 and SORTED 470.00 for L2.
SELECT BatchCode, Status, QuantityKg
FROM trace.Batch
WHERE BatchCode IN (@l1, @l2)
ORDER BY BatchCode;
GO
