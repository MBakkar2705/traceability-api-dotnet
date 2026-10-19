/*
  007_generate_volume_data.sql
  Fills TraceabilityDev with INVENTED data, to measure searches on a large volume
  (lot 2b). It inserts directly into the tables (the procedures are not used), by
  sets, with fixed formulas computed from the batch number N: no randomness, so the
  numbers are exact and identical on every machine.

  - Runs ONLY on TraceabilityDev. The name is written in the script, so SQLCMD
    mode is not needed. On any other database the script refuses to run.
  - Run 001, 002, 004 and 005 first.
  - Contains no DROP, TRUNCATE or DELETE.
  - @TargetLots = number of batches wanted. As written: 10000 (a sample, to measure
    the size on disk). For the full set, change it to 1000000 and run the script
    again: it continues where it stopped. Do NOT save that change.
  - Resumable: it only accepts an EMPTY database, or the beginning of THIS data set
    (all farms, stations and functions, and batches 1..N complete with their
    movements). Anything else: it refuses and tells what it found.
  - Chunks of 100000 batches, one transaction per chunk: if a chunk fails, it is
    undone as a whole and the previous chunks stay.
  - Disk guard: before each chunk it reads the free space of the volume(s) holding
    the database files. Below @MinFreeGB (40) it stops with error 50005.
  - To start again from scratch: 900, then 001, 002, 004, 005.
  - Guard numbers (range 50000-50099 reserved for scripts):
      50001 wrong database          50002 invalid @TargetLots
      50003 unexpected content      50004 reference data not as expected
      50005 not enough free disk space

  The full data set is always 1000000 batches; a smaller run is its beginning.
  Formulas (N = batch number, 1 to 1000000):
  - Farms: 200 (F001 to F200). N odd: one of the 20 big farms (F001-F020), N even:
    one of the 180 others. So the 20 big farms hold half of the batches.
  - Stations: 30. SITE-01..10 (RECEPTION and SORTING), PCK-01..10 (PACKING),
    SHP-01..10 (SHIPMENT). 40 functions.
  - Status follows the rank (the oldest batches are shipped):
      N 1-600000        SHIPPED   4 movements
      N 600001-750000   PACKED    3 movements
      N 750001-900000   SORTED    2 movements
      N 900001-1000000  RECEIVED  1 movement      (3250000 movements in all)
  - Harvest date: grows with N, from 2024-10-20 (N = 1) to 2026-10-19 (N = 1000000).
    Fixed dates: GETDATE() is never used.
  - Quantity: RECEPTION between 100.00 and 1000.00 kg; each next step loses 0 to 10 %
    (rounded so that it never exceeds 10 %), never gains. Batch.QuantityKg and
    Batch.Status are those of the LAST movement, as AddMovement leaves them.
  - Times (UTC): RECEPTION on the harvest day between 06:00 and 10:59; each next step
    2 to 6 hours after the previous one.
*/

USE TraceabilityDev;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Settings (see the header).
DECLARE @TargetLots INT           = 10000;   -- 10000 = sample; 1000000 = full set (do not save the change)
DECLARE @MinFreeGB  DECIMAL(10,2) = 40;      -- stop if the free disk space goes below this
DECLARE @ChunkSize  INT           = 100000;  -- batches per transaction

-- Safety 1: only TraceabilityDev.
IF DB_NAME() <> N'TraceabilityDev'
BEGIN
    THROW 50001, N'Wrong database. This script runs only on TraceabilityDev. Nothing was done.', 1;
END;

-- Safety 2: the target must be possible.
IF @TargetLots < 1 OR @TargetLots > 1000000
BEGIN
    THROW 50002, N'@TargetLots must be between 1 and 1000000. Nothing was done.', 1;
END;

DECLARE @msg NVARCHAR(2048);

/* ---------- What is already in the database? ---------- */

