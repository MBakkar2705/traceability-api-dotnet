/*
  012_check_list_procedures.sql
  Tests the 3 stored procedures of 011: trace.ListFarms, trace.ListStations and
  trace.GetStation (contract: docs/procedures.md). 16 tests.

  - Runs ONLY on TraceabilityTest. The name is written in the script, so SQLCMD
    mode is not needed. On any other database the script refuses to run.
  - Run 001, 002, 004, 005 and 011 on TraceabilityTest first.
  - Replayable: it first removes the test rows of a previous run (codes that start
    with ZY-), with DELETE ... WHERE only. Other rows are never touched. The prefix
    is ZY- and not ZZ-, so the rows of 006 (ZZ-) stay as they are.
  - Nothing is rolled back: the test rows stay in TraceabilityTest until the next run.
  - A refusal test is OK if: the error number is the expected one, the data is
    unchanged (dbo.TestFingerprint), and no transaction is left open.
  - A procedure with 2 result sets cannot be captured by INSERT ... EXEC. So the
    content tests (1, 2, 7, 8, 13, 14) check the NUMBER and the SHAPE of the result
    sets (WITH RESULT SETS); the VALUES are checked BY EYE. For each of them the
    script first displays what to expect, in the grid, then the procedure results.
  - Tests 1 and 7 show page 1 with a page size of 1000: valid while TraceabilityTest
    has at most 1000 farms and 1000 stations.
  - dbo.TestFingerprint() has the same definition as in 006: whichever of the two
    scripts runs first creates it.
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

-- Safety 2: the 3 procedures of 011 must exist.
IF (SELECT COUNT(*) FROM sys.procedures
    WHERE schema_id = SCHEMA_ID(N'trace')
      AND name IN (N'ListFarms', N'ListStations', N'GetStation')) <> 3
BEGIN
    RAISERROR(N'The 3 procedures ListFarms, ListStations and GetStation are missing. Run 011 first. Nothing was done.', 16, 1);
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
-- keys, and only the rows whose code starts with ZY- (test data of this script).
DELETE FROM trace.StationCapability
WHERE StationId IN (SELECT StationId FROM trace.Station WHERE Code LIKE N'ZY-%');

DELETE FROM trace.Station
WHERE Code LIKE N'ZY-%';

DELETE FROM trace.Farm
WHERE Code LIKE N'ZY-%';
GO

/* ===================== Setup and the 16 tests (one batch) ===================== */

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
DECLARE @farmTotal INT;
DECLARE @stationTotal INT;
DECLARE @farmPageBeyond INT;
DECLARE @stationPageBeyond INT;

-- Setup: starting data inserted DIRECTLY in the tables (not through the procedures).
-- The ORDER BY gives the identity numbers in the order of the codes.
BEGIN TRY
    INSERT trace.Farm (Code, Name, Region)
    SELECT v.Code, v.Name, N'Test region'
    FROM (VALUES (N'ZY-F01', N'Test farm Y1'),
                 (N'ZY-F02', N'Test farm Y2'),
                 (N'ZY-F03', N'Test farm Y3'),
                 (N'ZY-F04', N'Test farm Y4'),
                 (N'ZY-F05', N'Test farm Y5')) AS v (Code, Name)
    ORDER BY v.Code;

    INSERT trace.Station (Code, Name)
    SELECT v.Code, v.Name
    FROM (VALUES (N'ZY-S01', N'Test station Y1'),   -- 2 functions: SORTING, RECEPTION
                 (N'ZY-S02', N'Test station Y2'),   -- no function
                 (N'ZY-S03', N'Test station Y3'),
                 (N'ZY-S04', N'Test station Y4'),
                 (N'ZY-S05', N'Test station Y5')) AS v (Code, Name)
    ORDER BY v.Code;

    -- The 2 functions of ZY-S01 are inserted in an order that is NOT the order of
    -- the life cycle (SORTING first), to prove that GetStation sorts them itself.
    INSERT trace.StationCapability (StationId, MovementType)
    SELECT StationId, N'SORTING'
    FROM trace.Station
    WHERE Code = N'ZY-S01';

    INSERT trace.StationCapability (StationId, MovementType)
    SELECT StationId, N'RECEPTION'
    FROM trace.Station
    WHERE Code = N'ZY-S01';
END TRY
BEGIN CATCH
    DECLARE @setup_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup failed, tests not run: %s', 16, 1, @setup_error);
    RETURN;
END CATCH;

SET @farmTotal = (SELECT COUNT(*) FROM trace.Farm);
SET @stationTotal = (SELECT COUNT(*) FROM trace.Station);
SET @farmPageBeyond = @farmTotal + 1;
SET @stationPageBeyond = @stationTotal + 1;

/* ---------- ListFarms (tests 1 to 6) ---------- */

-- 1. ListFarms: control (shape checked by the script, content BY EYE)
SELECT N'Test 1: ListFarms, page 1, page size 1000. Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) the LAST 5 rows are ZY-F01, ZY-F02, ZY-F03, ZY-F04, ZY-F05, in this order (columns Code, Name, Region)' AS result_set_1,
       CONCAT(N'2) one row: TotalCount = ', @farmTotal) AS result_set_2;
BEGIN TRY
    EXEC trace.ListFarms @PageNumber = 1, @PageSize = 1000
    WITH RESULT SETS
    (
        (Code NVARCHAR(20), Name NVARCHAR(100), Region NVARCHAR(100)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: control (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: control (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 2. ListFarms: page beyond the end (shape checked by the script, content BY EYE)
SELECT N'Test 2: ListFarms, a page beyond the end (page size 1). Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) no row at all' AS result_set_1,
       CONCAT(N'2) one row: TotalCount = ', @farmTotal, N' (the total does not change)') AS result_set_2;
BEGIN TRY
    EXEC trace.ListFarms @PageNumber = @farmPageBeyond, @PageSize = 1
    WITH RESULT SETS
    (
        (Code NVARCHAR(20), Name NVARCHAR(100), Region NVARCHAR(100)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page beyond the end (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page beyond the end (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 3. ListFarms: page number 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListFarms @PageNumber = 0, @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page number 0', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page number 0', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 4. ListFarms: page size 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListFarms @PageNumber = 1, @PageSize = 0;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page size 0', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page size 0', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 5. ListFarms: page size 1001
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListFarms @PageNumber = 1, @PageSize = 1001;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page size 1001', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page size 1001', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 6. ListFarms: page number NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListFarms @PageNumber = NULL, @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page number NULL', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListFarms: page number NULL', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- ListStations (tests 7 to 12) ---------- */

-- 7. ListStations: control (shape checked by the script, content BY EYE)
SELECT N'Test 7: ListStations, page 1, page size 1000. Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) the LAST 5 rows are ZY-S01, ZY-S02, ZY-S03, ZY-S04, ZY-S05, in this order (columns Code, Name)' AS result_set_1,
       CONCAT(N'2) one row: TotalCount = ', @stationTotal) AS result_set_2;
BEGIN TRY
    EXEC trace.ListStations @PageNumber = 1, @PageSize = 1000
    WITH RESULT SETS
    (
        (Code NVARCHAR(20), Name NVARCHAR(100)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: control (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: control (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 8. ListStations: page beyond the end (shape checked by the script, content BY EYE)
SELECT N'Test 8: ListStations, a page beyond the end (page size 1). Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) no row at all' AS result_set_1,
       CONCAT(N'2) one row: TotalCount = ', @stationTotal, N' (the total does not change)') AS result_set_2;
BEGIN TRY
    EXEC trace.ListStations @PageNumber = @stationPageBeyond, @PageSize = 1
    WITH RESULT SETS
    (
        (Code NVARCHAR(20), Name NVARCHAR(100)),
        (TotalCount INT)
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page beyond the end (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page beyond the end (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 9. ListStations: page number 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListStations @PageNumber = 0, @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page number 0', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page number 0', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 10. ListStations: page size 0
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListStations @PageNumber = 1, @PageSize = 0;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page size 0', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page size 0', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 11. ListStations: page size 1001
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListStations @PageNumber = 1, @PageSize = 1001;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page size 1001', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page size 1001', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 12. ListStations: page number NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.ListStations @PageNumber = NULL, @PageSize = 10;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page number NULL', N'50404', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'ListStations: page number NULL', N'50404',
            CASE WHEN ERROR_NUMBER() <> 50404
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

/* ---------- GetStation (tests 13 to 16) ---------- */

-- 13. GetStation: station with 2 functions (shape checked by the script, content BY EYE)
SELECT N'Test 13: GetStation ZY-S01. Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) one row: ZY-S01, Test station Y1' AS result_set_1,
       N'2) two rows, in this order: RECEPTION, SORTING' AS result_set_2;
BEGIN TRY
    EXEC trace.GetStation @StationCode = N'ZY-S01'
    WITH RESULT SETS
    (
        (Code NVARCHAR(20), Name NVARCHAR(100)),
        (MovementType NVARCHAR(20))
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: station with 2 functions (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: station with 2 functions (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 14. GetStation: station without function (shape checked by the script, content BY EYE)
SELECT N'Test 14: GetStation ZY-S02. Check by eye the 2 result sets just below.' AS check_by_eye,
       N'1) one row: ZY-S02, Test station Y2' AS result_set_1,
       N'2) no row at all (this station has no function yet)' AS result_set_2;
BEGIN TRY
    EXEC trace.GetStation @StationCode = N'ZY-S02'
    WITH RESULT SETS
    (
        (Code NVARCHAR(20), Name NVARCHAR(100)),
        (MovementType NVARCHAR(20))
    );
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: station without function (content checked by eye)', N'(accepted)',
            N'To check by eye (see the 2 result sets above)',
            N'The script checked the number and the shape of the result sets, not the values');
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: station without function (content checked by eye)', N'(accepted)',
            CONCAT(N'ATTENTION: refused or wrong shape, error ', ERROR_NUMBER()),
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 15. GetStation: unknown station
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.GetStation @StationCode = N'ZY-NOPE';
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: unknown station', N'50102', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: unknown station', N'50102',
            CASE WHEN ERROR_NUMBER() <> 50102
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;

-- 16. GetStation: station code NULL
SET @before = dbo.TestFingerprint();
BEGIN TRY
    EXEC trace.GetStation @StationCode = NULL;
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: station code NULL', N'50102', N'ATTENTION: accepted', NULL);
END TRY
BEGIN CATCH
    INSERT @results (test_name, expected, outcome, detail)
    VALUES (N'GetStation: station code NULL', N'50102',
            CASE WHEN ERROR_NUMBER() <> 50102
                      THEN CONCAT(N'ATTENTION: error ', ERROR_NUMBER())
                 WHEN @@TRANCOUNT <> 0 THEN N'ATTENTION: a transaction was left open'
                 WHEN dbo.TestFingerprint() <> @before THEN N'ATTENTION: refused, but the data changed'
                 ELSE N'Refused as expected' END,
            LEFT(ERROR_MESSAGE(), 200));
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
END CATCH;


/* ===================== Results ===================== */

-- Result of each test.
SELECT test_no, test_name, expected, outcome, detail
FROM @results
ORDER BY test_no;

-- Summary: tests_ok + tests_by_eye must equal tests_total (16 = 10 + 6).
SELECT COUNT(*) AS tests_total,
       SUM(CASE WHEN outcome IN (N'Refused as expected', N'Accepted as expected')
                THEN 1 ELSE 0 END) AS tests_ok,
       SUM(CASE WHEN outcome LIKE N'To check by eye%' THEN 1 ELSE 0 END) AS tests_by_eye
FROM @results;
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO
