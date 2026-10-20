/*
  006_check_procedures.sql
  Tests the 7 stored procedures of the schema trace (contract: docs/procedures.md).

  - Runs ONLY on TraceabilityTest. The name is written in the script, so SQLCMD
    mode is not needed. On any other database the script refuses to run.
  - Run 001, 002, 004 and 005 on TraceabilityTest first.
  - Replayable: it first removes the test rows of a previous run (codes that start
    with ZZ-), with DELETE ... WHERE only. Other rows are never touched.
  - Unlike 003, nothing is rolled back: the procedures have their own transactions.
    The test rows stay in TraceabilityTest until the next run.
  - A refusal test is OK if: the error number is the expected one, the data is
    unchanged (dbo.TestFingerprint), and no transaction is left open.
    A control test is OK if the valid case is accepted AND has the expected effect.
  - Tests 30, 32, 33 and 38 (GetBatch, ListBatches) return two result sets: the script
    checks their number and shape (WITH RESULT SETS), their content is checked BY EYE.
    Tests 32, 33 and 38 show what to expect in the grid, before the results (changed
    when ListBatches got its total).
  - Creates one helper function in TraceabilityTest only: dbo.TestFingerprint().
*/

USE TraceabilityTest;
GO

-- Safety 1: only TraceabilityTest. Otherwise nothing below is executed.
IF DB_NAME() <> N'TraceabilityTest'
BEGIN
    RAISERROR(N'Wrong database. These tests run only on TraceabilityTest. Nothing was done.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Safety 2: the 7 procedures must exist (004 and 005).
IF (SELECT COUNT(*) FROM sys.procedures
    WHERE schema_id = SCHEMA_ID(N'trace')
      AND name IN (N'CreateFarm', N'CreateStation', N'AddStationCapability',
                   N'CreateBatch', N'AddMovement', N'GetBatch', N'ListBatches')) <> 7
BEGIN
    RAISERROR(N'The 7 procedures of the schema trace are missing. Run 004 and 005 first. Nothing was done.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Helper: a short "fingerprint" of the 5 tables (row counts + a checksum of the
-- status and quantity of every batch). Read before and after a refusal: if it
-- changed, the refused call changed something.
CREATE OR ALTER FUNCTION dbo.TestFingerprint()
RETURNS NVARCHAR(200)
AS
BEGIN
    RETURN CONCAT(
        (SELECT COUNT(*) FROM trace.Farm), N'/',
        (SELECT COUNT(*) FROM trace.Station), N'/',
        (SELECT COUNT(*) FROM trace.StationCapability), N'/',
        (SELECT COUNT(*) FROM trace.Batch), N'/',
        (SELECT COUNT(*) FROM trace.Movement), N'/',
        (SELECT CHECKSUM_AGG(CHECKSUM(BatchId, Status, QuantityKg)) FROM trace.Batch));
END;
GO

-- Cleanup of a previous run. DELETE with WHERE only, in the order of the foreign
-- keys, and only the rows whose code starts with ZZ- (test data).
DELETE FROM trace.Movement
WHERE BatchId IN (SELECT BatchId FROM trace.Batch WHERE BatchCode LIKE N'ZZ-%');

DELETE FROM trace.Batch
WHERE BatchCode LIKE N'ZZ-%';

DELETE FROM trace.StationCapability
WHERE StationId IN (SELECT StationId FROM trace.Station WHERE Code LIKE N'ZZ-%');

DELETE FROM trace.Station
WHERE Code LIKE N'ZZ-%';

DELETE FROM trace.Farm
WHERE Code LIKE N'ZZ-%';
GO

/* ===================== Setup and the 38 tests (one batch) ===================== */

SET NOCOUNT ON;

DECLARE @results TABLE
(
    test_no   INT IDENTITY(1,1),
    test_name NVARCHAR(100),
    expected  NVARCHAR(100),
    outcome   NVARCHAR(250),
    detail    NVARCHAR(250)
);
DECLARE @before NVARCHAR(200);

-- Tables that receive what the procedures return.
DECLARE @farmOut    TABLE (FarmId INT, Code NVARCHAR(20), Name NVARCHAR(100), Region NVARCHAR(100));
DECLARE @stationOut TABLE (StationId INT, Code NVARCHAR(20), Name NVARCHAR(100));

-- Setup: starting data inserted DIRECTLY in the tables (not through the procedures),
-- so a defect in a procedure cannot spoil the tests of another one.
BEGIN TRY
    INSERT trace.Farm (Code, Name, Region)
    VALUES (N'ZZ-F01', N'Test farm 1', N'Test region'),
           (N'ZZ-F02', N'Test farm 2', N'Test region'),
           (N'ZZ-F03', N'Test farm 3', N'Test region');

    INSERT trace.Station (Code, Name)
    VALUES (N'ZZ-S01', N'Test station 1'),   -- RECEPTION and SORTING
           (N'ZZ-S02', N'Test station 2'),   -- PACKING
           (N'ZZ-S03', N'Test station 3'),   -- SHIPMENT
           (N'ZZ-S04', N'Test station 4');   -- SORTING only (no RECEPTION)

    INSERT trace.StationCapability (StationId, MovementType)
    SELECT s.StationId, v.MovementType
    FROM (VALUES (N'ZZ-S01', N'RECEPTION'), (N'ZZ-S01', N'SORTING'),
                 (N'ZZ-S02', N'PACKING'),
                 (N'ZZ-S03', N'SHIPMENT'),
                 (N'ZZ-S04', N'SORTING')) AS v (StationCode, MovementType)
    JOIN trace.Station AS s ON s.Code = v.StationCode;

    -- ZZ-B-W1: control of AddMovement. ZZ-B-RECV: stays RECEIVED, used by refusals.
    -- ZZ-B-SORT: SORTED. ZZ-B-SHIP: SHIPPED. ZZ-B-F2A/F2B: the 2 batches of farm F02.
    -- ZZ-P1..P5: the 5 batches of farm F03, for the pages (ORDER BY gives the numbers).
    INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
    SELECT v.BatchCode, f.FarmId, N'Test variety', '2026-10-14', v.QuantityKg, v.Status
    FROM (VALUES (N'ZZ-B-W1',   N'ZZ-F01', 500.00, N'RECEIVED'),
                 (N'ZZ-B-RECV', N'ZZ-F01', 500.00, N'RECEIVED'),
                 (N'ZZ-B-SORT', N'ZZ-F01', 470.00, N'SORTED'),
                 (N'ZZ-B-SHIP', N'ZZ-F01', 465.00, N'SHIPPED'),
                 (N'ZZ-B-F2A',  N'ZZ-F02', 100.00, N'RECEIVED'),
                 (N'ZZ-B-F2B',  N'ZZ-F02', 100.00, N'SHIPPED'),
                 (N'ZZ-P1',     N'ZZ-F03', 100.00, N'RECEIVED'),
                 (N'ZZ-P2',     N'ZZ-F03', 100.00, N'RECEIVED'),
                 (N'ZZ-P3',     N'ZZ-F03', 100.00, N'RECEIVED'),
                 (N'ZZ-P4',     N'ZZ-F03', 100.00, N'RECEIVED'),
                 (N'ZZ-P5',     N'ZZ-F03', 100.00, N'RECEIVED')) AS v (BatchCode, FarmCode, QuantityKg, Status)
    JOIN trace.Farm AS f ON f.Code = v.FarmCode
    ORDER BY v.BatchCode;
END TRY
BEGIN CATCH
    DECLARE @setup_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup failed, tests not run: %s', 16, 1, @setup_error);
    RETURN;
END CATCH;

/* ---------- Farms, stations, functions (tests 1 to 11) ---------- */

-- 1. CreateFarm: control (valid farm created and returned)
BEGIN TRY
    INSERT @farmOut EXEC trace.CreateFarm
         @Code = N'ZZ-F10', @Name = N'Created farm', @Region = N'Test region';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: control (valid farm created and returned)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM @farmOut WHERE Code = N'ZZ-F10') = 1
                 AND (SELECT COUNT(*) FROM trace.Farm WHERE Code = N'ZZ-F10' AND Name = N'Created farm') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The farm is returned by the procedure and exists in the table');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: control (valid farm created and returned)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 2. CreateFarm: empty code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateFarm
         @Code = N'   ', @Name = N'x', @Region = N'x';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: empty code', N'50400', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: empty code', N'50400',
            CASE WHEN ERROR_NUMBER() <> 50400
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 3. CreateFarm: duplicate code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateFarm
         @Code = N'ZZ-F01', @Name = N'x', @Region = N'x';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: duplicate code', N'50200', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: duplicate code', N'50200',
            CASE WHEN ERROR_NUMBER() <> 50200
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 4. CreateFarm: duplicate code, other case
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateFarm
         @Code = N'zz-f01', @Name = N'x', @Region = N'x';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: duplicate code, other case', N'50200', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateFarm: duplicate code, other case', N'50200',
            CASE WHEN ERROR_NUMBER() <> 50200
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 5. CreateStation: control (valid station created and returned)
BEGIN TRY
    INSERT @stationOut EXEC trace.CreateStation
         @Code = N'ZZ-S10', @Name = N'Created station';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateStation: control (valid station created and returned)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM @stationOut WHERE Code = N'ZZ-S10') = 1
                 AND (SELECT COUNT(*) FROM trace.Station WHERE Code = N'ZZ-S10' AND Name = N'Created station') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The station is returned by the procedure and exists in the table');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateStation: control (valid station created and returned)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 6. CreateStation: empty code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateStation
         @Code = N'   ', @Name = N'x';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateStation: empty code', N'50400', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateStation: empty code', N'50400',
            CASE WHEN ERROR_NUMBER() <> 50400
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 7. CreateStation: duplicate code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateStation
         @Code = N'ZZ-S01', @Name = N'x';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateStation: duplicate code', N'50201', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateStation: duplicate code', N'50201',
            CASE WHEN ERROR_NUMBER() <> 50201
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 8. AddStationCapability: control (lower case in, capitals stored)
BEGIN TRY
    EXEC trace.AddStationCapability
         @StationCode = N'ZZ-S10', @MovementType = N'reception';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: control (lower case in, capitals stored)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.StationCapability AS sc
                 JOIN trace.Station AS s ON s.StationId = sc.StationId
                 WHERE s.Code = N'ZZ-S10'
                   AND sc.MovementType = N'RECEPTION' COLLATE Latin1_General_CS_AS) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'Given as reception, stored as RECEPTION (case-sensitive comparison)');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: control (lower case in, capitals stored)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 9. AddStationCapability: unknown movement type
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddStationCapability
         @StationCode = N'ZZ-S01', @MovementType = N'LOST';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: unknown movement type', N'50402', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: unknown movement type', N'50402',
            CASE WHEN ERROR_NUMBER() <> 50402
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 10. AddStationCapability: unknown station
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddStationCapability
         @StationCode = N'ZZ-NOPE', @MovementType = N'RECEPTION';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: unknown station', N'50102', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: unknown station', N'50102',
            CASE WHEN ERROR_NUMBER() <> 50102
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 11. AddStationCapability: function already declared
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddStationCapability
         @StationCode = N'ZZ-S01', @MovementType = N'RECEPTION';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: function already declared', N'50203', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddStationCapability: function already declared', N'50203',
            CASE WHEN ERROR_NUMBER() <> 50203
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- CreateBatch (tests 12 to 18) ---------- */