DECLARE @Farms     INT = (SELECT COUNT(*) FROM trace.Farm);
DECLARE @Stations  INT = (SELECT COUNT(*) FROM trace.Station);
DECLARE @Caps      INT = (SELECT COUNT(*) FROM trace.StationCapability);
DECLARE @Batches   INT = (SELECT COUNT(*) FROM trace.Batch);
DECLARE @Movements INT = (SELECT COUNT(*) FROM trace.Movement);

DECLARE @Fresh BIT = CASE WHEN @Farms + @Stations + @Caps + @Batches + @Movements = 0
                          THEN 1 ELSE 0 END;

IF @Fresh = 0
BEGIN
    -- Something is already there. It must be the beginning of THIS data set.
    DECLARE @BadCodes INT = 0;
    DECLARE @MinLot   INT = 0;
    DECLARE @MaxLot   INT = 0;

    SELECT @BadCodes = COUNT(*)
    FROM trace.Batch
    WHERE BatchCode NOT LIKE N'LOT-[0-9][0-9][0-9][0-9][0-9][0-9][0-9]';

    IF @BadCodes = 0 AND @Batches > 0
    BEGIN
        SELECT @MinLot = MIN(TRY_CAST(SUBSTRING(BatchCode, 5, 7) AS INT)),
               @MaxLot = MAX(TRY_CAST(SUBSTRING(BatchCode, 5, 7) AS INT))
        FROM trace.Batch;
    END;

    -- Movements expected for batches 1..@Batches (4, 3, 2, 1 movements by rank).
    DECLARE @ExpMov INT =
          4 * LEAST(@Batches, 600000)
        + 3 * GREATEST(0, LEAST(@Batches, 750000) - 600000)
        + 2 * GREATEST(0, LEAST(@Batches, 900000) - 750000)
        + 1 * GREATEST(0, LEAST(@Batches, 1000000) - 900000);

    IF NOT (    @Farms = 200 AND @Stations = 30 AND @Caps = 40
            AND @BadCodes = 0
            AND (@Batches = 0 OR (@MinLot = 1 AND @MaxLot = @Batches))
            AND @Movements = @ExpMov)
    BEGIN
        SET @msg = CONCAT(N'TraceabilityDev already holds data that is not the beginning of this data set. ',
                          N'Farms ', @Farms, N', stations ', @Stations, N', functions ', @Caps,
                          N', batches ', @Batches, N' (codes not LOT-nnnnnnn: ', @BadCodes,
                          N'; first/last number ', @MinLot, N'/', @MaxLot, N'), movements ', @Movements,
                          N' (expected ', @ExpMov, N'). Nothing was done. To start again: 900, then 001, 002, 004, 005.');
        THROW 50003, @msg, 1;
    END;

    IF @Batches >= @TargetLots
    BEGIN
        PRINT N'Nothing to do: the database already holds the requested number of batches.';
        RETURN;
    END;
END;

/* ---------- Reference data: only on an empty database ---------- */

IF @Fresh = 1
BEGIN
    BEGIN TRANSACTION;

    -- 200 farms: F001 to F200.
    INSERT trace.Farm (Code, Name, Region)
    SELECT CONCAT(N'F', RIGHT(CONCAT(N'00', g.value), 3)),
           CONCAT(N'Farm ', RIGHT(CONCAT(N'00', g.value), 3)),
           CONCAT(N'Region ', CHAR(65 + (g.value % 4)))
    FROM GENERATE_SERIES(1, 200) AS g
    ORDER BY g.value;

    -- 30 stations.
    INSERT trace.Station (Code, Name)
    SELECT CONCAT(N'SITE-', RIGHT(CONCAT(N'0', g.value), 2)),
           CONCAT(N'Reception and sorting site ', RIGHT(CONCAT(N'0', g.value), 2))
    FROM GENERATE_SERIES(1, 10) AS g
    ORDER BY g.value;

    INSERT trace.Station (Code, Name)
    SELECT CONCAT(N'PCK-', RIGHT(CONCAT(N'0', g.value), 2)),
           CONCAT(N'Packing station ', RIGHT(CONCAT(N'0', g.value), 2))
    FROM GENERATE_SERIES(1, 10) AS g
    ORDER BY g.value;

    INSERT trace.Station (Code, Name)
    SELECT CONCAT(N'SHP-', RIGHT(CONCAT(N'0', g.value), 2)),
           CONCAT(N'Shipping station ', RIGHT(CONCAT(N'0', g.value), 2))
    FROM GENERATE_SERIES(1, 10) AS g
    ORDER BY g.value;

    -- 40 functions.
    INSERT trace.StationCapability (StationId, MovementType)
    SELECT StationId, N'RECEPTION' FROM trace.Station WHERE Code LIKE N'SITE-[0-9][0-9]'
    UNION ALL
    SELECT StationId, N'SORTING'   FROM trace.Station WHERE Code LIKE N'SITE-[0-9][0-9]'
    UNION ALL
    SELECT StationId, N'PACKING'   FROM trace.Station WHERE Code LIKE N'PCK-[0-9][0-9]'
    UNION ALL
    SELECT StationId, N'SHIPMENT'  FROM trace.Station WHERE Code LIKE N'SHP-[0-9][0-9]';

    COMMIT TRANSACTION;
