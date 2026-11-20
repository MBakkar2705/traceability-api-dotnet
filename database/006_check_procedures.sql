/*
  006_check_procedures.sql
  Tests the 10 stored procedures of the schema trace (contract: docs/procedures.md).

  - Runs ONLY on TraceabilityTest. The name is written in the script, so SQLCMD
    mode is not needed. On any other database the script refuses to run.
  - Run 001, 002, 004 and 005 on TraceabilityTest first (a database made before lot 12a also
    needs 019, then 005 again; a database made before lot 12b also needs 020, then 005 again).
  - Replayable: it first removes the test rows of a previous run (codes that start
    with ZZ-), with DELETE ... WHERE only. Other rows are never touched.
  - Unlike 003, nothing is rolled back: the procedures have their own transactions.
    The test rows stay in TraceabilityTest until the next run.
  - A refusal test is OK if: the error number is the expected one, the data is
    unchanged (dbo.TestFingerprint), and no transaction is left open.
    A control test is OK if the valid case is accepted AND has the expected effect.
  - Lot 11: every call of CreateBatch and AddMovement gives an author. Tests 39 to 47 are about
    the author (recorded, returned by GetBatch, refused when empty or too long, required).
  - Lot 12a: tests 48 to 88 are about the corrections (ReplaceMovement, CancelMovement, and the
    new GetBatch). They use their own batches ZZ-C1 to ZZ-C4 and depend on each other: do not
    reorder them.
  - Lot 12b: tests 89 to 122 are about the correction of the sheet of a batch (CorrectBatch), the
    old codes (AddMovement, ReplaceMovement, CancelMovement, CreateBatch, GetBatch) and the harvest
    date rule. They use their own batches ZZ-D1 to ZZ-D4 (and ZZ-P5) and depend on each other: do
    not reorder them.
  - Lot 12c: tests 123 to 150 are about the time of the movements: 50310 (a time in the future, 5
    minutes accepted) and 50311 (a time not strictly after the previous valid movement, or not
    strictly before the next one; checked by AddMovement and by ReplaceMovement when the time
    changes). They use their own batches ZZ-T1 to ZZ-T10 and depend on each other: do not reorder
    them. The limit of exactly 5 minutes is not tested (the clock of the server moves): the tests
    use 4 minutes (accepted) and 6 minutes (refused).
  - 003 cannot be run after this script: it leaves its ZZ- rows and 003 refuses to start (see the
    header of 003).
  - Tests 32, 33 and 38 (ListBatches) return two result sets, tests 30, 41, 86 and 87 (GetBatch)
    return four: the script checks their number and shape (WITH RESULT SETS), their content is
    checked BY EYE.
    Tests 32, 33 and 38 show what to expect in the grid, before the results (changed
    when ListBatches got its total).
  - Creates one helper function in TraceabilityTest only: dbo.TestFingerprint().
  - Verdict (lot 9): at the end, the script raises an error (RAISERROR, severity 16) if a test is
    marked ATTENTION or if the counts do not add up, so that a run with sqlcmd -b fails (CI).
    A test "to check by eye" counts as passed there for its shape only: its content is still
    checked BY EYE.
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

-- Safety 2: the 10 procedures must exist (004 and 005).
IF (SELECT COUNT(*) FROM sys.procedures
    WHERE schema_id = SCHEMA_ID(N'trace')
      AND name IN (N'CreateFarm', N'CreateStation', N'AddStationCapability',
                   N'CreateBatch', N'AddMovement', N'GetBatch', N'ListBatches',
                   N'ReplaceMovement', N'CancelMovement', N'CorrectBatch')) <> 10
BEGIN
    RAISERROR(N'The 10 procedures of the schema trace are missing. Run 004 and 005 first (019 and 020 before them if the table MovementCorrection or BatchCorrection is missing). Nothing was done.', 16, 1);
    SET NOEXEC ON;
END;
GO

-- Helper: a short "fingerprint" of the 7 tables (row counts + a checksum of the code, farm, variety,
-- harvest date, status and quantity of every batch + a checksum of the journal). Read before and after
-- a refusal: if it changed, the refused call changed something.
CREATE OR ALTER FUNCTION dbo.TestFingerprint()
RETURNS NVARCHAR(300)
AS
BEGIN
    RETURN CONCAT(
        (SELECT COUNT(*) FROM trace.Farm), N'/',
        (SELECT COUNT(*) FROM trace.Station), N'/',
        (SELECT COUNT(*) FROM trace.StationCapability), N'/',
        (SELECT COUNT(*) FROM trace.Batch), N'/',
        (SELECT COUNT(*) FROM trace.Movement), N'/',
        (SELECT COUNT(*) FROM trace.MovementCorrection), N'/',
        (SELECT COUNT(*) FROM trace.BatchCorrection), N'/',
        (SELECT CHECKSUM_AGG(CHECKSUM(BatchId, BatchCode, FarmId, Variety, HarvestDate, Status, QuantityKg))
         FROM trace.Batch), N'/',
        (SELECT CHECKSUM_AGG(CHECKSUM(MovementId, StationId, QuantityKg, OccurredAt)) FROM trace.Movement));
END;
GO

-- Cleanup of a previous run. DELETE with WHERE only, in the order of the foreign
-- keys, and only the rows whose code starts with ZZ- (test data).
DELETE FROM trace.BatchCorrection
WHERE BatchId IN (SELECT BatchId FROM trace.Batch WHERE BatchCode LIKE N'ZZ-%');

DELETE FROM trace.MovementCorrection
WHERE MovementId IN (SELECT m.MovementId
                     FROM trace.Movement AS m
                     JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                     WHERE b.BatchCode LIKE N'ZZ-%');

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

/* ===================== Setup and the 150 tests (one batch) ===================== */

SET NOCOUNT ON;

DECLARE @results TABLE
(
    test_no   INT IDENTITY(1,1),
    test_name NVARCHAR(100),
    expected  NVARCHAR(100),
    outcome   NVARCHAR(250),
    detail    NVARCHAR(250)
);
DECLARE @before NVARCHAR(300);

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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-NEW', @StationCode = N'ZZ-S02', @MovementType = N'PACKING',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T13:40:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-NEW', @StationCode = N'ZZ-S03', @MovementType = N'SHIPMENT',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T17:05:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 0, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 100.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
         @QuantityKg = 520.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
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
PRINT N'Test 30: GetBatch ZZ-B-NEW. Check by eye the four result sets displayed just below:';
PRINT N'  1) one row: ZZ-B-NEW, ZZ-F01, Cherry, 2026-10-14, 465.00, SHIPPED';
PRINT N'  2) four rows, in this order: RECEPTION ZZ-S01 500.00 / SORTING ZZ-S01 470.00 / PACKING ZZ-S02 465.00 / SHIPMENT ZZ-S03 465.00';
PRINT N'     AuthorName is Test Author on the four rows, IsCancelled 0, CorrectionCount 0, Original columns = the values';
PRINT N'  3) no row (no correction)';
PRINT N'  4) no row (no correction of the sheet)';
BEGIN TRY
    EXEC trace.GetBatch @BatchCode = N'ZZ-B-NEW'
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (MovementId BIGINT, MovementType NVARCHAR(20), StationCode NVARCHAR(20),
         QuantityKg DECIMAL(10,2), OccurredAt DATETIME2, AuthorName NVARCHAR(100),
         IsCancelled BIT, CorrectionCount INT, OriginalStationCode NVARCHAR(20),
         OriginalQuantityKg DECIMAL(10,2), OriginalOccurredAt DATETIME2),
        (CorrectionId BIGINT, MovementId BIGINT, Kind NVARCHAR(10), MovementType NVARCHAR(20),
         StationCode NVARCHAR(20), QuantityKg DECIMAL(10,2), OccurredAt DATETIME2,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2),
        (CorrectionId BIGINT, OldBatchCode NVARCHAR(30), NewBatchCode NVARCHAR(30),
         OldFarmCode NVARCHAR(20), NewFarmCode NVARCHAR(20), OldVariety NVARCHAR(50),
         NewVariety NVARCHAR(50), OldHarvestDate DATE, NewHarvestDate DATE,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: control (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 4 result sets above)',
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


/* ---------- The author (tests 39 to 47, lot 11) ---------- */

-- Values longer than the columns (64 and 100 characters), for tests 44 and 46.
DECLARE @longAuthorId   NVARCHAR(200) = REPLICATE(N'x', 65);
DECLARE @longAuthorName NVARCHAR(200) = REPLICATE(N'x', 101);

-- 39. CreateBatch: the author is recorded on the first movement
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-AUT', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'author-id-1', @AuthorName = N'Author One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: the author is recorded on the first movement', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                       WHERE b.BatchCode = N'ZZ-B-AUT' AND m.MovementType = N'RECEPTION'
                         AND m.AuthorId = N'author-id-1' AND m.AuthorName = N'Author One') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The RECEPTION movement of ZZ-B-AUT has AuthorId author-id-1 and AuthorName Author One');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: the author is recorded on the first movement', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 40. AddMovement: each movement keeps its own author (needs test 39)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-AUT', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'author-id-2', @AuthorName = N'Author Two';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: each movement keeps its own author', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                       WHERE b.BatchCode = N'ZZ-B-AUT' AND m.MovementType = N'SORTING'
                         AND m.AuthorId = N'author-id-2' AND m.AuthorName = N'Author Two') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-B-AUT' AND m.MovementType = N'RECEPTION'
                        AND m.AuthorId = N'author-id-1' AND m.AuthorName = N'Author One') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'SORTING by Author Two, and RECEPTION still by Author One');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: each movement keeps its own author', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 41. GetBatch: the author name of each movement (shape checked by the script, content BY EYE; needs tests 39 and 40)
