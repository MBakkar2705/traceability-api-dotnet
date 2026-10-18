/*
  900_reset_dev_database.sql

  *** DESTRUCTIVE: contains DROP DATABASE ***
  Deletes the development database TraceabilityDev and ALL its data
  (data file and log file are removed from disk). No backup is made.

  Use it only to start again from scratch, then run 001, 002, 003 again.

  - Only TraceabilityDev is concerned (never TraceabilityTest, never another database).
  - Safety lock: as written, the script does NOTHING. To really drop the database,
    change @confirm to N'YES' below. Do NOT save that change in the file.
  - Other connections to TraceabilityDev (other query windows) are disconnected.
*/

USE master;
GO

DECLARE @confirm NVARCHAR(3) = N'NO';   -- change to N'YES' to really drop (do not save)

IF @confirm <> N'YES'
BEGIN
    PRINT N'Nothing done. To drop TraceabilityDev, set @confirm to YES and run again.';
    RETURN;
END;

IF DB_ID(N'TraceabilityDev') IS NULL
BEGIN
    PRINT N'Database TraceabilityDev does not exist. Nothing done.';
    RETURN;
END;

BEGIN TRY
    -- Otherwise DROP fails with "database in use" if another window is connected to it.
    ALTER DATABASE TraceabilityDev SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE TraceabilityDev;
    PRINT N'Database TraceabilityDev dropped. Run 001, 002, 003 to rebuild.';
END TRY
BEGIN CATCH
    DECLARE @drop_error NVARCHAR(2000) = ERROR_MESSAGE();
    -- If the drop failed, give the database back to everybody.
    IF DB_ID(N'TraceabilityDev') IS NOT NULL
        ALTER DATABASE TraceabilityDev SET MULTI_USER;
    RAISERROR(N'Drop failed, database kept: %s', 16, 1, @drop_error);
END CATCH;
GO
