/*
  003_check_schema.sql
  Checks the schema created by 002 in the database named in DbName.

  Part A: read-only inspection (columns and constraints).
  Part B: refusal tests. Each test tries ONE forbidden insert and checks that the
          database refuses it with the expected constraint. Everything runs in one
          transaction that is ROLLED BACK at the end: no row is kept.
          IDENTITY numbers used by the tests are not given back (normal).

  - Replayable at any time, on an empty database AND on a filled one (lot 2b): the
    last query compares the number of rows of each table before and after the tests.
  - Contains no DROP, TRUNCATE or DELETE.
  - Run after 002_create_schema_and_tables.sql, with the same DbName.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode).
*/

:setvar DbName TraceabilityDev

USE $(DbName);
GO

/* ===================== Part A: inspection (read only) ===================== */

-- A1. Columns of the 5 tables (nvarchar_length is in characters).
SELECT t.name AS table_name,
       c.column_id AS pos,
       c.name AS column_name,
       ty.name AS type_name,
       CASE WHEN ty.name = N'nvarchar' THEN c.max_length / 2 END AS nvarchar_length,
       c.precision,
       c.scale,
       c.is_nullable,
       c.is_identity
FROM sys.tables AS t
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE t.schema_id = SCHEMA_ID(N'trace')
ORDER BY t.name, c.column_id;

-- A2. Primary keys and unique constraints.
SELECT OBJECT_NAME(kc.parent_object_id) AS table_name,
       kc.name AS constraint_name,
       kc.type_desc
FROM sys.key_constraints AS kc
WHERE kc.schema_id = SCHEMA_ID(N'trace')
ORDER BY table_name, constraint_name;

-- A3. Check constraints.
SELECT OBJECT_NAME(cc.parent_object_id) AS table_name,
       cc.name AS constraint_name,
       cc.definition
FROM sys.check_constraints AS cc
WHERE cc.schema_id = SCHEMA_ID(N'trace')
ORDER BY table_name, constraint_name;

-- A4. Foreign keys, one row per column (the two-column key has two rows).
SELECT fk.name AS fk_name,
       OBJECT_NAME(fk.parent_object_id) AS table_name,
       pc.name AS column_name,
       OBJECT_NAME(fk.referenced_object_id) AS references_table,
       rc.name AS references_column,
       fkc.constraint_column_id AS column_position
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns AS pc ON pc.object_id = fkc.parent_object_id
                      AND pc.column_id = fkc.parent_column_id
JOIN sys.columns AS rc ON rc.object_id = fkc.referenced_object_id
                      AND rc.column_id = fkc.referenced_column_id
WHERE fk.schema_id = SCHEMA_ID(N'trace')
ORDER BY fk.name, fkc.constraint_column_id;
GO

/* ===================== Part B: refusal tests ===================== */
/* One batch: variables do not survive a GO. */

SET NOCOUNT ON;
SET XACT_ABORT OFF;  -- a refused insert must not cancel the whole transaction

IF DB_NAME() <> N'$(DbName)'
BEGIN
    RAISERROR(N'Wrong database. Expected $(DbName). Tests not run.', 16, 1);
    RETURN;
END;

-- A table variable is NOT undone by ROLLBACK: the results survive.
DECLARE @results TABLE
(
    test_no       INT IDENTITY(1,1),
    test_name     NVARCHAR(100),
    expected_rule NVARCHAR(100),
    outcome       NVARCHAR(250)
);

DECLARE @FarmId INT, @StationId INT, @BatchId INT;

-- Number of rows of each table BEFORE the tests (a table variable survives ROLLBACK).
DECLARE @before TABLE (table_name NVARCHAR(30), row_count BIGINT);
INSERT @before (table_name, row_count)
SELECT N'Farm', COUNT(*) FROM trace.Farm
UNION ALL SELECT N'Station', COUNT(*) FROM trace.Station
UNION ALL SELECT N'StationCapability', COUNT(*) FROM trace.StationCapability
UNION ALL SELECT N'Batch', COUNT(*) FROM trace.Batch
UNION ALL SELECT N'Movement', COUNT(*) FROM trace.Movement;

BEGIN TRANSACTION;