PRINT N'Test 41: GetBatch ZZ-B-AUT. Check by eye the four result sets displayed just below:';
PRINT N'  1) one row: ZZ-B-AUT, ZZ-F01, Cherry, 2026-10-14, 470.00, SORTED';
PRINT N'  2) two rows, in this order: RECEPTION ZZ-S01 500.00 ... Author One / SORTING ZZ-S01 470.00 ... Author Two (column AuthorName)';
PRINT N'  3) no row (no correction)';
PRINT N'  4) no row (no correction of the sheet)';
BEGIN TRY
    EXEC trace.GetBatch @BatchCode = N'ZZ-B-AUT'
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (MovementId BIGINT, MovementType NVARCHAR(20), StationCode NVARCHAR(20),
         QuantityKg DECIMAL(10,2), OccurredAt DATETIME2, AuthorName NVARCHAR(100),
         IsCancelled BIT, CorrectionCount INT, OriginalStationCode NVARCHAR(20),
         OriginalQuantityKg DECIMAL(10,2), OriginalOccurredAt DATETIME2),
        (CorrectionId BIGINT, MovementId BIGINT, Kind NVARCHAR(10), MovementType NVARCHAR(20),
         StationCode NVARCHAR(20), QuantityKg DECIMAL(10,2), OccurredAt DATETIME2,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2),
        (CorrectionId BIGINT, OldBatchCode NVARCHAR(30), NewBatchCode NVARCHAR(30),
         OldFarmCode NVARCHAR(20), NewFarmCode NVARCHAR(20), OldVariety NVARCHAR(50),
         NewVariety NVARCHAR(50), OldHarvestDate DATE, NewHarvestDate DATE,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: the author name of each movement (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 4 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: the author name of each movement (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 42. CreateBatch: blank author id
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X42', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'   ', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: blank author id', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: blank author id', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 43. CreateBatch: blank author name
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X43', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'   ';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: blank author name', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: blank author name', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 44. CreateBatch: author id too long
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X44', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = @longAuthorId, @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: author id too long', N'50406', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: author id too long', N'50406',
            CASE WHEN ERROR_NUMBER() <> 50406
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 45. AddMovement: author id NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = NULL, @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: author id NULL', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: author id NULL', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 46. AddMovement: author name too long
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'test-author-id', @AuthorName = @longAuthorName;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: author name too long', N'50406', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: author name too long', N'50406',
            CASE WHEN ERROR_NUMBER() <> 50406
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 47. AddMovement: author parameters not given
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-RECV', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: author parameters not given', N'201', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: author parameters not given', N'201',
            CASE WHEN ERROR_NUMBER() <> 201
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- Corrections (tests 48 to 88, lot 12a) ---------- */

-- Data of this part, inserted DIRECTLY in the tables (like the setup above), so that a defect
-- in a procedure cannot spoil the starting point. Each batch has its own role:
--   ZZ-C1 SHIPPED 465 (RECEPTION 500, SORTING 470, PACKING 465, SHIPMENT 465): replaced then cancelled.
--   ZZ-C2 PACKED  465 (RECEPTION 500, SORTING 470, PACKING 465): cancelled step by step, then a new movement.
--   ZZ-C3 RECEIVED 500 (RECEPTION 500): the RECEPTION cannot be cancelled.
--   ZZ-C4 PACKED  465 (RECEPTION 500, SORTING 470, PACKING 465): the equal quantity is accepted.
-- The tests below depend on each other (they are run in this order, like 39 to 41).
DECLARE @c1_rec  BIGINT, @c1_sort BIGINT, @c1_pack BIGINT, @c1_ship BIGINT;
DECLARE @c2_rec  BIGINT, @c2_sort BIGINT, @c2_pack BIGINT;
DECLARE @c3_rec  BIGINT, @c4_pack BIGINT;
DECLARE @comment500 NVARCHAR(2000) = REPLICATE(N'c', 500);
DECLARE @comment501 NVARCHAR(2000) = REPLICATE(N'c', 501);

BEGIN TRY
    INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
    SELECT v.BatchCode, f.FarmId, N'Test variety', '2026-10-14', v.QuantityKg, v.Status
    FROM (VALUES (N'ZZ-C1', 465.00, N'SHIPPED'),
                 (N'ZZ-C2', 465.00, N'PACKED'),
                 (N'ZZ-C3', 500.00, N'RECEIVED'),
                 (N'ZZ-C4', 465.00, N'PACKED')) AS v (BatchCode, QuantityKg, Status)
    CROSS JOIN trace.Farm AS f
    WHERE f.Code = N'ZZ-F01'
    ORDER BY v.BatchCode;

    INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt, AuthorId, AuthorName)
    SELECT b.BatchId, st.StationId, v.MovementType, v.QuantityKg, v.OccurredAt, N'orig-id', N'Original Author'
    FROM (VALUES (N'ZZ-C1', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-C1', N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-C1', N'ZZ-S02', N'PACKING',   465.00, '2026-10-14T13:40:00'),
                 (N'ZZ-C1', N'ZZ-S03', N'SHIPMENT',  465.00, '2026-10-14T17:05:00'),
                 (N'ZZ-C2', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-C2', N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-C2', N'ZZ-S02', N'PACKING',   465.00, '2026-10-14T13:40:00'),
                 (N'ZZ-C3', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-C4', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-C4', N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-C4', N'ZZ-S02', N'PACKING',   465.00, '2026-10-14T13:40:00')
         ) AS v (BatchCode, StationCode, MovementType, QuantityKg, OccurredAt)
    JOIN trace.Batch   AS b  ON b.BatchCode = v.BatchCode
    JOIN trace.Station AS st ON st.Code = v.StationCode
    ORDER BY v.BatchCode, v.OccurredAt;

    SELECT @c1_rec  = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C1' AND m.MovementType = N'RECEPTION';
    SELECT @c1_sort = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C1' AND m.MovementType = N'SORTING';
    SELECT @c1_pack = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C1' AND m.MovementType = N'PACKING';
    SELECT @c1_ship = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C1' AND m.MovementType = N'SHIPMENT';
    SELECT @c2_rec  = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C2' AND m.MovementType = N'RECEPTION';
    SELECT @c2_sort = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C2' AND m.MovementType = N'SORTING';
    SELECT @c2_pack = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C2' AND m.MovementType = N'PACKING';
    SELECT @c3_rec  = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C3' AND m.MovementType = N'RECEPTION';
    SELECT @c4_pack = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-C4' AND m.MovementType = N'PACKING';
END TRY
BEGIN CATCH
    DECLARE @setup12a_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup of the correction tests failed, tests not run: %s', 16, 1, @setup12a_error);
    RETURN;
END CATCH;

/* ---------- ReplaceMovement: accepted cases (tests 48 to 53) ---------- */

-- 48. ReplaceMovement: control (middle step of a SHIPPED batch, journal unchanged)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 480.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (middle step of a SHIPPED batch, journal unchanged)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @c1_sort) = 1
                 AND (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c1_sort)
                   AND c.Kind = N'REPLACE' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND c.QuantityKg = 480.00 AND c.OccurredAt = '2026-10-14T09:15:00' AND c.ReasonCode = N'DATA_ENTRY_ERROR') = 1
                 AND (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @c1_sort AND ReasonComment = N'' AND AuthorId = N'sup-id-1' AND AuthorName = N'Supervisor One' AND CorrectedAt IS NOT NULL) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c1_sort
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND QuantityKg = 470.00 AND OccurredAt = '2026-10-14T09:15:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                 WHERE b.BatchCode = N'ZZ-C1') = 4
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C1' AND Status = N'SHIPPED' AND QuantityKg = 465.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'One REPLACE row (480.00 kg, reason and author recorded); the movement keeps 470.00 kg; the batch is not changed (not the last step)');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (middle step of a SHIPPED batch, journal unchanged)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 49. ReplaceMovement: control (last step: the batch quantity follows)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_ship, @StationCode = N'ZZ-S03',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T17:05:00',
         @ReasonCode = N'MEASUREMENT_ERROR', @ReasonComment = N'Scale was not zeroed',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (last step: the batch quantity follows)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c1_ship)
                   AND c.Kind = N'REPLACE' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S03')
                   AND c.QuantityKg = 460.00 AND c.OccurredAt = '2026-10-14T17:05:00' AND c.ReasonCode = N'MEASUREMENT_ERROR') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c1_ship
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S03')
                   AND QuantityKg = 465.00 AND OccurredAt = '2026-10-14T17:05:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C1' AND Status = N'SHIPPED' AND QuantityKg = 460.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The SHIPMENT is corrected to 460.00 kg; the batch stays SHIPPED and follows to 460.00 kg; the movement keeps 465.00 kg');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (last step: the batch quantity follows)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 50. ReplaceMovement: control (a second correction of the same movement, station and time)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S04',
         @QuantityKg = 480.00, @OccurredAt = '2026-10-14T10:00:00',
         @ReasonCode = N'OTHER', @ReasonComment = N'Wrong station on the sheet',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a second correction of the same movement, station and time)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @c1_sort) = 2
                 AND (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c1_sort)
                   AND c.Kind = N'REPLACE' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S04')
                   AND c.QuantityKg = 480.00 AND c.OccurredAt = '2026-10-14T10:00:00' AND c.ReasonCode = N'OTHER') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c1_sort
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND QuantityKg = 470.00 AND OccurredAt = '2026-10-14T09:15:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C1' AND Status = N'SHIPPED' AND QuantityKg = 460.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'Two corrections of the movement; the latest one (highest CorrectionId) has station ZZ-S04 and 10:00; the batch is not changed');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a second correction of the same movement, station and time)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 51. ReplaceMovement: control (reason code in lower case is stored in capitals, first step)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C2', @MovementId = @c2_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 510.00, @OccurredAt = '2026-10-14T06:30:00',
         @ReasonCode = N'measurement_error', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (reason code in lower case is stored in capitals, first step)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c2_rec)
                   AND c.Kind = N'REPLACE' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND c.QuantityKg = 510.00 AND c.OccurredAt = '2026-10-14T06:30:00' AND c.ReasonCode = N'MEASUREMENT_ERROR') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C2' AND Status = N'PACKED' AND QuantityKg = 465.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'ReasonCode MEASUREMENT_ERROR stored in capitals; the RECEPTION (no step before) can go up; the batch is not changed');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (reason code in lower case is stored in capitals, first step)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 52. ReplaceMovement: control (a quantity equal to the previous step is accepted)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C4', @MovementId = @c4_pack, @StationCode = N'ZZ-S02',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T13:40:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a quantity equal to the previous step is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c4_pack)
                   AND c.Kind = N'REPLACE' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S02')
                   AND c.QuantityKg = 470.00 AND c.OccurredAt = '2026-10-14T13:40:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C4' AND Status = N'PACKED' AND QuantityKg = 470.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'PACKING corrected to 470.00 kg (equal to the SORTING); the batch follows to 470.00 kg');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a quantity equal to the previous step is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 53. ReplaceMovement: control (a comment of exactly 500 characters, only step of the batch)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C3', @MovementId = @c3_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 495.00, @OccurredAt = '2026-10-14T06:30:00',
         @ReasonCode = N'OTHER', @ReasonComment = @comment500,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a comment of exactly 500 characters, only step of the batch)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @c3_rec AND LEN(ReasonComment) = 500) = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C3' AND Status = N'RECEIVED' AND QuantityKg = 495.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The 500 characters are stored whole (never cut); the batch is RECEIVED at 495.00 kg');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a comment of exactly 500 characters, only step of the batch)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- ReplaceMovement: refused cases (tests 54 to 69) ---------- */