END;

/* ---------- Lookup tables: farm number -> FarmId, station kind and number -> StationId ---------- */
-- IDENTITY numbers are not always 1, 2, 3... (the tests of 003 use some and do not
-- give them back), so the formulas never assume a FarmId or a StationId.

DECLARE @FarmMap TABLE (No INT NOT NULL PRIMARY KEY, FarmId INT NOT NULL);
DECLARE @StationMap TABLE (Kind VARCHAR(4) NOT NULL, Idx INT NOT NULL, StationId INT NOT NULL,
                           PRIMARY KEY (Kind, Idx));

INSERT @FarmMap (No, FarmId)
SELECT TRY_CAST(SUBSTRING(Code, 2, 3) AS INT), FarmId
FROM trace.Farm
WHERE Code LIKE N'F[0-9][0-9][0-9]';

INSERT @StationMap (Kind, Idx, StationId)
SELECT 'SITE', TRY_CAST(RIGHT(Code, 2) AS INT), StationId FROM trace.Station WHERE Code LIKE N'SITE-[0-9][0-9]'
UNION ALL
SELECT 'PCK',  TRY_CAST(RIGHT(Code, 2) AS INT), StationId FROM trace.Station WHERE Code LIKE N'PCK-[0-9][0-9]'
UNION ALL
SELECT 'SHP',  TRY_CAST(RIGHT(Code, 2) AS INT), StationId FROM trace.Station WHERE Code LIKE N'SHP-[0-9][0-9]';

IF (SELECT COUNT(*) FROM @FarmMap WHERE No BETWEEN 1 AND 200) <> 200
   OR (SELECT COUNT(*) FROM @StationMap WHERE Idx BETWEEN 1 AND 10) <> 30
BEGIN
    THROW 50004, N'The farms or stations are not F001-F200, SITE-01..10, PCK-01..10, SHP-01..10. Nothing was done.', 1;
END;

/* ---------- Batches and movements, chunk by chunk ---------- */

-- The derived values of the batches of a chunk (all formulas are here, once).
-- A table variable lives only for this run: nothing is left behind.
DECLARE @Lot TABLE
(
    LotNo       INT           NOT NULL PRIMARY KEY,
    BatchCode   NVARCHAR(30)  NOT NULL,
    FarmId      INT           NOT NULL,
    Variety     NVARCHAR(50)  NOT NULL,
    HarvestDate DATE          NOT NULL,
    Steps       TINYINT       NOT NULL,   -- number of movements: 1 to 4
    SiteId      INT           NOT NULL,   -- station of RECEPTION and SORTING
    PckId       INT           NOT NULL,   -- station of PACKING
    ShpId       INT           NOT NULL,   -- station of SHIPMENT
    Q1          DECIMAL(10,2) NOT NULL,
    Q2          DECIMAL(10,2) NOT NULL,
    Q3          DECIMAL(10,2) NOT NULL,
    Q4          DECIMAL(10,2) NOT NULL,
    T1          DATETIME2     NOT NULL,
    T2          DATETIME2     NOT NULL,
    T3          DATETIME2     NOT NULL,
    T4          DATETIME2     NOT NULL
);

