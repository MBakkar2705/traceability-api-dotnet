/*
  900_reset_dev_database.sql

  *** DESTRUCTIVE: contains DROP DATABASE ***
  Deletes the database named in DbName and ALL its data
  (data file and log file are removed from disk). No backup is made.

  Use it only to start again from scratch, then run 001, 002, 003 again.

  - Only two names are allowed: TraceabilityDev and TraceabilityTest. Any other
    name is refused (never another database).
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode). As written, DbName is
    TraceabilityDev. To reset the test database, change the :setvar line below to
    TraceabilityTest. Do NOT save that change in the file.
  - Safety lock: as written, the script does NOTHING. To really drop the database,
    change @confirm to N'YES' below. Do NOT save that change in the file.
  - Other connections to the database (other query windows) are disconnected.
*/

:setvar DbName TraceabilityDev

USE master;
GO

-- Safety: only the two project databases can be dropped.
IF N'$(DbName)' NOT IN (N'TraceabilityDev', N'TraceabilityTest')
BEGIN
    RAISERROR(N'Database name ''$(DbName)'' is not allowed. Nothing done.', 16, 1);
    RETURN;
END;

DECLARE @confirm NVARCHAR(3) = N'NO';   -- change to N'YES' to really drop (do not save)

IF @confirm <> N'YES'
BEGIN
    PRINT N'Nothing done. To drop $(DbName), set @confirm to YES and run again.';
    RETURN;
END;

IF DB_ID(N'$(DbName)') IS NULL
BEGIN
    PRINT N'Database $(DbName) does not exist. Nothing done.';
    RETURN;
END;

BEGIN TRY
    -- Otherwise DROP fails with "database in use" if another window is connected to it.
    ALTER DATABASE $(DbName) SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE $(DbName);
    PRINT N'Database $(DbName) dropped. Run 001, 002, 003 to rebuild.';
END TRY
BEGIN CATCH
    DECLARE @drop_error NVARCHAR(2000) = ERROR_MESSAGE();
    -- If the drop failed, give the database back to everybody.
    IF DB_ID(N'$(DbName)') IS NOT NULL
        ALTER DATABASE $(DbName) SET MULTI_USER;
    RAISERROR(N'Drop failed, database kept: %s', 16, 1, @drop_error);
END CATCH;
GO