-- 54. ReplaceMovement: unknown batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C-NOPE', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown batch', N'50100', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown batch', N'50100',
            CASE WHEN ERROR_NUMBER() <> 50100
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 55. ReplaceMovement: unknown station
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S-NOPE',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown station', N'50102', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown station', N'50102',
            CASE WHEN ERROR_NUMBER() <> 50102
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 56. ReplaceMovement: movement of another batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c3_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: movement of another batch', N'50103', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: movement of another batch', N'50103',
            CASE WHEN ERROR_NUMBER() <> 50103
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 57. ReplaceMovement: unknown movement
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = 999999999, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown movement', N'50103', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown movement', N'50103',
            CASE WHEN ERROR_NUMBER() <> 50103
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 58. ReplaceMovement: station without the function of the movement
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S02',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: station without the function of the movement', N'50303', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: station without the function of the movement', N'50303',
            CASE WHEN ERROR_NUMBER() <> 50303
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 59. ReplaceMovement: quantity higher than the previous step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 500.01, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity higher than the previous step', N'50304', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity higher than the previous step', N'50304',
            CASE WHEN ERROR_NUMBER() <> 50304
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 60. ReplaceMovement: quantity lower than the next step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 464.99, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity lower than the next step', N'50304', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity lower than the next step', N'50304',
            CASE WHEN ERROR_NUMBER() <> 50304
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 61. ReplaceMovement: same values as the current ones
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_ship, @StationCode = N'ZZ-S03',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T17:05:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: same values as the current ones', N'50308', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: same values as the current ones', N'50308',
            CASE WHEN ERROR_NUMBER() <> 50308
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 62. ReplaceMovement: quantity 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 0, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity 0', N'50401', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity 0', N'50401',
            CASE WHEN ERROR_NUMBER() <> 50401
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 63. ReplaceMovement: quantity NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = NULL, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity NULL', N'50401', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: quantity NULL', N'50401',
            CASE WHEN ERROR_NUMBER() <> 50401
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 64. ReplaceMovement: unknown reason
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'WRONG', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown reason', N'50407', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: unknown reason', N'50407',
            CASE WHEN ERROR_NUMBER() <> 50407
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 65. ReplaceMovement: reason NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = NULL, @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reason NULL', N'50407', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reason NULL', N'50407',
            CASE WHEN ERROR_NUMBER() <> 50407
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 66. ReplaceMovement: reason OTHER without a comment
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'OTHER', @ReasonComment = N'   ',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reason OTHER without a comment', N'50408', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reason OTHER without a comment', N'50408',
            CASE WHEN ERROR_NUMBER() <> 50408
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 67. ReplaceMovement: comment of 501 characters
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = @comment501,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: comment of 501 characters', N'50409', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: comment of 501 characters', N'50409',
            CASE WHEN ERROR_NUMBER() <> 50409
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 68. ReplaceMovement: blank author id
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'   ', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: blank author id', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: blank author id', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 69. ReplaceMovement: author name too long
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 475.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = @longAuthorName;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: author name too long', N'50406', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: author name too long', N'50406',
            CASE WHEN ERROR_NUMBER() <> 50406
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- CancelMovement: accepted cases (tests 70 to 74) ---------- */

-- 70. CancelMovement: control (last step: the batch goes back one step)
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C2', @MovementId = @c2_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (last step: the batch goes back one step)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c2_pack)
                   AND c.Kind = N'CANCEL' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S02')
                   AND c.QuantityKg = 465.00 AND c.OccurredAt = '2026-10-14T13:40:00' AND c.ReasonCode = N'DATA_ENTRY_ERROR') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c2_pack
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S02')
                   AND QuantityKg = 465.00 AND OccurredAt = '2026-10-14T13:40:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                 WHERE b.BatchCode = N'ZZ-C2') = 3
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C2' AND Status = N'SORTED' AND QuantityKg = 470.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'A CANCEL row repeats the values (465.00 kg); the movement is still in the journal; the batch is SORTED at 470.00 kg');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (last step: the batch goes back one step)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 71. CancelMovement: control (the step before is cancelled too: its corrected quantity is used)
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C2', @MovementId = @c2_sort,
         @ReasonCode = N'OTHER', @ReasonComment = N'Sorting was entered on the wrong batch',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (the step before is cancelled too: its corrected quantity is used)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c2_sort)
                   AND c.Kind = N'CANCEL' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND c.QuantityKg = 470.00 AND c.OccurredAt = '2026-10-14T09:15:00' AND c.ReasonCode = N'OTHER') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C2' AND Status = N'RECEIVED' AND QuantityKg = 510.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The batch is RECEIVED again, at 510.00 kg (the corrected RECEPTION, not the first 500.00 kg)');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (the step before is cancelled too: its corrected quantity is used)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 72. AddMovement: control (a new movement after a cancellation)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-C2', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 480.00, @OccurredAt = '2026-10-15T08:00:00',
         @AuthorId = N'author-id-3', @AuthorName = N'Author Three';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (a new movement after a cancellation)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C2' AND Status = N'SORTED' AND QuantityKg = 480.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                 WHERE b.BatchCode = N'ZZ-C2') = 4
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The batch is SORTED at 480.00 kg; the journal has 4 movements (the 2 cancelled ones stay)');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (a new movement after a cancellation)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 73. CancelMovement: control (SHIPPED batch: the shipment is cancelled, the batch is PACKED again)
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_ship,
         @ReasonCode = N'OTHER', @ReasonComment = N'Truck never left',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (SHIPPED batch: the shipment is cancelled, the batch is PACKED again)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c1_ship)
                   AND c.Kind = N'CANCEL' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S03')
                   AND c.QuantityKg = 460.00 AND c.OccurredAt = '2026-10-14T17:05:00' AND c.ReasonCode = N'OTHER') = 1
                 AND (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @c1_ship) = 2
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C1' AND Status = N'PACKED' AND QuantityKg = 465.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The CANCEL row repeats the corrected values (460.00 kg); the batch is PACKED at 465.00 kg');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (SHIPPED batch: the shipment is cancelled, the batch is PACKED again)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 74. ReplaceMovement: control (a cancelled step does not count for the limits)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_pack, @StationCode = N'ZZ-S02',
         @QuantityKg = 455.00, @OccurredAt = '2026-10-14T13:40:00',
         @ReasonCode = N'MEASUREMENT_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a cancelled step does not count for the limits)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection AS c
                 WHERE c.CorrectionId = (SELECT MAX(CorrectionId) FROM trace.MovementCorrection WHERE MovementId = @c1_pack)
                   AND c.Kind = N'REPLACE' AND c.StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S02')
                   AND c.QuantityKg = 455.00 AND c.OccurredAt = '2026-10-14T13:40:00' AND c.ReasonCode = N'MEASUREMENT_ERROR') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-C1' AND Status = N'PACKED' AND QuantityKg = 455.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'455.00 kg is accepted for the PACKING (now the last valid step) and the batch follows to 455.00 kg');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a cancelled step does not count for the limits)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- CancelMovement and ReplaceMovement: refused cases (tests 75 to 85) ---------- */

