/*
  021_find_unordered_movements.sql
  Lot 12c: counts and lists the movements whose time is out of order or in the future, in the database
  named in DbName. It changes nothing in that database: no INSERT, UPDATE or DELETE. It only reads, and
  it uses one temporary table (#Ordered, in tempdb), dropped at the start and at the end.

  - Why: before lot 12c nothing checked the time of a movement. Since lot 12c, AddMovement and
    ReplaceMovement refuse a time that is not strictly after the previous valid movement (50311), or
    that is more than 5 minutes in the future (50310). Data written before may break these rules.
    This script shows how many movements do. It corrects nothing: old data is not touched (decision
    of lot 12c, docs/adr/0018-heure-des-mouvements.md).
  - A valid movement is one that is not cancelled, with its latest correction applied (like GetBatch).
    The previous movement is the previous valid one of the same batch, in the order of MovementId.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode), after changing DbName if needed.
  - Result 1: the counts. Result 2: the first 200 movements that break a rule.
  - The duration on a large database (for example one filled by 007) has not been measured.
*/

:setvar DbName TraceabilityDev

USE $(DbName);
GO

-- Safety: if the connection is not on $(DbName) (wrong database, or SQLCMD mode is off), nothing
-- below is executed. SET NOEXEC ON makes SQL Server read the next batches without running them.
IF DB_NAME() <> N'$(DbName)'
BEGIN
    RAISERROR(N'Wrong database or SQLCMD mode is off. Expected $(DbName). Nothing was run.', 16, 1);
    SET NOEXEC ON;
END;
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'tempdb..#Ordered') IS NOT NULL DROP TABLE #Ordered;

-- The valid version of every movement that is not cancelled, with the time of the previous valid
-- movement of the same batch.
WITH Valid AS
(
    SELECT m.BatchId, m.MovementId, m.MovementType, COALESCE(c.OccurredAt, m.OccurredAt) AS ValidTime
    FROM trace.Movement AS m
    OUTER APPLY (SELECT TOP (1) cc.Kind, cc.OccurredAt
                 FROM trace.MovementCorrection AS cc
                 WHERE cc.MovementId = m.MovementId
                 ORDER BY cc.CorrectionId DESC) AS c
    WHERE c.Kind IS NULL OR c.Kind <> N'CANCEL'
)
SELECT BatchId, MovementId, MovementType, ValidTime,
       LAG(ValidTime) OVER (PARTITION BY BatchId ORDER BY MovementId) AS PreviousTime
INTO #Ordered
FROM Valid;

-- Result 1: the counts.
SELECT COUNT(*) AS valid_movements,
       COUNT(DISTINCT BatchId) AS batches_checked,
       SUM(CASE WHEN ValidTime = PreviousTime THEN 1 ELSE 0 END) AS equal_to_previous,
       SUM(CASE WHEN ValidTime < PreviousTime THEN 1 ELSE 0 END) AS before_previous,
       SUM(CASE WHEN ValidTime > DATEADD(MINUTE, 5, SYSUTCDATETIME()) THEN 1 ELSE 0 END) AS in_the_future,
       COUNT(DISTINCT CASE WHEN ValidTime <= PreviousTime
                             OR ValidTime > DATEADD(MINUTE, 5, SYSUTCDATETIME())
                           THEN BatchId END) AS batches_with_a_problem
FROM #Ordered;

-- Result 2: the first 200 movements that break a rule.
SELECT TOP (200)
       b.BatchCode, o.MovementId, o.MovementType, o.ValidTime, o.PreviousTime,
       CASE WHEN o.ValidTime < o.PreviousTime THEN N'before the previous'
            WHEN o.ValidTime = o.PreviousTime THEN N'equal to the previous'
            ELSE N'in the future' END AS problem
FROM #Ordered AS o
JOIN trace.Batch AS b ON b.BatchId = o.BatchId
WHERE o.ValidTime <= o.PreviousTime
   OR o.ValidTime > DATEADD(MINUTE, 5, SYSUTCDATETIME())
ORDER BY o.BatchId, o.MovementId;

IF OBJECT_ID(N'tempdb..#Ordered') IS NOT NULL DROP TABLE #Ordered;
GO

-- End of the safety lock set at the top of the script.
SET NOEXEC OFF;
GO
