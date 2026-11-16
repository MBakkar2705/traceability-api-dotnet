/*
  902_trial_data_lot12b.sql

  Creates the small set of data used to try lot 12b by hand (correction of a batch sheet,
  see section 23 of docs/verification.md): two farms, three stations with their functions,
  and two batches.

    <prefix>-L1  Roma    RECEPTION 500 kg, SORTING 470 kg, PACKING 465 kg, SHIPMENT 460 kg  -> SHIPPED, 460 kg
    <prefix>-L2  Cherry  RECEPTION 500 kg, SORTING 470 kg                                   -> SORTED,  470 kg

  Farms: <prefix>-F1 (farm of both batches) and <prefix>-F2 (no batch: used to try a change of farm).
  Stations: <prefix>-S1 (RECEPTION, SORTING), <prefix>-S2 (PACKING), <prefix>-S3 (SHIPMENT).
  Harvest date and reception are on the same day (2026-11-10): the rule "harvest not after the
  reception day" is respected. Every row is written by the procedures of 004 and 005, with the
  fictitious author "Donnees SQL (essai)" (no Keycloak account is involved).

  - Only TraceabilityTest is accepted. Any other database is refused and nothing is done.
  - The codes come from @prefix (as written: ESSAI-12B). To try the script without touching
    the batches that already exist, change @prefix (for example ESSAI-REJEU, 11 characters at
    most). Do NOT save that change in the file.
  - Run it once per prefix: a second run with the same prefix stops at the first duplicate code.
  - Run 002, 004 and 005 (and 019 then 020 on an existing database) before.
  - Note: every run of "dotnet test" empties TraceabilityTest, so these data must be created again.
*/

USE TraceabilityTest;
GO

IF DB_NAME() <> N'TraceabilityTest'
BEGIN
    RAISERROR(N'Only TraceabilityTest is accepted. Nothing done.', 16, 1);
    RETURN;
END;

DECLARE @prefix     NVARCHAR(11) = N'ESSAI-12B';
DECLARE @authorId   NVARCHAR(64) = N'sql-essai';
DECLARE @authorName NVARCHAR(100) = N'Donnees SQL (essai)';

DECLARE @farm1 NVARCHAR(20) = @prefix + N'-F1';
DECLARE @farm2 NVARCHAR(20) = @prefix + N'-F2';
DECLARE @s1    NVARCHAR(20) = @prefix + N'-S1';
DECLARE @s2    NVARCHAR(20) = @prefix + N'-S2';
DECLARE @s3    NVARCHAR(20) = @prefix + N'-S3';
DECLARE @l1    NVARCHAR(30) = @prefix + N'-L1';
DECLARE @l2    NVARCHAR(30) = @prefix + N'-L2';

DECLARE @harvest DATE = '2026-11-10';
DECLARE @t0630 DATETIME2 = '2026-11-10T06:30:00';
DECLARE @t0915 DATETIME2 = '2026-11-10T09:15:00';
DECLARE @t1340 DATETIME2 = '2026-11-10T13:40:00';
DECLARE @t1705 DATETIME2 = '2026-11-10T17:05:00';

-- Farms, stations and functions.
EXEC trace.CreateFarm    @Code = @farm1, @Name = N'Ferme d''essai 12b (1)', @Region = N'Essai';
EXEC trace.CreateFarm    @Code = @farm2, @Name = N'Ferme d''essai 12b (2)', @Region = N'Essai';
EXEC trace.CreateStation @Code = @s1, @Name = N'Station d''essai 1';
EXEC trace.CreateStation @Code = @s2, @Name = N'Station d''essai 2';
EXEC trace.CreateStation @Code = @s3, @Name = N'Station d''essai 3';
EXEC trace.AddStationCapability @StationCode = @s1, @MovementType = N'RECEPTION';
EXEC trace.AddStationCapability @StationCode = @s1, @MovementType = N'SORTING';
EXEC trace.AddStationCapability @StationCode = @s2, @MovementType = N'PACKING';
EXEC trace.AddStationCapability @StationCode = @s3, @MovementType = N'SHIPMENT';

-- Batch 1: goes all the way to the shipment (correction of a shipped sheet).
EXEC trace.CreateBatch @BatchCode = @l1, @FarmCode = @farm1, @Variety = N'Roma', @HarvestDate = @harvest,
     @QuantityKg = 500, @StationCode = @s1, @OccurredAt = @t0630, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l1, @StationCode = @s1, @MovementType = N'SORTING',
     @QuantityKg = 470, @OccurredAt = @t0915, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l1, @StationCode = @s2, @MovementType = N'PACKING',
     @QuantityKg = 465, @OccurredAt = @t1340, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l1, @StationCode = @s3, @MovementType = N'SHIPMENT',
     @QuantityKg = 460, @OccurredAt = @t1705, @AuthorId = @authorId, @AuthorName = @authorName;

-- Batch 2: stops after the sorting.
EXEC trace.CreateBatch @BatchCode = @l2, @FarmCode = @farm1, @Variety = N'Cherry', @HarvestDate = @harvest,
     @QuantityKg = 500, @StationCode = @s1, @OccurredAt = @t0630, @AuthorId = @authorId, @AuthorName = @authorName;
EXEC trace.AddMovement @BatchCode = @l2, @StationCode = @s1, @MovementType = N'SORTING',
     @QuantityKg = 470, @OccurredAt = @t0915, @AuthorId = @authorId, @AuthorName = @authorName;

-- What was created: expected SHIPPED 460.00 for L1 and SORTED 470.00 for L2,
-- both on farm <prefix>-F1, harvest 2026-11-10.
SELECT b.BatchCode, b.Status, b.QuantityKg, f.Code AS FarmCode, b.Variety, b.HarvestDate
FROM trace.Batch AS b
JOIN trace.Farm AS f ON f.FarmId = b.FarmId
WHERE b.BatchCode IN (@l1, @l2)
ORDER BY b.BatchCode;
GO