-- 75. CancelMovement: not the last valid movement
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_sort,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: not the last valid movement', N'50306', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: not the last valid movement', N'50306',
            CASE WHEN ERROR_NUMBER() <> 50306
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 76. CancelMovement: the RECEPTION cannot be cancelled
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C3', @MovementId = @c3_rec,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: the RECEPTION cannot be cancelled', N'50307', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: the RECEPTION cannot be cancelled', N'50307',
            CASE WHEN ERROR_NUMBER() <> 50307
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 77. CancelMovement: movement already cancelled
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C2', @MovementId = @c2_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: movement already cancelled', N'50305', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: movement already cancelled', N'50305',
            CASE WHEN ERROR_NUMBER() <> 50305
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 78. CancelMovement: unknown batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C-NOPE', @MovementId = @c1_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: unknown batch', N'50100', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: unknown batch', N'50100',
            CASE WHEN ERROR_NUMBER() <> 50100
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 79. CancelMovement: movement of another batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c3_rec,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: movement of another batch', N'50103', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: movement of another batch', N'50103',
            CASE WHEN ERROR_NUMBER() <> 50103
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 80. CancelMovement: unknown reason
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_pack,
         @ReasonCode = N'WRONG', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: unknown reason', N'50407', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: unknown reason', N'50407',
            CASE WHEN ERROR_NUMBER() <> 50407
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 81. CancelMovement: reason OTHER without a comment
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_pack,
         @ReasonCode = N'OTHER', @ReasonComment = N'   ',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: reason OTHER without a comment', N'50408', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: reason OTHER without a comment', N'50408',
            CASE WHEN ERROR_NUMBER() <> 50408
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 82. CancelMovement: comment of 501 characters
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = @comment501,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: comment of 501 characters', N'50409', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: comment of 501 characters', N'50409',
            CASE WHEN ERROR_NUMBER() <> 50409
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 83. CancelMovement: blank author name
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'   ';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: blank author name', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: blank author name', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 84. CancelMovement: author id too long
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-C1', @MovementId = @c1_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = @longAuthorId, @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: author id too long', N'50406', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: author id too long', N'50406',
            CASE WHEN ERROR_NUMBER() <> 50406
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 85. ReplaceMovement: movement already cancelled
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-C2', @MovementId = @c2_pack, @StationCode = N'ZZ-S02',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T13:40:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: movement already cancelled', N'50305', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: movement already cancelled', N'50305',
            CASE WHEN ERROR_NUMBER() <> 50305
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- GetBatch and the journal (tests 86 to 88) ---------- */

