/*
  001_create_database.sql
  Creates the database named in DbName (TraceabilityDev for development,
  TraceabilityTest for the tests).

  - Replayable: if the database already exists, nothing is changed.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode), connected to the
    instance (localhost). Change the :setvar line below to choose the database.
  - Contains no DROP, TRUNCATE or DELETE.
*/

:setvar DbName TraceabilityDev

USE master;
GO

IF DB_ID(N'$(DbName)') IS NULL
BEGIN
    CREATE DATABASE $(DbName);

    -- SIMPLE recovery: the transaction log does not keep growing during large
    -- data loads (lot 2). Fine for development, not for a real production database.
    ALTER DATABASE $(DbName) SET RECOVERY SIMPLE;

    PRINT N'Database $(DbName) created.';
END
ELSE
BEGIN
    PRINT N'Database $(DbName) already exists. Nothing changed.';
END
GO

-- Check (read only): collation, recovery model, state.
SELECT name, collation_name, recovery_model_desc, state_desc
FROM sys.databases
WHERE name = N'$(DbName)';

-- Check (read only): where the data and log files are.
SELECT name AS logical_name, type_desc, physical_name
FROM sys.master_files
WHERE database_id = DB_ID(N'$(DbName)');
GO
