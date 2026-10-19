/*
  010_create_indexes.sql
  Creates the extra indexes of lot 2b in TraceabilityDev, one by one.
  Each index is added only after a measurement showed a need (docs/mesures.md).

  - Runs ONLY on TraceabilityDev. The name is written in the script, so SQLCMD
    mode is not needed. TraceabilityTest is not touched.
  - Replayable: an index is created only if it does not exist yet.
  - Contains no DROP, TRUNCATE or DELETE. It does not change any row.
  - Creating an index on a filled table takes some seconds and uses disk space
    (see the sizes in part C of 008).

  Indexes:
    1. IX_Movement_BatchId on trace.Movement (BatchId)
       For the journey of one batch (trace.GetBatch, second result): the movements
       of one batch are read by BatchId. Without this index, SQL Server reads the whole table.
       The primary key is added to a nonclustered index by SQL Server, so the movements
       of a batch should come back ordered by MovementId: to be checked in the plan.
*/

USE TraceabilityDev;
GO

SET NOCOUNT ON;

IF DB_NAME() <> N'TraceabilityDev'
BEGIN
    THROW 50001, N'Wrong database. This script runs only on TraceabilityDev. Nothing was done.', 1;
END;
GO

/* ---------- 1. IX_Movement_BatchId ---------- */
IF NOT EXISTS (SELECT 1
               FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'trace.Movement')
                 AND name = N'IX_Movement_BatchId')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Movement_BatchId
        ON trace.Movement (BatchId);
    PRINT N'Index IX_Movement_BatchId created.';
END
ELSE
BEGIN
    PRINT N'Index IX_Movement_BatchId already exists. Nothing done.';
END;
GO