-- 86. GetBatch: a batch with replaced and cancelled movements (shape checked by the script, content BY EYE)
PRINT N'Test 86: GetBatch ZZ-C1. Check by eye the four result sets displayed just below:';
PRINT N'  1) one row: ZZ-C1, ZZ-F01, Test variety, 2026-10-14, 455.00, PACKED';
PRINT N'  2) four rows (MovementId order):';
PRINT N'     RECEPTION ZZ-S01 500.00 06:30, IsCancelled 0, CorrectionCount 0, original = same values';
PRINT N'     SORTING ZZ-S04 480.00 10:00, IsCancelled 0, CorrectionCount 2, original ZZ-S01 470.00 09:15';
PRINT N'     PACKING ZZ-S02 455.00 13:40, IsCancelled 0, CorrectionCount 1, original ZZ-S02 465.00 13:40';
PRINT N'     SHIPMENT ZZ-S03 460.00 17:05, IsCancelled 1, CorrectionCount 2, original ZZ-S03 465.00 17:05';
PRINT N'  3) five rows (CorrectionId order): SORTING REPLACE ZZ-S01 480.00 / SHIPMENT REPLACE 460.00 / SORTING REPLACE ZZ-S04 480.00 10:00 (OTHER) / SHIPMENT CANCEL 460.00 (OTHER) / PACKING REPLACE 455.00';
PRINT N'     each row has ReasonCode, ReasonComment, AuthorName Supervisor One and a CorrectedAt';
PRINT N'  4) no row (no correction of the sheet)';
BEGIN TRY
    EXEC trace.GetBatch @BatchCode = N'ZZ-C1'
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (MovementId BIGINT, MovementType NVARCHAR(20), StationCode NVARCHAR(20),
         QuantityKg DECIMAL(10,2), OccurredAt DATETIME2, AuthorName NVARCHAR(100),
         IsCancelled BIT, CorrectionCount INT, OriginalStationCode NVARCHAR(20),
         OriginalQuantityKg DECIMAL(10,2), OriginalOccurredAt DATETIME2),
        (CorrectionId BIGINT, MovementId BIGINT, Kind NVARCHAR(10), MovementType NVARCHAR(20),
         StationCode NVARCHAR(20), QuantityKg DECIMAL(10,2), OccurredAt DATETIME2,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2),
        (CorrectionId BIGINT, OldBatchCode NVARCHAR(30), NewBatchCode NVARCHAR(30),
         OldFarmCode NVARCHAR(20), NewFarmCode NVARCHAR(20), OldVariety NVARCHAR(50),
         NewVariety NVARCHAR(50), OldHarvestDate DATE, NewHarvestDate DATE,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: a batch with replaced and cancelled movements (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 4 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: a batch with replaced and cancelled movements (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 87. GetBatch: a batch with two cancelled movements and a new one (shape checked by the script, content BY EYE)
PRINT N'Test 87: GetBatch ZZ-C2. Check by eye the four result sets displayed just below:';
PRINT N'  1) one row: ZZ-C2, ZZ-F01, Test variety, 2026-10-14, 480.00, SORTED';
PRINT N'  2) four rows (MovementId order): RECEPTION 510.00 (CorrectionCount 1, original 500.00) / SORTING 470.00 (IsCancelled 1, CorrectionCount 1)';
PRINT N'     / PACKING 465.00 (IsCancelled 1, CorrectionCount 1) / SORTING ZZ-S01 480.00 2026-10-15 08:00 (IsCancelled 0, CorrectionCount 0, author Author Three)';
PRINT N'  3) three rows (CorrectionId order): RECEPTION REPLACE 510.00 / PACKING CANCEL 465.00 / SORTING CANCEL 470.00';
PRINT N'  4) no row (no correction of the sheet)';
BEGIN TRY
    EXEC trace.GetBatch @BatchCode = N'ZZ-C2'
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (MovementId BIGINT, MovementType NVARCHAR(20), StationCode NVARCHAR(20),
         QuantityKg DECIMAL(10,2), OccurredAt DATETIME2, AuthorName NVARCHAR(100),
         IsCancelled BIT, CorrectionCount INT, OriginalStationCode NVARCHAR(20),
         OriginalQuantityKg DECIMAL(10,2), OriginalOccurredAt DATETIME2),
        (CorrectionId BIGINT, MovementId BIGINT, Kind NVARCHAR(10), MovementType NVARCHAR(20),
         StationCode NVARCHAR(20), QuantityKg DECIMAL(10,2), OccurredAt DATETIME2,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2),
        (CorrectionId BIGINT, OldBatchCode NVARCHAR(30), NewBatchCode NVARCHAR(30),
         OldFarmCode NVARCHAR(20), NewFarmCode NVARCHAR(20), OldVariety NVARCHAR(50),
         NewVariety NVARCHAR(50), OldHarvestDate DATE, NewHarvestDate DATE,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: a batch with two cancelled movements and a new one (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 4 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: a batch with two cancelled movements and a new one (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 88. The journal trace.Movement was never changed by the corrections
INSERT @results (test_name, expected, outcome, detail)
VALUES (N'The journal trace.Movement was never changed by the corrections', N'(accepted)',
        CASE WHEN (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                   WHERE b.BatchCode IN (N'ZZ-C1', N'ZZ-C2', N'ZZ-C3', N'ZZ-C4')) = 12
              AND (SELECT SUM(m.QuantityKg) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                   WHERE b.BatchCode IN (N'ZZ-C1', N'ZZ-C2', N'ZZ-C3', N'ZZ-C4')) = 5750.00
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c1_sort
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND QuantityKg = 470.00 AND OccurredAt = '2026-10-14T09:15:00') = 1
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c1_ship
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S03')
                   AND QuantityKg = 465.00 AND OccurredAt = '2026-10-14T17:05:00') = 1
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c2_rec
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND QuantityKg = 500.00 AND OccurredAt = '2026-10-14T06:30:00') = 1
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @c3_rec
                   AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S01')
                   AND QuantityKg = 500.00 AND OccurredAt = '2026-10-14T06:30:00') = 1
             THEN N'Accepted as expected'
             ELSE N'ATTENTION: a movement of the journal was changed' END,
        N'12 movements, 5750.00 kg in all, and the first values of the corrected movements are still there');


/* ---------- Correction of the sheet of a batch (tests 89 to 122, lot 12b) ---------- */

-- Data of this part, inserted DIRECTLY in the tables (like the setup above). Each batch has its own role:
--   ZZ-D1 RECEIVED 500 (RECEPTION 06:30): its code, then several fields, are corrected; it takes back its
--         first code; its old codes are used by the refusals and by GetBatch.
--   ZZ-D2 SHIPPED 465 (RECEPTION 500, SORTING 470, PACKING 465, SHIPMENT 465): a shipped batch is corrected.
--   ZZ-D3 RECEIVED 500 (RECEPTION 06:30): harvest date, comment of 500 characters, change of case only,
--         and its RECEPTION moved to the harvest day.
--   ZZ-D4 RECEIVED 500 (RECEPTION 06:30): NEVER corrected; the refused calls use it, so its values are known.
--   ZZ-P5 (from the setup, no movement): a batch without reception.
-- The tests below depend on each other (they are run in this order, like 39 to 41).
DECLARE @d1_rec BIGINT, @d3_rec BIGINT, @d4_rec BIGINT;
DECLARE @id65    NVARCHAR(200) = REPLICATE(N'a', 65);
DECLARE @name101 NVARCHAR(200) = REPLICATE(N'n', 101);

BEGIN TRY
    INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
    SELECT v.BatchCode, f.FarmId, N'Test variety', '2026-10-14', v.QuantityKg, v.Status
    FROM (VALUES (N'ZZ-D1', 500.00, N'RECEIVED'),
                 (N'ZZ-D2', 465.00, N'SHIPPED'),
                 (N'ZZ-D3', 500.00, N'RECEIVED'),
                 (N'ZZ-D4', 500.00, N'RECEIVED')) AS v (BatchCode, QuantityKg, Status)
    CROSS JOIN trace.Farm AS f
    WHERE f.Code = N'ZZ-F01'
    ORDER BY v.BatchCode;

    INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt, AuthorId, AuthorName)
    SELECT b.BatchId, st.StationId, v.MovementType, v.QuantityKg, v.OccurredAt, N'orig-id', N'Original Author'
    FROM (VALUES (N'ZZ-D1', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-D2', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-D2', N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-D2', N'ZZ-S02', N'PACKING',   465.00, '2026-10-14T13:40:00'),
                 (N'ZZ-D2', N'ZZ-S03', N'SHIPMENT',  465.00, '2026-10-14T17:05:00'),
                 (N'ZZ-D3', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-D4', N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00')
         ) AS v (BatchCode, StationCode, MovementType, QuantityKg, OccurredAt)
    JOIN trace.Batch   AS b  ON b.BatchCode = v.BatchCode
    JOIN trace.Station AS st ON st.Code = v.StationCode
    ORDER BY v.BatchCode, v.OccurredAt;

    SELECT @d1_rec = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-D1' AND m.MovementType = N'RECEPTION';
    SELECT @d3_rec = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-D3' AND m.MovementType = N'RECEPTION';
    SELECT @d4_rec = MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-D4' AND m.MovementType = N'RECEPTION';
END TRY
BEGIN CATCH
    DECLARE @setup12b_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup of the batch correction tests failed, tests not run: %s', 16, 1, @setup12b_error);
    RETURN;
END CATCH;

/* ---------- CorrectBatch: accepted cases (tests 89 to 98) ---------- */

-- 89. CorrectBatch: control (code of a RECEIVED batch changed, old values kept)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D1', @NewBatchCode = N'ZZ-D1X', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (code of a RECEIVED batch changed, old values kept)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch
                 WHERE BatchCode = N'ZZ-D1X' AND Status = N'RECEIVED' AND QuantityKg = 500.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-D1') = 0
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                      WHERE b.BatchCode = N'ZZ-D1X' AND c.OldBatchCode = N'ZZ-D1' AND c.NewBatchCode = N'ZZ-D1X'
                        AND c.OldFarmId = c.NewFarmId AND c.OldVariety = N'Test variety' AND c.NewVariety = N'Test variety'
                        AND c.OldHarvestDate = '2026-10-14' AND c.NewHarvestDate = '2026-10-14'
                        AND c.ReasonCode = N'DATA_ENTRY_ERROR' AND c.ReasonComment = N''
                        AND c.AuthorId = N'sup-id-1' AND c.AuthorName = N'Supervisor One'
                        AND c.CorrectedAt IS NOT NULL) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-D1X') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The batch now has the code ZZ-D1X; one row keeps ZZ-D1 and ZZ-D1X, the author and the reason; the movement is untouched');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (code of a RECEIVED batch changed, old values kept)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 90. CorrectBatch: control (several fields at once, reason OTHER with a comment)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D1X', @NewBatchCode = N'ZZ-D1X', @FarmCode = N'ZZ-F02',
         @Variety = N'Other variety', @HarvestDate = '2026-10-13',
         @ReasonCode = N'OTHER', @ReasonComment = N'Sheet written for the wrong farm',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (several fields at once, reason OTHER with a comment)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch AS b JOIN trace.Farm AS f ON f.FarmId = b.FarmId
                 WHERE b.BatchCode = N'ZZ-D1X' AND f.Code = N'ZZ-F02' AND b.Variety = N'Other variety'
                   AND b.HarvestDate = '2026-10-13' AND b.Status = N'RECEIVED' AND b.QuantityKg = 500.00) = 1
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c
                      JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                      JOIN trace.Farm AS fo ON fo.FarmId = c.OldFarmId
                      JOIN trace.Farm AS fn ON fn.FarmId = c.NewFarmId
                      WHERE b.BatchCode = N'ZZ-D1X' AND c.OldBatchCode = N'ZZ-D1X' AND c.NewBatchCode = N'ZZ-D1X'
                        AND fo.Code = N'ZZ-F01' AND fn.Code = N'ZZ-F02'
                        AND c.OldVariety = N'Test variety' AND c.NewVariety = N'Other variety'
                        AND c.OldHarvestDate = '2026-10-14' AND c.NewHarvestDate = '2026-10-13'
                        AND c.ReasonCode = N'OTHER' AND c.ReasonComment = N'Sheet written for the wrong farm') = 1
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D1X') = 2
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'Farm, variety and harvest date changed together; the second row keeps the old values of all three fields');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (several fields at once, reason OTHER with a comment)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 91. CorrectBatch: control (a SHIPPED batch can be corrected, status and quantity unchanged)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D2', @NewBatchCode = N'ZZ-D2', @FarmCode = N'ZZ-F01',
         @Variety = N'Corrected variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = N'Variety typed wrongly',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (a SHIPPED batch can be corrected, status and quantity unchanged)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch
                 WHERE BatchCode = N'ZZ-D2' AND Variety = N'Corrected variety'
                   AND Status = N'SHIPPED' AND QuantityKg = 465.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-D2') = 4
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D2') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The SHIPPED batch keeps its status, its 465.00 kg and its 4 movements; one correction row');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (a SHIPPED batch can be corrected, status and quantity unchanged)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 92. CorrectBatch: control (reason code in lower case stored in capitals, earlier harvest date)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D3', @NewBatchCode = N'ZZ-D3', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-13',
         @ReasonCode = N'data_entry_error', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (reason code in lower case stored in capitals, earlier harvest date)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D3'
                   AND c.ReasonCode COLLATE Latin1_General_BIN2 = N'DATA_ENTRY_ERROR' COLLATE Latin1_General_BIN2
                   AND c.OldHarvestDate = '2026-10-14' AND c.NewHarvestDate = '2026-10-13') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The reason code is stored in capitals (binary comparison); harvest date moved from 2026-10-14 to 2026-10-13');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (reason code in lower case stored in capitals, earlier harvest date)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 93. CorrectBatch: control (harvest date equal to the reception day is accepted)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D3', @NewBatchCode = N'ZZ-D3', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (harvest date equal to the reception day is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-D3' AND HarvestDate = '2026-10-14') = 1
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D3') = 2
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The reception is on 2026-10-14 at 06:30: a harvest on the same day is accepted');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (harvest date equal to the reception day is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 94. CorrectBatch: control (a comment of exactly 500 characters)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D3', @NewBatchCode = N'ZZ-D3', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety 2', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = @comment500,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (a comment of exactly 500 characters)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D3' AND LEN(c.ReasonComment) = 500) = 1
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D3') = 3
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'A comment of 500 characters is stored whole');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (a comment of exactly 500 characters)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 95. CorrectBatch: control (batch without reception: the harvest date rule is not applied)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-P5', @NewBatchCode = N'ZZ-P5', @FarmCode = N'ZZ-F03',
         @Variety = N'Test variety', @HarvestDate = '2030-01-01',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (batch without reception: the harvest date rule is not applied)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-P5' AND HarvestDate = '2030-01-01') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                      WHERE b.BatchCode = N'ZZ-P5') = 0
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-P5') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'ZZ-P5 has no movement, so there is no reception to compare with: the correction is accepted');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (batch without reception: the harvest date rule is not applied)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 96. CorrectBatch: control (a batch can take back its own old code)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D1X', @NewBatchCode = N'ZZ-D1', @FarmCode = N'ZZ-F02',
         @Variety = N'Other variety', @HarvestDate = '2026-10-13',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (a batch can take back its own old code)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-D1' AND Variety = N'Other variety') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-D1X') = 0
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D1') = 3
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'ZZ-D1 is again the code of the batch, three corrections are kept; ZZ-D1X is now an old code');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (a batch can take back its own old code)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 97. CorrectBatch: control (change of case only is a change)
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D3', @NewBatchCode = N'zz-d3', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety 2', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (change of case only is a change)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch
                 WHERE BatchCode COLLATE Latin1_General_BIN2 = N'zz-d3' COLLATE Latin1_General_BIN2) = 1
                 AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                 WHERE b.BatchCode = N'ZZ-D3') = 4
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The code is stored as zz-d3 (binary comparison); a fourth correction row');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: control (change of case only is a change)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 98. ReplaceMovement: control (a reception moved to the harvest day is accepted)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-D3', @MovementId = @d3_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 500.00, @OccurredAt = '2026-10-14T00:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a reception moved to the harvest day is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection
                 WHERE MovementId = @d3_rec AND Kind = N'REPLACE' AND OccurredAt = '2026-10-14T00:00:00') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The harvest date of ZZ-D3 is 2026-10-14: the same day is accepted');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (a reception moved to the harvest day is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- CorrectBatch: refused cases (tests 99 to 114) ---------- */