-- 12. CreateBatch: control (batch RECEIVED and its RECEPTION movement)
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-NEW', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: control (batch RECEIVED and its RECEPTION movement)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch
                 WHERE BatchCode = N'ZZ-B-NEW' AND Status = N'RECEIVED' AND QuantityKg = 500.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-B-NEW') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-B-NEW' AND m.MovementType = N'RECEPTION' AND m.QuantityKg = 500.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'One batch RECEIVED at 500.00 kg and exactly one RECEPTION movement');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: control (batch RECEIVED and its RECEPTION movement)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 13. CreateBatch: empty code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'   ', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: empty code', N'50400', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: empty code', N'50400',
            CASE WHEN ERROR_NUMBER() <> 50400
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 14. CreateBatch: quantity 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X14', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 0, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: quantity 0', N'50401', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: quantity 0', N'50401',
            CASE WHEN ERROR_NUMBER() <> 50401
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 15. CreateBatch: unknown farm
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X15', @FarmCode = N'ZZ-NOPE', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: unknown farm', N'50101', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: unknown farm', N'50101',
            CASE WHEN ERROR_NUMBER() <> 50101
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 16. CreateBatch: unknown station
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X16', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-NOPE',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: unknown station', N'50102', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: unknown station', N'50102',
            CASE WHEN ERROR_NUMBER() <> 50102
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 17. CreateBatch: duplicate code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-RECV', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: duplicate code', N'50202', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: duplicate code', N'50202',
            CASE WHEN ERROR_NUMBER() <> 50202
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 18. CreateBatch: station without the RECEPTION function
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X18', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S04',
         @OccurredAt = '2026-10-14T06:30:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: station without the RECEPTION function', N'50303', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: station without the RECEPTION function', N'50303',
            CASE WHEN ERROR_NUMBER() <> 50303
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- AddMovement (tests 19 to 29) ---------- */

