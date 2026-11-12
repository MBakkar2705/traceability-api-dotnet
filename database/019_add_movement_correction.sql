/*
  019_add_movement_correction.sql
  Lot 12a: adds the table trace.MovementCorrection (the corrections of movements) to a database
  that already exists. A new database gets the same table from 002.

  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode). As written, DbName is
    TraceabilityDev. To run on TraceabilityTest, change the :setvar line below to
    TraceabilityTest. Do NOT save that change in the file.
  - Only TraceabilityDev and TraceabilityTest are allowed. Any other name is refused.
  - Replayable: if the table already exists, nothing is done.
  - All or nothing: one transaction, and any error rolls everything back.
  - It adds an EMPTY table and one index. It reads no row of the other tables and changes none:
    the movements, the batches and the other tables are not touched.
  - After this script, run 005 and then 017 again (005 recreates the old ListBatches, 017
    replaces it).
  - Contains no DROP, TRUNCATE, DELETE or UPDATE.
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

-- Replayable: do nothing if the table is already there.
IF OBJECT_ID(N'trace.MovementCorrection', N'U') IS NOT NULL
BEGIN
    PRINT N'The table trace.MovementCorrection already exists. Nothing done.';
    RETURN;
END;

BEGIN TRANSACTION;

-- 6. MovementCorrection: the corrections of movements (lot 12a). Rows are added, never changed or
-- deleted. trace.Movement itself is never changed: a correction is a new row here, and it points to
-- the movement it corrects.
--   Kind REPLACE gives the new station, quantity and time of a movement (the movement type stays
--   the same, so the step stays the same).
--   Kind CANCEL says the movement did not happen. It repeats the values of the version it cancels.
-- The valid version of a movement is its row in trace.Movement with the latest correction (highest
-- CorrectionId) applied. A movement whose latest correction is a CANCEL is cancelled for good.
-- ReasonCode is DATA_ENTRY_ERROR, MEASUREMENT_ERROR or OTHER (then the comment is required).
-- ReasonComment is an empty text when there is no comment. The author follows the rules of
-- trace.Movement (no default value). CorrectedAt is set by the database, in UTC.
-- (StationId, MovementType) is a two-column foreign key to StationCapability, like in trace.Movement.
CREATE TABLE trace.MovementCorrection
(
    CorrectionId  BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_MovementCorrection PRIMARY KEY,
    MovementId    BIGINT        NOT NULL,
    Kind          NVARCHAR(10)  NOT NULL,
    StationId     INT           NOT NULL,
    MovementType  NVARCHAR(20)  NOT NULL,
    QuantityKg    DECIMAL(10,2) NOT NULL,
    OccurredAt    DATETIME2     NOT NULL,   -- UTC
    ReasonCode    NVARCHAR(20)  NOT NULL,
    ReasonComment NVARCHAR(500) NOT NULL,
    AuthorId      NVARCHAR(64)  NOT NULL,
    AuthorName    NVARCHAR(100) NOT NULL,
    CorrectedAt   DATETIME2     NOT NULL
        CONSTRAINT DF_MovementCorrection_CorrectedAt DEFAULT SYSUTCDATETIME(),   -- UTC

    CONSTRAINT FK_MovementCorrection_Movement FOREIGN KEY (MovementId)
        REFERENCES trace.Movement (MovementId),
    CONSTRAINT FK_MovementCorrection_StationCapability FOREIGN KEY (StationId, MovementType)
        REFERENCES trace.StationCapability (StationId, MovementType),
    CONSTRAINT CK_MovementCorrection_Kind CHECK (Kind IN (N'REPLACE', N'CANCEL')),
    CONSTRAINT CK_MovementCorrection_MovementType
        CHECK (MovementType IN (N'RECEPTION', N'SORTING', N'PACKING', N'SHIPMENT')),
    CONSTRAINT CK_MovementCorrection_QuantityKg_Positive CHECK (QuantityKg > 0),
    CONSTRAINT CK_MovementCorrection_ReasonCode
        CHECK (ReasonCode IN (N'DATA_ENTRY_ERROR', N'MEASUREMENT_ERROR', N'OTHER')),
    CONSTRAINT CK_MovementCorrection_Comment_Required
        CHECK (ReasonCode <> N'OTHER' OR LEN(TRIM(ReasonComment)) > 0),
    CONSTRAINT CK_MovementCorrection_AuthorId_NotEmpty CHECK (LEN(TRIM(AuthorId)) > 0),
    CONSTRAINT CK_MovementCorrection_AuthorName_NotEmpty CHECK (LEN(TRIM(AuthorName)) > 0)
);

-- The corrections of a movement are found by its MovementId (GetBatch, ReplaceMovement,
-- CancelMovement). The index is created with the table; it is not measured, the table starts empty.
CREATE INDEX IX_MovementCorrection_MovementId ON trace.MovementCorrection (MovementId);

-- Check (read only), before the transaction ends.
-- a. The columns of the new table: type, size, NULL not allowed (expected: 12 rows, all 0).
SELECT c.name AS column_name, ty.name AS type_name, c.max_length / 2 AS max_chars, c.is_nullable
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'trace.MovementCorrection')
ORDER BY c.column_id;

-- b. The constraints and the index of the new table.
SELECT name AS constraint_name, type_desc
FROM sys.objects
WHERE parent_object_id = OBJECT_ID(N'trace.MovementCorrection')
ORDER BY type_desc, name;

SELECT name AS index_name, type_desc
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'trace.MovementCorrection')
ORDER BY index_id;

COMMIT TRANSACTION;
PRINT N'Table trace.MovementCorrection created.';
GO