-- 99. CorrectBatch: author id NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = NULL, @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: author id NULL', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: author id NULL', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 100. CorrectBatch: blank author name
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'   ';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: blank author name', N'50405', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: blank author name', N'50405',
            CASE WHEN ERROR_NUMBER() <> 50405
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 101. CorrectBatch: author id too long (65 characters)
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = @id65, @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: author id too long (65 characters)', N'50406', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: author id too long (65 characters)', N'50406',
            CASE WHEN ERROR_NUMBER() <> 50406
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 102. CorrectBatch: author name too long (101 characters)
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = @name101;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: author name too long (101 characters)', N'50406', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: author name too long (101 characters)', N'50406',
            CASE WHEN ERROR_NUMBER() <> 50406
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 103. CorrectBatch: reason not accepted for a batch (MEASUREMENT_ERROR)
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'MEASUREMENT_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: reason not accepted for a batch (MEASUREMENT_ERROR)', N'50407', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: reason not accepted for a batch (MEASUREMENT_ERROR)', N'50407',
            CASE WHEN ERROR_NUMBER() <> 50407
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 104. CorrectBatch: reason NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = NULL, @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: reason NULL', N'50407', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: reason NULL', N'50407',
            CASE WHEN ERROR_NUMBER() <> 50407
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 105. CorrectBatch: reason OTHER without a comment
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'OTHER', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: reason OTHER without a comment', N'50408', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: reason OTHER without a comment', N'50408',
            CASE WHEN ERROR_NUMBER() <> 50408
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 106. CorrectBatch: comment of 501 characters
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = @comment501,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: comment of 501 characters', N'50409', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: comment of 501 characters', N'50409',
            CASE WHEN ERROR_NUMBER() <> 50409
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 107. CorrectBatch: blank new code
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'   ', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: blank new code', N'50400', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: blank new code', N'50400',
            CASE WHEN ERROR_NUMBER() <> 50400
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 108. CorrectBatch: unknown batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D-NOPE', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: unknown batch', N'50100', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: unknown batch', N'50100',
            CASE WHEN ERROR_NUMBER() <> 50100
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 109. CorrectBatch: old code used to correct (the batch is found by its current code)
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D1X', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: old code used to correct (the batch is found by its current code)', N'50104', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: old code used to correct (the batch is found by its current code)', N'50104',
            CASE WHEN ERROR_NUMBER() <> 50104
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 110. CorrectBatch: unknown farm
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F-NOPE',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: unknown farm', N'50101', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: unknown farm', N'50101',
            CASE WHEN ERROR_NUMBER() <> 50101
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 111. CorrectBatch: new code is the current code of another batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D1', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: new code is the current code of another batch', N'50202', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: new code is the current code of another batch', N'50202',
            CASE WHEN ERROR_NUMBER() <> 50202
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 112. CorrectBatch: new code is the old code of another batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D1X', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: new code is the old code of another batch', N'50203', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: new code is the old code of another batch', N'50203',
            CASE WHEN ERROR_NUMBER() <> 50203
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 113. CorrectBatch: harvest date after the reception day
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4N', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-15',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: harvest date after the reception day', N'50309', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: harvest date after the reception day', N'50309',
            CASE WHEN ERROR_NUMBER() <> 50309
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 114. CorrectBatch: same values as the current ones
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CorrectBatch
         @BatchCode = N'ZZ-D4', @NewBatchCode = N'ZZ-D4', @FarmCode = N'ZZ-F01',
         @Variety = N'Test variety', @HarvestDate = '2026-10-14',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: same values as the current ones', N'50308', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CorrectBatch: same values as the current ones', N'50308',
            CASE WHEN ERROR_NUMBER() <> 50308
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- Old codes and the harvest date in the other procedures (tests 115 to 121) ---------- */

-- 115. AddMovement: old code of a corrected batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-D1X', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:15:00',
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: old code of a corrected batch', N'50104', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: old code of a corrected batch', N'50104',
            CASE WHEN ERROR_NUMBER() <> 50104
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 116. ReplaceMovement: old code of a corrected batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-D1X', @MovementId = @d1_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 495.00, @OccurredAt = '2026-10-14T06:30:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: old code of a corrected batch', N'50104', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: old code of a corrected batch', N'50104',
            CASE WHEN ERROR_NUMBER() <> 50104
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 117. CancelMovement: old code of a corrected batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-D1X', @MovementId = @d1_rec,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: old code of a corrected batch', N'50104', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: old code of a corrected batch', N'50104',
            CASE WHEN ERROR_NUMBER() <> 50104
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 118. CreateBatch: code that is the old code of another batch
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-D1X', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: code that is the old code of another batch', N'50203', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: code that is the old code of another batch', N'50203',
            CASE WHEN ERROR_NUMBER() <> 50203
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 119. CreateBatch: harvest date after the reception day
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-B-X50', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-15', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: harvest date after the reception day', N'50309', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: harvest date after the reception day', N'50309',
            CASE WHEN ERROR_NUMBER() <> 50309
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 120. ReplaceMovement: reception moved before the harvest day
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-D4', @MovementId = @d4_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 500.00, @OccurredAt = '2026-10-13T23:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reception moved before the harvest day', N'50309', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reception moved before the harvest day', N'50309',
            CASE WHEN ERROR_NUMBER() <> 50309
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 121. GetBatch: read by an old code, with the corrections of the sheet (shape checked by the script, content BY EYE)
PRINT N'Test 121: GetBatch ZZ-D1X (an OLD code of the batch ZZ-D1). Check by eye the four result sets displayed just below:';
PRINT N'  1) one row, with the CURRENT code: ZZ-D1, ZZ-F02, Other variety, 2026-10-13, 500.00, RECEIVED';
PRINT N'  2) one row: RECEPTION ZZ-S01 500.00 2026-10-14 06:30, AuthorName Original Author, IsCancelled 0, CorrectionCount 0';
PRINT N'  3) no row (no correction of a movement)';
PRINT N'  4) three rows (CorrectionId order), each with AuthorName Supervisor One and a CorrectedAt:';
PRINT N'     ZZ-D1 to ZZ-D1X, same farm ZZ-F01, same variety, same date, DATA_ENTRY_ERROR, no comment';
PRINT N'     ZZ-D1X to ZZ-D1X, ZZ-F01 to ZZ-F02, Test variety to Other variety, 2026-10-14 to 2026-10-13, OTHER, Sheet written for the wrong farm';
PRINT N'     ZZ-D1X to ZZ-D1, ZZ-F02 both sides, Other variety both sides, 2026-10-13 both sides, DATA_ENTRY_ERROR, no comment';
BEGIN TRY
    EXEC trace.GetBatch @BatchCode = N'ZZ-D1X'
    WITH RESULT SETS
    (
        (BatchCode NVARCHAR(30), FarmCode NVARCHAR(20), Variety NVARCHAR(50),
         HarvestDate DATE, QuantityKg DECIMAL(10,2), Status NVARCHAR(20)),
        (MovementId BIGINT, MovementType NVARCHAR(20), StationCode NVARCHAR(20),
         QuantityKg DECIMAL(10,2), OccurredAt DATETIME2, AuthorName NVARCHAR(100),
         IsCancelled BIT, CorrectionCount INT, OriginalStationCode NVARCHAR(20),
         OriginalQuantityKg DECIMAL(10,2), OriginalOccurredAt DATETIME2),
        (CorrectionId BIGINT, MovementId BIGINT, Kind NVARCHAR(10), MovementType NVARCHAR(20),
         StationCode NVARCHAR(20), QuantityKg DECIMAL(10,2), OccurredAt DATETIME2,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2),
        (CorrectionId BIGINT, OldBatchCode NVARCHAR(30), NewBatchCode NVARCHAR(30),
         OldFarmCode NVARCHAR(20), NewFarmCode NVARCHAR(20), OldVariety NVARCHAR(50),
         NewVariety NVARCHAR(50), OldHarvestDate DATE, NewHarvestDate DATE,
         ReasonCode NVARCHAR(20), ReasonComment NVARCHAR(500), AuthorName NVARCHAR(100),
         CorrectedAt DATETIME2)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: read by an old code, with the sheet corrections (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 4 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetBatch: read by an old code, with the sheet corrections (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 122. The journal trace.Movement was never changed by the sheet corrections, and refused calls left no row
INSERT @results (test_name, expected, outcome, detail)
VALUES (N'The journal was not changed by the sheet corrections; refused calls left no row', N'(accepted)',
        CASE WHEN (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                   WHERE b.BatchCode IN (N'ZZ-D1', N'ZZ-D2', N'ZZ-D3', N'ZZ-D4')) = 7
              AND (SELECT SUM(m.QuantityKg) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                   WHERE b.BatchCode IN (N'ZZ-D1', N'ZZ-D2', N'ZZ-D3', N'ZZ-D4')) = 3400.00
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @d1_rec
                   AND QuantityKg = 500.00 AND OccurredAt = '2026-10-14T06:30:00') = 1
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @d3_rec
                   AND QuantityKg = 500.00 AND OccurredAt = '2026-10-14T06:30:00') = 1
              AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @d4_rec
                   AND QuantityKg = 500.00 AND OccurredAt = '2026-10-14T06:30:00') = 1
              AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                   WHERE b.BatchCode LIKE N'ZZ-%') = 9
              AND (SELECT COUNT(*) FROM trace.BatchCorrection AS c JOIN trace.Batch AS b ON b.BatchId = c.BatchId
                   WHERE b.BatchCode = N'ZZ-D4') = 0
             THEN N'Accepted as expected'
             ELSE N'ATTENTION: a movement of the journal was changed, or a refused call left a row' END,
        N'7 movements, 3400.00 kg, first values still there; 9 correction rows (ZZ-D1 3, ZZ-D2 1, ZZ-D3 4, ZZ-P5 1) and none for ZZ-D4');