-- 19. AddMovement: control (RECEIVED to SORTED)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-W1', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (RECEIVED to SORTED)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch
                 WHERE BatchCode = N'ZZ-B-W1' AND Status = N'SORTED' AND QuantityKg = 470.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-B-W1') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-B-W1' AND m.MovementType = N'SORTING' AND m.QuantityKg = 470.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'Batch SORTED at 470.00 kg, one SORTING movement added');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (RECEIVED to SORTED)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 20. AddMovement: control (full path to SHIPPED, equal quantity accepted)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-NEW', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00';
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-NEW', @StationCode = N'ZZ-S02', @MovementType = N'PACKING',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T13:40:00';
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-NEW', @StationCode = N'ZZ-S03', @MovementType = N'SHIPMENT',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T17:05:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (full path to SHIPPED, equal quantity accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch
                 WHERE BatchCode = N'ZZ-B-NEW' AND Status = N'SHIPPED' AND QuantityKg = 465.00) = 1
                 AND (SELECT STRING_AGG(m.MovementType, N',') WITHIN GROUP (ORDER BY m.MovementId)
                      FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-B-NEW') = N'RECEPTION,SORTING,PACKING,SHIPMENT'
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'Batch SHIPPED at 465.00 kg, movements in order RECEPTION, SORTING, PACKING, SHIPMENT (needs test 12)');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (full path to SHIPPED, equal quantity accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 21. AddMovement: quantity 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 0, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: quantity 0', N'50401', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: quantity 0', N'50401',
            CASE WHEN ERROR_NUMBER() <> 50401
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 22. AddMovement: unknown movement type
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S01', @MovementType = N'LOST',
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: unknown movement type', N'50402', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: unknown movement type', N'50402',
            CASE WHEN ERROR_NUMBER() <> 50402
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 23. AddMovement: unknown batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-NOPE', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: unknown batch', N'50100', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: unknown batch', N'50100',
            CASE WHEN ERROR_NUMBER() <> 50100
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 24. AddMovement: unknown station
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-NOPE', @MovementType = N'SORTING',
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: unknown station', N'50102', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: unknown station', N'50102',
            CASE WHEN ERROR_NUMBER() <> 50102
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 25. AddMovement: batch already SHIPPED
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-SHIP', @StationCode = N'ZZ-S03', @MovementType = N'SHIPMENT',
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: batch already SHIPPED', N'50300', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: batch already SHIPPED', N'50300',
            CASE WHEN ERROR_NUMBER() <> 50300
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 26. AddMovement: step skipped (RECEIVED then PACKING)
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S02', @MovementType = N'PACKING',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: step skipped (RECEIVED then PACKING)', N'50301', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: step skipped (RECEIVED then PACKING)', N'50301',
            CASE WHEN ERROR_NUMBER() <> 50301
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 27. AddMovement: step repeated (SORTED then SORTING)
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-SORT', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: step repeated (SORTED then SORTING)', N'50301', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: step repeated (SORTED then SORTING)', N'50301',
            CASE WHEN ERROR_NUMBER() <> 50301
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 28. AddMovement: station without the function
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S02', @MovementType = N'SORTING',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: station without the function', N'50303', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: station without the function', N'50303',
            CASE WHEN ERROR_NUMBER() <> 50303
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 29. AddMovement: quantity goes up
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 520.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: quantity goes up', N'50302', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: quantity goes up', N'50302',
            CASE WHEN ERROR_NUMBER() <> 50302
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- GetBatch (tests 30 and 31) ---------- */

-- 30. GetBatch: control (the shape is checked by the script, the content BY EYE)
PRINT N'Test 30: GetBatch ZZ-B-NEW. Check by eye the two result sets displayed just below:';
PRINT N'  1) one row: ZZ-B-NEW, ZZ-F01, Cherry, 2026-10-14, 465.00, SHIPPED';
PRINT N'  2) four rows, in this order: RECEPTION ZZ-S01 500.00 / SORTING ZZ-S01 470.00 / PACKING ZZ-S02 465.00 / SHIPMENT ZZ-S03 465.00';
BEGIN TRY
    EXEC trace.GetBatch @BatchCode = N'ZZ-B-NEW'
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (MovementId BIGINT, MovementType NVARCHAR(20), StationCode NVARCHAR(20),
         QuantityKg DECIMAL(10,2), OccurredAt DATETIME2)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: control (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: control (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 31. GetBatch: unknown batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.GetBatch
         @BatchCode = N'ZZ-B-NOPE';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: unknown batch', N'50100', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: unknown batch', N'50100',
            CASE WHEN ERROR_NUMBER() <> 50100
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- ListBatches (tests 32 to 38) ---------- */

-- 32. ListBatches: filter by status (shape checked by the script, content BY EYE)
SELECT N'Test 32: ListBatches, status SORTED, page 1, page size 1000. Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) only SORTED rows: ZZ-B-SORT is in the list, ZZ-B-RECV is not' AS result_set_1,
       CONCAT(N'2) one row: TotalCount = ', (SELECT COUNT(*) FROM trace.Batch WHERE Status = N'SORTED')) AS result_set_2;
BEGIN TRY
    EXEC trace.ListBatches
         @Status = N'SORTED', @FarmCode = NULL, @PageNumber = 1,
         @PageSize = 1000
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: filter by status (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: filter by status (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 33. ListBatches: filter by farm (shape checked by the script, content BY EYE)
SELECT N'Test 33: ListBatches, farm ZZ-F02, page 1, page size 1000. Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) exactly 2 rows, both with FarmCode ZZ-F02: ZZ-B-F2A and ZZ-B-F2B' AS result_set_1,
       N'2) one row: TotalCount = 2' AS result_set_2;
BEGIN TRY
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = N'ZZ-F02', @PageNumber = 1,
         @PageSize = 1000
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: filter by farm (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: filter by farm (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 34. ListBatches: unknown status
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListBatches
         @Status = N'LOST', @FarmCode = NULL, @PageNumber = 1,
         @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: unknown status', N'50403', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: unknown status', N'50403',
            CASE WHEN ERROR_NUMBER() <> 50403
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 35. ListBatches: unknown farm
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = N'ZZ-NOPE', @PageNumber = 1,
         @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: unknown farm', N'50101', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: unknown farm', N'50101',
            CASE WHEN ERROR_NUMBER() <> 50101
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 36. ListBatches: page number 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = NULL, @PageNumber = 0,
         @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: page number 0', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: page number 0', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 37. ListBatches: page size 1001
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = NULL, @PageNumber = 1,
         @PageSize = 1001;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: page size 1001', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: page size 1001', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 38. ListBatches: pages follow each other (shape checked by the script, content BY EYE)
SELECT N'Test 38: ListBatches, farm ZZ-F03, page size 2, pages 1, 2 and 3. Check by eye the 6 result sets just below (2 per page).' AS check_by_eye,
       N'rows: page 1 = ZZ-P1, ZZ-P2 / page 2 = ZZ-P3, ZZ-P4 / page 3 = ZZ-P5 (no gap, no duplicate)' AS rows_expected,
       N'totals: each page is followed by one row, TotalCount = 5' AS totals_expected;
BEGIN TRY
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = N'ZZ-F03', @PageNumber = 1,
         @PageSize = 2
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (TotalCount INT)
    );
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = N'ZZ-F03', @PageNumber = 2,
         @PageSize = 2
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (TotalCount INT)
    );
    EXEC trace.ListBatches
         @Status = NULL, @FarmCode = N'ZZ-F03', @PageNumber = 3,
         @PageSize = 2
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: pages follow each other (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 6 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListBatches: pages follow each other (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;


/* ===================== Results ===================== */

-- Result of each test.
SELECT test_no, test_name, expected, outcome, detail
FROM @results
ORDER BY test_no;

-- Summary: tests_ok + tests_by_eye must equal tests_total.
SELECT COUNT(*) AS tests_total,
       SUM(CASE WHEN outcome IN (N'Refused as expected', N'Accepted as expected')
                THEN 1 ELSE 0 END) AS tests_ok,
       SUM(CASE WHEN outcome LIKE N'To check by eye%' THEN 1 ELSE 0 END) AS tests_by_eye
FROM @results;

-- Left for the manual lock test: ZZ-B-RECV must still be RECEIVED at 500.00 kg.
SELECT BatchCode, Status, QuantityKg
FROM trace.Batch
WHERE BatchCode = N'ZZ-B-RECV';
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO
