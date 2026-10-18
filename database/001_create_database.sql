/*
  001_create_database.sql
  Creates the development database TraceabilityDev.

  - Replayable: if the database already exists, nothing is changed.
  - Run in SSMS, connected to the instance (localhost).
  - Contains no DROP, TRUNCATE or DELETE.
*/

USE master;
GO

IF DB_ID(N'TraceabilityDev') IS NULL
BEGIN
    CREATE DATABASE TraceabilityDev;

    -- SIMPLE recovery: the transaction log does not keep growing during large
    -- data loads (lot 2). Fine for development, not for a real production database.
    ALTER DATABASE TraceabilityDev SET RECOVERY SIMPLE;

    PRINT N'Database TraceabilityDev created.';
END
ELSE
BEGIN
    PRINT N'Database TraceabilityDev already exists. Nothing changed.';
END
GO

-- Check (read only): collation, recovery model, state.
SELECT name, collation_name, recovery_model_desc, state_desc
FROM sys.databases
WHERE name = N'TraceabilityDev';

-- Check (read only): where the data and log files are.
SELECT name AS logical_name, type_desc, physical_name
FROM sys.master_files
WHERE database_id = DB_ID(N'TraceabilityDev');
GO