/* ---------- The time of the movements (tests 123 to 150, lot 12c) ---------- */

-- Data of this part, inserted DIRECTLY in the tables (like the setup above), on farm ZZ-F01 (harvest
-- 2026-10-14). The movements of a batch are inserted in the order of their steps (Seq), so that their
-- MovementId follows the steps, even for ZZ-T4 whose times are already out of order.
--   ZZ-T1 RECEIVED 500 (RECEPTION 06:30): refused additions, never changed.
--   ZZ-T3 PACKED 465 (RECEPTION 06:30, SORTING 09:15, PACKING 13:40): refused and accepted corrections.
--   ZZ-T4 SORTED 470 (RECEPTION 10:00, SORTING 09:00): a batch already out of order (data from before lot
--         12c): a correction that does not change the time is accepted, one that changes it is checked.
--   ZZ-T6, ZZ-T7 RECEIVED 500 (RECEPTION 06:30): additions accepted.
--   ZZ-T8 SORTED 470 (RECEPTION 06:30, SORTING 09:15): the time of the sorting is corrected, then an
--         addition is checked against the corrected time.
--   ZZ-T9 PACKED 465 (RECEPTION 06:30, SORTING 09:15, PACKING 13:40): the packing is cancelled, then an
--         addition is checked without the cancelled step.
--   ZZ-T5 is created by test 124. The tests below depend on each other (run in this order).
-- The times "in the future" are computed from the clock of the server when the test runs: 6 minutes
-- (refused) and 4 minutes (accepted). The limit of exactly 5 minutes is not tested, the clock moves.
DECLARE @t3_rec BIGINT, @t3_sort BIGINT, @t3_pack BIGINT, @t4_sort BIGINT, @t8_sort BIGINT, @t9_pack BIGINT;
DECLARE @t12c DATETIME2;

BEGIN TRY
    INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
    SELECT v.BatchCode, f.FarmId, N'Test variety', '2026-10-14', v.QuantityKg, v.Status
    FROM (VALUES (N'ZZ-T1', 500.00, N'RECEIVED'),
                 (N'ZZ-T3', 465.00, N'PACKED'),
                 (N'ZZ-T4', 470.00, N'SORTED'),
                 (N'ZZ-T6', 500.00, N'RECEIVED'),
                 (N'ZZ-T7', 500.00, N'RECEIVED'),
                 (N'ZZ-T8', 470.00, N'SORTED'),
                 (N'ZZ-T9', 465.00, N'PACKED')) AS v (BatchCode, QuantityKg, Status)
    CROSS JOIN trace.Farm AS f
    WHERE f.Code = N'ZZ-F01'
    ORDER BY v.BatchCode;

    INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt, AuthorId, AuthorName)
    SELECT b.BatchId, st.StationId, v.MovementType, v.QuantityKg, v.OccurredAt, N'orig-id', N'Original Author'
    FROM (VALUES (N'ZZ-T1', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-T3', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-T3', 2, N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-T3', 3, N'ZZ-S02', N'PACKING',   465.00, '2026-10-14T13:40:00'),
                 (N'ZZ-T4', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T10:00:00'),
                 (N'ZZ-T4', 2, N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:00:00'),
                 (N'ZZ-T6', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-T7', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-T8', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-T8', 2, N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-T9', 1, N'ZZ-S01', N'RECEPTION', 500.00, '2026-10-14T06:30:00'),
                 (N'ZZ-T9', 2, N'ZZ-S01', N'SORTING',   470.00, '2026-10-14T09:15:00'),
                 (N'ZZ-T9', 3, N'ZZ-S02', N'PACKING',   465.00, '2026-10-14T13:40:00')
         ) AS v (BatchCode, Seq, StationCode, MovementType, QuantityKg, OccurredAt)
    JOIN trace.Batch   AS b  ON b.BatchCode = v.BatchCode
    JOIN trace.Station AS st ON st.Code = v.StationCode
    ORDER BY v.BatchCode, v.Seq;

    SELECT @t3_rec  = m.MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-T3' AND m.MovementType = N'RECEPTION';
    SELECT @t3_sort = m.MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-T3' AND m.MovementType = N'SORTING';
    SELECT @t3_pack = m.MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-T3' AND m.MovementType = N'PACKING';
    SELECT @t4_sort = m.MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-T4' AND m.MovementType = N'SORTING';
    SELECT @t8_sort = m.MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-T8' AND m.MovementType = N'SORTING';
    SELECT @t9_pack = m.MovementId FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId WHERE b.BatchCode = N'ZZ-T9' AND m.MovementType = N'PACKING';
END TRY
BEGIN CATCH
    DECLARE @setup12c_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup of the time tests failed, tests not run: %s', 16, 1, @setup12c_error);
    RETURN;
END CATCH;

-- 123. CreateBatch: reception time more than 5 minutes in the future
SET @t12c = DATEADD(MINUTE, 6, SYSUTCDATETIME());
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-T5X', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = @t12c,
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: reception time more than 5 minutes in the future', N'50310', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: reception time more than 5 minutes in the future', N'50310',
            CASE WHEN ERROR_NUMBER() <> 50310
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 124. CreateBatch: control (reception time 4 minutes in the future is accepted)
SET @t12c = DATEADD(MINUTE, 4, SYSUTCDATETIME());
BEGIN TRY
    EXEC trace.CreateBatch
         @BatchCode = N'ZZ-T5', @FarmCode = N'ZZ-F01', @Variety = N'Cherry',
         @HarvestDate = '2026-10-14', @QuantityKg = 500.00, @StationCode = N'ZZ-S01',
         @OccurredAt = @t12c,
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: control (reception time 4 minutes in the future is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                  WHERE b.BatchCode = N'ZZ-T5' AND m.MovementType = N'RECEPTION' AND m.OccurredAt = @t12c) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The batch is created with its reception 4 minutes after the clock of the server');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CreateBatch: control (reception time 4 minutes in the future is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 125. AddMovement: time more than 5 minutes in the future
SET @t12c = DATEADD(MINUTE, 6, SYSUTCDATETIME());
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T1', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = @t12c,
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time more than 5 minutes in the future', N'50310', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time more than 5 minutes in the future', N'50310',
            CASE WHEN ERROR_NUMBER() <> 50310
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 126. AddMovement: time equal to the previous step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T1', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T06:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time equal to the previous step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time equal to the previous step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 127. AddMovement: time before the previous step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T1', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T06:00:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time before the previous step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time before the previous step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 128. AddMovement: control (time 4 minutes in the future is accepted)
SET @t12c = DATEADD(MINUTE, 4, SYSUTCDATETIME());
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T6', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = @t12c,
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (time 4 minutes in the future is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-T6' AND Status = N'SORTED' AND QuantityKg = 470.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                  WHERE b.BatchCode = N'ZZ-T6') = 2
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The sorting is added 4 minutes after the clock of the server; the batch is SORTED');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (time 4 minutes in the future is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 129. AddMovement: control (time one second after the previous step is accepted)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T7', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T06:30:01',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (time one second after the previous step is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-T7' AND Status = N'SORTED' AND QuantityKg = 470.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                  WHERE b.BatchCode = N'ZZ-T7' AND m.MovementType = N'SORTING' AND m.OccurredAt = '2026-10-14T06:30:01') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The sorting at 06:30:01 is accepted after the reception at 06:30:00');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (time one second after the previous step is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 130. ReplaceMovement: time more than 5 minutes in the future
SET @t12c = DATEADD(MINUTE, 6, SYSUTCDATETIME());
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_pack, @StationCode = N'ZZ-S02',
         @QuantityKg = 465.00, @OccurredAt = @t12c,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time more than 5 minutes in the future', N'50310', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time more than 5 minutes in the future', N'50310',
            CASE WHEN ERROR_NUMBER() <> 50310
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 131. ReplaceMovement: time equal to the previous step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T06:30:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time equal to the previous step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time equal to the previous step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 132. ReplaceMovement: time before the previous step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T06:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time before the previous step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time before the previous step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 133. ReplaceMovement: time equal to the next step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T13:40:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time equal to the next step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time equal to the next step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 134. ReplaceMovement: time after the next step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T14:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time after the next step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: time after the next step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 135. ReplaceMovement: reception time equal to the next step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 500.00, @OccurredAt = '2026-10-14T09:15:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reception time equal to the next step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reception time equal to the next step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 136. ReplaceMovement: reception time after the next step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 500.00, @OccurredAt = '2026-10-14T10:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reception time after the next step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: reception time after the next step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 137. ReplaceMovement: new time still out of order in a batch already out of order
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T4', @MovementId = @t4_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T09:30:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: new time still out of order in a batch already out of order', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: new time still out of order in a batch already out of order', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 138. ReplaceMovement: control (time between the two neighbours)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T07:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (time between the two neighbours)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t3_sort AND Kind = N'REPLACE' AND OccurredAt = '2026-10-14T07:00:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Movement WHERE MovementId = @t3_sort AND OccurredAt = '2026-10-14T09:15:00') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'A correction row holds 07:00; the first time 09:15 is still in the journal');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (time between the two neighbours)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 139. ReplaceMovement: control (reception: only the next step counts)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_rec, @StationCode = N'ZZ-S01',
         @QuantityKg = 500.00, @OccurredAt = '2026-10-14T06:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (reception: only the next step counts)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t3_rec AND Kind = N'REPLACE' AND OccurredAt = '2026-10-14T06:00:00') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The reception moves to 06:00, before its first time, and stays before the sorting at 07:00');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (reception: only the next step counts)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 140. ReplaceMovement: control (last step: 4 minutes in the future is accepted)