DECLARE @From     INT = @Batches + 1;
DECLARE @To       INT;
DECLARE @FreeGB   DECIMAL(10,2);
DECLARE @FreeText NVARCHAR(20);

WHILE @From <= @TargetLots
BEGIN
    SET @To = LEAST(@TargetLots, @From + @ChunkSize - 1);

    -- Disk guard: the smallest free space among the volumes of the database files.
    SELECT @FreeGB = MIN(CAST(vs.available_bytes / 1073741824.0 AS DECIMAL(10,2)))
    FROM sys.master_files AS mf
    CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
    WHERE mf.database_id = DB_ID();

    IF @FreeGB < @MinFreeGB
    BEGIN
        SET @msg = CONCAT(N'Stopped before batch ', @From, N': free disk space is ', @FreeGB,
                          N' GB, below the limit of ', @MinFreeGB,
                          N' GB. Batches before this one are kept. Nothing else was done.');
        THROW 50005, @msg, 1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Derived values of the batches @From..@To.
        INSERT @Lot (LotNo, BatchCode, FarmId, Variety, HarvestDate, Steps,
                     SiteId, PckId, ShpId, Q1, Q2, Q3, Q4, T1, T2, T3, T4)
        SELECT a.n,
               CONCAT(N'LOT-', RIGHT(CONCAT(N'000000', a.n), 7)),
               fm.FarmId,
               CHOOSE(a.n % 5 + 1, N'cherry', N'roma', N'beefsteak', N'vine', N'round'),
               b.HarvestDate,
               b.Steps,
               s1.StationId, s2.StationId, s3.StationId,
               CAST(b.Q1h  / 100.0 AS DECIMAL(10,2)),
               CAST(c2.Q2h / 100.0 AS DECIMAL(10,2)),
               CAST(c3.Q3h / 100.0 AS DECIMAL(10,2)),
               CAST(c4.Q4h / 100.0 AS DECIMAL(10,2)),
               d1.T1, d2.T2, d3.T3, d4.T4
        FROM GENERATE_SERIES(@From, @To) AS g
        CROSS APPLY (SELECT CAST(g.value AS INT) AS n, CAST(g.value AS BIGINT) AS nb) AS a
        CROSS APPLY (SELECT
                         CASE WHEN a.n <= 600000 THEN 4
                              WHEN a.n <= 750000 THEN 3
                              WHEN a.n <= 900000 THEN 2
                              ELSE 1 END AS Steps,
                         CASE WHEN a.n % 2 = 1 THEN 1 + ((a.n - 1) / 2) % 20      -- big farms 1..20
                              ELSE 21 + (a.n / 2 - 1) % 180 END AS FarmNo,        -- other farms 21..200
                         DATEADD(DAY, CAST((a.nb - 1) * 729 / 999999 AS INT),
                                 CAST('20241020' AS DATE)) AS HarvestDate,
                         10000 + (a.nb * 7919) % 90001 AS Q1h,                    -- hundredths of kg, 100.00 to 1000.00
                         (a.nb * 31) % 1001            AS Loss2,                  -- loss in hundredths of %, 0 to 10.00 %
                         (a.nb * 37 + 11) % 1001       AS Loss3,
                         (a.nb * 41 + 23) % 1001       AS Loss4) AS b
        -- Each step keeps (100 % - loss) of the previous quantity, rounded UP to the
        -- hundredth of kg (the +9999 before the division): the loss never exceeds 10 %.
        CROSS APPLY (SELECT (b.Q1h  * (10000 - b.Loss2) + 9999) / 10000 AS Q2h) AS c2
        CROSS APPLY (SELECT (c2.Q2h * (10000 - b.Loss3) + 9999) / 10000 AS Q3h) AS c3
        CROSS APPLY (SELECT (c3.Q3h * (10000 - b.Loss4) + 9999) / 10000 AS Q4h) AS c4
        CROSS APPLY (SELECT DATEADD(MINUTE, 360 + (a.n * 13) % 300, CAST(b.HarvestDate AS DATETIME2)) AS T1) AS d1
        CROSS APPLY (SELECT DATEADD(MINUTE, 120 + (a.n * 17) % 241, d1.T1) AS T2) AS d2
        CROSS APPLY (SELECT DATEADD(MINUTE, 120 + (a.n * 19) % 241, d2.T2) AS T3) AS d3
        CROSS APPLY (SELECT DATEADD(MINUTE, 120 + (a.n * 23) % 241, d3.T3) AS T4) AS d4
        JOIN @FarmMap    AS fm ON fm.No = b.FarmNo
        JOIN @StationMap AS s1 ON s1.Kind = 'SITE' AND s1.Idx = a.n % 10 + 1
        JOIN @StationMap AS s2 ON s2.Kind = 'PCK'  AND s2.Idx = (a.n / 10) % 10 + 1
        JOIN @StationMap AS s3 ON s3.Kind = 'SHP'  AND s3.Idx = (a.n / 100) % 10 + 1
        ORDER BY a.n;

        -- 2. The batches, in batch-number order (so BatchId grows with the number).
        INSERT trace.Batch (BatchCode, FarmId, Variety, HarvestDate, QuantityKg, Status)
        SELECT l.BatchCode, l.FarmId, l.Variety, l.HarvestDate,
               CASE l.Steps WHEN 1 THEN l.Q1 WHEN 2 THEN l.Q2 WHEN 3 THEN l.Q3 ELSE l.Q4 END,
               CASE l.Steps WHEN 1 THEN N'RECEIVED' WHEN 2 THEN N'SORTED'
                            WHEN 3 THEN N'PACKED'   ELSE N'SHIPPED' END
        FROM @Lot AS l
        WHERE l.LotNo BETWEEN @From AND @To
        ORDER BY l.LotNo;

        -- 3. The movements: for each batch, the steps 1..Steps, in order.
        INSERT trace.Movement (BatchId, StationId, MovementType, QuantityKg, OccurredAt)
        SELECT b.BatchId, m.StationId, m.MovementType, m.QuantityKg, m.OccurredAt
        FROM @Lot AS l
        JOIN trace.Batch AS b ON b.BatchCode = l.BatchCode
        CROSS APPLY (VALUES (1, l.SiteId, N'RECEPTION', l.Q1, l.T1),
                            (2, l.SiteId, N'SORTING',   l.Q2, l.T2),
                            (3, l.PckId,  N'PACKING',   l.Q3, l.T3),
                            (4, l.ShpId,  N'SHIPMENT',  l.Q4, l.T4))
                     AS m (Step, StationId, MovementType, QuantityKg, OccurredAt)
        WHERE l.LotNo BETWEEN @From AND @To
          AND m.Step <= l.Steps
        ORDER BY l.LotNo, m.Step;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;   -- raise the original error again
    END CATCH;

    CHECKPOINT;   -- lets the log space be reused (recovery model SIMPLE)

    SET @FreeText = CAST(@FreeGB AS NVARCHAR(20));
    RAISERROR(N'Batches %d to %d done. Free disk space before this chunk: %s GB.',
              0, 1, @From, @To, @FreeText) WITH NOWAIT;

    SET @From = @To + 1;
END;

/* ---------- Summary ---------- */

SELECT (SELECT COUNT(*) FROM trace.Farm)              AS farms,
       (SELECT COUNT(*) FROM trace.Station)           AS stations,
       (SELECT COUNT(*) FROM trace.StationCapability) AS functions,
       (SELECT COUNT(*) FROM trace.Batch)             AS batches,
       (SELECT COUNT(*) FROM trace.Movement)          AS movements;

PRINT N'Done. Now run 008_check_volume_data.sql.';
GO