BEGIN TRY

    -- Setup: valid rows used by the tests (rolled back at the end).
    INSERT trace.Farm (Code, Name, Region) VALUES (N'ZZ-F01', N'Test farm', N'Test region');
    SET @FarmId = SCOPE_IDENTITY();

    INSERT trace.Station (Code, Name) VALUES (N'ZZ-S01', N'Test station');
    SET @StationId = SCOPE_IDENTITY();

    -- This station has ONE function only: RECEPTION.
    INSERT trace.StationCapability (StationId, MovementType) VALUES (@StationId, N'RECEPTION');

    INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
    VALUES (N'ZZ-B01', @FarmId, N'Test variety', '2026-10-14', 500.00, N'RECEIVED');
    SET @BatchId = SCOPE_IDENTITY();

    -- 1. Control: a fully valid movement must be ACCEPTED.
    BEGIN TRY
        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        VALUES (@BatchId, @StationId, N'RECEPTION', 500.00, '2026-10-14T06:30:00');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Control: valid movement', N'(accepted)', N'Accepted as expected');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Control: valid movement', N'(accepted)',
                N'ATTENTION: refused: ' + LEFT(ERROR_MESSAGE(), 150));
    END CATCH;

    -- 2. Farm: same code twice.
    BEGIN TRY
        INSERT trace.Farm (Code, Name, Region) VALUES (N'ZZ-F01', N'Other', N'Other');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Farm: duplicate code', N'UQ_Farm_Code', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Farm: duplicate code', N'UQ_Farm_Code',
                CASE WHEN ERROR_MESSAGE() LIKE N'%UQ_Farm_Code%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 3. Farm: same code, different case (the collation is case-insensitive).
    BEGIN TRY
        INSERT trace.Farm (Code, Name, Region) VALUES (N'zz-f01', N'Other', N'Other');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Farm: same code, other case', N'UQ_Farm_Code', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Farm: same code, other case', N'UQ_Farm_Code',
                CASE WHEN ERROR_MESSAGE() LIKE N'%UQ_Farm_Code%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 4. Farm: empty code (spaces only).
    BEGIN TRY
        INSERT trace.Farm (Code, Name, Region) VALUES (N'   ', N'Other', N'Other');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Farm: empty code', N'CK_Farm_Code_NotEmpty', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Farm: empty code', N'CK_Farm_Code_NotEmpty',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_Farm_Code_NotEmpty%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 5. Station: same code twice.
    BEGIN TRY
        INSERT trace.Station (Code, Name) VALUES (N'ZZ-S01', N'Other');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Station: duplicate code', N'UQ_Station_Code', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Station: duplicate code', N'UQ_Station_Code',
                CASE WHEN ERROR_MESSAGE() LIKE N'%UQ_Station_Code%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 6. Station: empty code.
    BEGIN TRY
        INSERT trace.Station (Code, Name) VALUES (N'   ', N'Other');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Station: empty code', N'CK_Station_Code_NotEmpty', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Station: empty code', N'CK_Station_Code_NotEmpty',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_Station_Code_NotEmpty%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 7. StationCapability: same function declared twice for a station.
    BEGIN TRY
        INSERT trace.StationCapability (StationId, MovementType) VALUES (@StationId, N'RECEPTION');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Capability: declared twice', N'PK_StationCapability', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Capability: declared twice', N'PK_StationCapability',
                CASE WHEN ERROR_MESSAGE() LIKE N'%PK_StationCapability%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 8. StationCapability: unknown function.
    BEGIN TRY
        INSERT trace.StationCapability (StationId, MovementType) VALUES (@StationId, N'LOST');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Capability: unknown function', N'CK_StationCapability_MovementType', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Capability: unknown function', N'CK_StationCapability_MovementType',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_StationCapability_MovementType%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 9. StationCapability: unknown station.
    BEGIN TRY
        INSERT trace.StationCapability (StationId, MovementType) VALUES (-1, N'RECEPTION');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Capability: unknown station', N'FK_StationCapability_Station', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Capability: unknown station', N'FK_StationCapability_Station',
                CASE WHEN ERROR_MESSAGE() LIKE N'%FK_StationCapability_Station%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 10. Batch: unknown farm.
    BEGIN TRY
        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (N'ZZ-B02', -1, N'Test variety', '2026-10-14', 100.00, N'RECEIVED');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: unknown farm', N'FK_Batch_Farm', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: unknown farm', N'FK_Batch_Farm',
                CASE WHEN ERROR_MESSAGE() LIKE N'%FK_Batch_Farm%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 11. Batch: quantity 0.
    BEGIN TRY
        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (N'ZZ-B03', @FarmId, N'Test variety', '2026-10-14', 0, N'RECEIVED');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: quantity 0', N'CK_Batch_QuantityKg_Positive', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: quantity 0', N'CK_Batch_QuantityKg_Positive',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_Batch_QuantityKg_Positive%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 12. Batch: unknown status.
    BEGIN TRY
        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (N'ZZ-B04', @FarmId, N'Test variety', '2026-10-14', 100.00, N'LOST');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: unknown status', N'CK_Batch_Status', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: unknown status', N'CK_Batch_Status',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_Batch_Status%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 13. Batch: same code twice.
    BEGIN TRY
        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (N'ZZ-B01', @FarmId, N'Test variety', '2026-10-14', 100.00, N'RECEIVED');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: duplicate code', N'UQ_Batch_BatchCode', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: duplicate code', N'UQ_Batch_BatchCode',
                CASE WHEN ERROR_MESSAGE() LIKE N'%UQ_Batch_BatchCode%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 14. Batch: empty code.
    BEGIN TRY
        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        VALUES (N'   ', @FarmId, N'Test variety', '2026-10-14', 100.00, N'RECEIVED');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: empty code', N'CK_Batch_BatchCode_NotEmpty', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Batch: empty code', N'CK_Batch_BatchCode_NotEmpty',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_Batch_BatchCode_NotEmpty%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 15. Movement: unknown batch.
    BEGIN TRY
        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        VALUES (-1, @StationId, N'RECEPTION', 100.00, '2026-10-14T07:00:00');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Movement: unknown batch', N'FK_Movement_Batch', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Movement: unknown batch', N'FK_Movement_Batch',
                CASE WHEN ERROR_MESSAGE() LIKE N'%FK_Movement_Batch%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 16. Movement: quantity 0.
    BEGIN TRY
        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        VALUES (@BatchId, @StationId, N'RECEPTION', 0, '2026-10-14T07:00:00');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Movement: quantity 0', N'CK_Movement_QuantityKg_Positive', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Movement: quantity 0', N'CK_Movement_QuantityKg_Positive',
                CASE WHEN ERROR_MESSAGE() LIKE N'%CK_Movement_QuantityKg_Positive%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

    -- 17. Movement: the station does NOT have this function (the key rule).
    --     ZZ-S01 can only do RECEPTION; here we ask for PACKING.
    BEGIN TRY
        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        VALUES (@BatchId, @StationId, N'PACKING', 100.00, '2026-10-14T07:00:00');
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Movement: station without the function', N'FK_Movement_StationCapability', N'ATTENTION: accepted');
    END TRY
    BEGIN CATCH
        INSERT @results (test_name, expected_rule, outcome)
        VALUES (N'Movement: station without the function', N'FK_Movement_StationCapability',
                CASE WHEN ERROR_MESSAGE() LIKE N'%FK_Movement_StationCapability%' THEN N'Refused as expected'
                     ELSE N'ATTENTION: other error: ' + LEFT(ERROR_MESSAGE(), 150) END);
    END CATCH;

END TRY
BEGIN CATCH
    -- The setup itself failed: undo everything and say so.
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @setup_error NVARCHAR(2000) = ERROR_MESSAGE();
    RAISERROR(N'Setup failed, tests not run: %s', 16, 1, @setup_error);
    RETURN;
END CATCH;

-- Undo everything the tests inserted.
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

-- Result of each test.
SELECT test_no, test_name, expected_rule, outcome
FROM @results
ORDER BY test_no;

-- Summary: tests_ok must equal tests_total.
SELECT COUNT(*) AS tests_total,
       SUM(CASE WHEN outcome IN (N'Refused as expected', N'Accepted as expected')
                THEN 1 ELSE 0 END) AS tests_ok
FROM @results;

-- Proof of the ROLLBACK: every table must have the same number of rows as before
-- the tests (0 on an empty database, the same number on a filled one).
SELECT b.table_name,
       b.row_count AS rows_before,
       a.row_count AS rows_after,
       CASE WHEN a.row_count = b.row_count THEN N'unchanged'
            ELSE N'ATTENTION: changed' END AS outcome
FROM @before AS b
JOIN (SELECT N'Farm' AS table_name, COUNT(*) AS row_count FROM trace.Farm
      UNION ALL SELECT N'Station', COUNT(*) FROM trace.Station
      UNION ALL SELECT N'StationCapability', COUNT(*) FROM trace.StationCapability
      UNION ALL SELECT N'Batch', COUNT(*) FROM trace.Batch
      UNION ALL SELECT N'Movement', COUNT(*) FROM trace.Movement) AS a
  ON a.table_name = b.table_name
ORDER BY b.table_name;
GO