SET @t12c = DATEADD(MINUTE, 4, SYSUTCDATETIME());
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T3', @MovementId = @t3_pack, @StationCode = N'ZZ-S02',
         @QuantityKg = 465.00, @OccurredAt = @t12c,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (last step: 4 minutes in the future is accepted)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t3_pack AND Kind = N'REPLACE' AND OccurredAt = @t12c) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The packing moves to 4 minutes after the clock of the server, after the sorting at 07:00');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (last step: 4 minutes in the future is accepted)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 141. ReplaceMovement: control (quantity only, in a batch already out of order)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T4', @MovementId = @t4_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (quantity only, in a batch already out of order)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t4_sort AND Kind = N'REPLACE' AND QuantityKg = 460.00 AND OccurredAt = '2026-10-14T09:00:00') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-T4' AND Status = N'SORTED' AND QuantityKg = 460.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The time 09:00 is not changed, so it is not checked: the quantity is corrected, the old disorder stays');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (quantity only, in a batch already out of order)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 142. ReplaceMovement: control (the sorting of ZZ-T8 moves to 12:00)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T8', @MovementId = @t8_sort, @StationCode = N'ZZ-S01',
         @QuantityKg = 470.00, @OccurredAt = '2026-10-14T12:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (the sorting of ZZ-T8 moves to 12:00)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t8_sort AND Kind = N'REPLACE' AND OccurredAt = '2026-10-14T12:00:00') = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The valid time of the sorting is now 12:00 (first time 09:15)');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (the sorting of ZZ-T8 moves to 12:00)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 143. AddMovement: time before the corrected time of the previous step
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T8', @StationCode = N'ZZ-S02', @MovementType = N'PACKING',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T11:00:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time before the corrected time of the previous step', N'50311', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time before the corrected time of the previous step', N'50311',
            CASE WHEN ERROR_NUMBER() <> 50311
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 144. AddMovement: control (time after the corrected time of the previous step)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T8', @StationCode = N'ZZ-S02', @MovementType = N'PACKING',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T12:30:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (time after the corrected time of the previous step)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-T8' AND Status = N'PACKED' AND QuantityKg = 465.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                  WHERE b.BatchCode = N'ZZ-T8') = 3
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The packing at 12:30 is accepted: the previous valid time is 12:00, not 09:15');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (time after the corrected time of the previous step)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 145. CancelMovement: control (the packing of ZZ-T9 is cancelled)
BEGIN TRY
    EXEC trace.CancelMovement
         @BatchCode = N'ZZ-T9', @MovementId = @t9_pack,
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (the packing of ZZ-T9 is cancelled)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t9_pack AND Kind = N'CANCEL') = 1
                 AND (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-T9' AND Status = N'SORTED' AND QuantityKg = 470.00) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The packing at 13:40 is cancelled; the batch goes back to SORTED');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'CancelMovement: control (the packing of ZZ-T9 is cancelled)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 146. AddMovement: control (a cancelled step does not count for the order)
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T9', @StationCode = N'ZZ-S02', @MovementType = N'PACKING',
         @QuantityKg = 465.00, @OccurredAt = '2026-10-14T10:00:00',
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (a cancelled step does not count for the order)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.Batch WHERE BatchCode = N'ZZ-T9' AND Status = N'PACKED' AND QuantityKg = 465.00) = 1
                 AND (SELECT COUNT(*) FROM trace.Movement AS m JOIN trace.Batch AS b ON b.BatchId = m.BatchId
                  WHERE b.BatchCode = N'ZZ-T9') = 4
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The new packing at 10:00 is accepted: the cancelled packing at 13:40 is ignored');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: control (a cancelled step does not count for the order)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 147. The first times of the journal were never changed by the corrections of the time
INSERT @results (test_name, expected, outcome, detail)
VALUES (N'The first times of the journal were not changed by the corrections of the time', N'(accepted)',
        CASE WHEN (SELECT COUNT(*) FROM trace.Movement AS m
                   JOIN (VALUES (@t3_rec,  '2026-10-14T06:30:00'), (@t3_sort, '2026-10-14T09:15:00'),
                                (@t3_pack, '2026-10-14T13:40:00'), (@t4_sort, '2026-10-14T09:00:00'),
                                (@t8_sort, '2026-10-14T09:15:00'), (@t9_pack, '2026-10-14T13:40:00'))
                        AS v (MovementId, OccurredAt)
                     ON v.MovementId = m.MovementId AND m.OccurredAt = v.OccurredAt) = 6
             THEN N'Accepted as expected'
             ELSE N'ATTENTION: a first time of the journal was changed' END,
        N'6 movements that were corrected or cancelled still hold their first time in trace.Movement');


-- Data of tests 148 to 150, inserted DIRECTLY (like the setup above):
--   ZZ-T10 RECEIVED 500: its RECEPTION was written 2 hours after the clock of the server, like a time in
--          the future that was accepted before lot 12c. It is used by test 148 only.
BEGIN TRY
    INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
    SELECT N'ZZ-T10', f.FarmId, N'Test variety', '2026-10-14', 500.00, N'RECEIVED'
    FROM trace.Farm AS f
    WHERE f.Code = N'ZZ-F01';

    INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt, AuthorId, AuthorName)
    SELECT b.BatchId, st.StationId, N'RECEPTION', 500.00, DATEADD(HOUR, 2, SYSUTCDATETIME()),
           N'orig-id', N'Original Author'
    FROM trace.Batch AS b
    CROSS JOIN trace.Station AS st
    WHERE b.BatchCode = N'ZZ-T10' AND st.Code = N'ZZ-S01';
END TRY
BEGIN CATCH
    DECLARE @setup12c2_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup of the tests 148 to 150 failed, tests not run: %s', 16, 1, @setup12c2_error);
    RETURN;
END CATCH;

-- 148. AddMovement: time in the future and before the previous step (the future first)
SET @t12c = DATEADD(HOUR, 1, SYSUTCDATETIME());
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-T10', @StationCode = N'ZZ-S01', @MovementType = N'SORTING',
         @QuantityKg = 470.00, @OccurredAt = @t12c,
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time in the future and before the previous step (the future first)', N'50310', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: time in the future and before the previous step (the future first)', N'50310',
            CASE WHEN ERROR_NUMBER() <> 50310
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 149. AddMovement: batch already SHIPPED and time in the future (50300 comes first)
SET @t12c = DATEADD(MINUTE, 6, SYSUTCDATETIME());
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.AddMovement
         @BatchCode = N'ZZ-B-SHIP', @StationCode = N'ZZ-S03', @MovementType = N'SHIPMENT',
         @QuantityKg = 465.00, @OccurredAt = @t12c,
         @AuthorId = N'test-author-id', @AuthorName = N'Test Author';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: batch already SHIPPED and time in the future (50300 comes first)', N'50300', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'AddMovement: batch already SHIPPED and time in the future (50300 comes first)', N'50300',
            CASE WHEN ERROR_NUMBER() <> 50300
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 150. ReplaceMovement: control (station only, time unchanged, batch already out of order)
BEGIN TRY
    EXEC trace.ReplaceMovement
         @BatchCode = N'ZZ-T4', @MovementId = @t4_sort, @StationCode = N'ZZ-S04',
         @QuantityKg = 460.00, @OccurredAt = '2026-10-14T09:00:00',
         @ReasonCode = N'DATA_ENTRY_ERROR', @ReasonComment = NULL,
         @AuthorId = N'sup-id-1', @AuthorName = N'Supervisor One';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (station only, time unchanged, batch already out of order)', N'(accepted)',
            CASE WHEN (SELECT COUNT(*) FROM trace.MovementCorrection WHERE MovementId = @t4_sort AND Kind = N'REPLACE' AND OccurredAt = '2026-10-14T09:00:00' AND QuantityKg = 460.00
                 AND StationId = (SELECT StationId FROM trace.Station WHERE Code = N'ZZ-S04')) = 1
                 THEN N'Accepted as expected'
                 ELSE N'ATTENTION: accepted, but the effect is not the expected one' END,
            N'The station changes, the time 09:00 does not: it is not checked, so the old disorder does not block it');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ReplaceMovement: control (station only, time unchanged, batch already out of order)', N'(accepted)',
            CONCAT(N'ATTENTION: refused, error ', ERROR_NUMBER()),
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

-- Verdict (lot 9): raise an error when a test is not OK, so that a run with sqlcmd -b fails.
-- A test "to check by eye" counts as passed here: only its shape is checked, not its content.
DECLARE @verdict_total     INT = (SELECT COUNT(*) FROM @results);
DECLARE @verdict_attention INT = (SELECT COUNT(*) FROM @results WHERE outcome LIKE N'ATTENTION%');
DECLARE @verdict_passed    INT = (SELECT COUNT(*) FROM @results
                                  WHERE outcome IN (N'Refused as expected', N'Accepted as expected')
                                     OR outcome LIKE N'To check by eye%');
IF @verdict_total = 0 OR @verdict_attention > 0 OR @verdict_passed <> @verdict_total
    RAISERROR(N'006 verdict: FAILED (tests_total = %d, passed or to check by eye = %d, marked ATTENTION = %d).',
              16, 1, @verdict_total, @verdict_passed, @verdict_attention);
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO
