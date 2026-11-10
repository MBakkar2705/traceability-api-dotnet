/*
  018_add_movement_author.sql
  Lot 11: adds the author of each movement (AuthorId, AuthorName) to trace.Movement in a
  database that already exists. A new database gets the same columns from 002.

  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode). As written, DbName is
    TraceabilityDev. To run on TraceabilityTest, change the :setvar line below to
    TraceabilityTest. Do NOT save that change in the file.
  - Only TraceabilityDev and TraceabilityTest are allowed. Any other name is refused.
  - DRY RUN by default: as written, everything runs in one transaction that is ROLLED BACK
    at the end. The script prints how long each step took and how much log space was used.
    To keep the change, set @keep to N'YES' below. Do NOT save that change in the file.
  - Replayable: if the two columns already exist, nothing is done.
  - All or nothing: one transaction, and any error rolls everything back.

  How the 3,250,000 existing movements get an author:
    1. The two columns are added as NOT NULL with a DEFAULT. SQL Server can keep that value
       in the table definition instead of writing it in every row: this is what the printed
       duration and log space are meant to confirm (they are measured, not assumed).
    2. The two CHECK constraints (not empty) are added and checked on all rows.
    3. The two DEFAULT constraints are dropped, so that a new row cannot be added without an
       author. The existing rows keep the value.
  The value given to the existing movements means "no author was recorded":
    AuthorId   = 00000000-0000-0000-0000-000000000000
    AuthorName = Initial_User   (the interface shows it as "Données initiales")

  Contains DROP CONSTRAINT, for the two DEFAULT constraints created by this script only.
  No TRUNCATE, no DELETE, no UPDATE.
*/

:setvar DbName TraceabilityDev

USE $(DbName);
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Safety: only the two project databases, and the connection must be on $(DbName).
IF N'$(DbName)' NOT IN (N'TraceabilityDev', N'TraceabilityTest')
BEGIN
    THROW 50001, N'Database name ''$(DbName)'' is not allowed. Nothing was done.', 1;
END;

IF DB_NAME() <> N'$(DbName)'
BEGIN
    THROW 50001, N'Wrong database. Expected $(DbName). Nothing was done.', 1;
END;

DECLARE @keep NVARCHAR(3) = N'NO';   -- change to N'YES' to keep the change (do not save)

-- Replayable: do nothing if the columns are already there.
DECLARE @hasId   INT = IIF(COL_LENGTH(N'trace.Movement', N'AuthorId')   IS NULL, 0, 1);
DECLARE @hasName INT = IIF(COL_LENGTH(N'trace.Movement', N'AuthorName') IS NULL, 0, 1);

IF @hasId = 1 AND @hasName = 1
BEGIN
    PRINT N'The author columns already exist. Nothing done.';
    RETURN;
END;

IF @hasId + @hasName <> 0
BEGIN
    THROW 50002, N'Only one of the two author columns exists. Check trace.Movement by hand. Nothing was done.', 1;
END;

DECLARE @rows      BIGINT = (SELECT COUNT_BIG(*) FROM trace.Movement);
DECLARE @logBefore BIGINT = (SELECT used_log_space_in_bytes FROM sys.dm_db_log_space_usage);
DECLARE @t0 DATETIME2 = SYSDATETIME();

PRINT CONCAT(N'Movements before: ', @rows);

BEGIN TRANSACTION;

-- 1. The two columns, with a default value for the existing rows.
EXEC (N'ALTER TABLE trace.Movement ADD
    AuthorId   NVARCHAR(64)  NOT NULL CONSTRAINT DF_Movement_AuthorId
               DEFAULT N''00000000-0000-0000-0000-000000000000'',
    AuthorName NVARCHAR(100) NOT NULL CONSTRAINT DF_Movement_AuthorName
               DEFAULT N''Initial_User'';');
DECLARE @t1 DATETIME2 = SYSDATETIME();

-- 2. The two CHECK constraints, validated on all rows (EXEC: the columns are new in this batch).
EXEC (N'ALTER TABLE trace.Movement ADD CONSTRAINT CK_Movement_AuthorId_NotEmpty
        CHECK (LEN(TRIM(AuthorId)) > 0);');
EXEC (N'ALTER TABLE trace.Movement ADD CONSTRAINT CK_Movement_AuthorName_NotEmpty
        CHECK (LEN(TRIM(AuthorName)) > 0);');
DECLARE @t2 DATETIME2 = SYSDATETIME();

-- 3. No default from now on: a new movement must come with an author.
EXEC (N'ALTER TABLE trace.Movement DROP CONSTRAINT DF_Movement_AuthorId, DF_Movement_AuthorName;');
DECLARE @t3 DATETIME2 = SYSDATETIME();

DECLARE @logAfter BIGINT = (SELECT used_log_space_in_bytes FROM sys.dm_db_log_space_usage);

PRINT CONCAT(N'1. Add the 2 columns (ms): ',        DATEDIFF(MILLISECOND, @t0, @t1));
PRINT CONCAT(N'2. Add the 2 CHECK constraints (ms): ', DATEDIFF(MILLISECOND, @t1, @t2));
PRINT CONCAT(N'3. Drop the 2 defaults (ms): ',      DATEDIFF(MILLISECOND, @t2, @t3));
PRINT CONCAT(N'Log space used by this transaction (KB): ', (@logAfter - @logBefore) / 1024);

-- Check (read only), before the transaction ends.
-- a. The two columns: type, size, NULL not allowed.
SELECT c.name AS column_name, ty.name AS type_name, c.max_length / 2 AS max_chars, c.is_nullable
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'trace.Movement') AND c.name IN (N'AuthorId', N'AuthorName')
ORDER BY c.name;

-- b. The existing movements all have the value "no author recorded".
-- (EXEC: SQL Server reads the whole batch before running it, and the columns do not exist yet then.)
EXEC (N'SELECT COUNT_BIG(*) AS movements,
       COUNT_BIG(CASE WHEN AuthorId = N''00000000-0000-0000-0000-000000000000''
                       AND AuthorName = N''Initial_User'' THEN 1 END) AS with_initial_value
FROM trace.Movement;');

-- c. No default constraint is left on the table (expected: 0 rows), and the 2 CHECK exist (expected: 2 rows).
SELECT name AS default_constraint_left
FROM sys.default_constraints
WHERE parent_object_id = OBJECT_ID(N'trace.Movement')
  AND name IN (N'DF_Movement_AuthorId', N'DF_Movement_AuthorName');

SELECT name AS check_constraint, is_not_trusted
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'trace.Movement')
  AND name IN (N'CK_Movement_AuthorId_NotEmpty', N'CK_Movement_AuthorName_NotEmpty');

IF @keep = N'YES'
BEGIN
    COMMIT TRANSACTION;
    PRINT N'Change KEPT (committed).';
END
ELSE
BEGIN
    ROLLBACK TRANSACTION;
    PRINT N'DRY RUN: everything was rolled back. Nothing changed. Set @keep to YES to keep the change.';
END;
GO
