/*
  002_create_schema_and_tables.sql
  Creates the schema "trace" and its 6 tables (the 5 tables of lot 1, and MovementCorrection
  of lot 12a) in the database named in DbName.
  Model: docs/modele-de-donnees.md
  Lot 11: trace.Movement also has the author columns (AuthorId, AuthorName). A database
  that already exists is brought to the same state by 018_add_movement_author.sql.
  Lot 12a: trace.MovementCorrection holds the corrections of movements. A database that
  already exists gets it from 019_add_movement_correction.sql.

  - NOT replayable on purpose: it fails if the schema or a table already exists.
  - All or nothing: everything runs in one transaction. On any error,
    nothing is created.
  - Run 001_create_database.sql first, with the same DbName.
  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode).
  - Contains no DROP, TRUNCATE or DELETE.
*/

:setvar DbName TraceabilityDev

USE $(DbName);
GO

SET XACT_ABORT ON;

-- Safety: stop if the connection is not on $(DbName).
IF DB_NAME() <> N'$(DbName)'
BEGIN
    THROW 50001, N'Wrong database. Expected $(DbName). Nothing was created.', 1;
END;

BEGIN TRANSACTION;

-- CREATE SCHEMA must be the first statement of a batch, hence EXEC.
EXEC (N'CREATE SCHEMA trace;');

-- 1. Farm
CREATE TABLE trace.Farm
(
    FarmId  INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Farm PRIMARY KEY,
    Code    NVARCHAR(20)  NOT NULL CONSTRAINT UQ_Farm_Code UNIQUE,
    Name    NVARCHAR(100) NOT NULL,
    Region  NVARCHAR(100) NOT NULL,

    CONSTRAINT CK_Farm_Code_NotEmpty CHECK (LEN(TRIM(Code)) > 0)
);

-- 2. Station
CREATE TABLE trace.Station
(
    StationId INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Station PRIMARY KEY,
    Code      NVARCHAR(20)  NOT NULL CONSTRAINT UQ_Station_Code UNIQUE,
    Name      NVARCHAR(100) NOT NULL,

    CONSTRAINT CK_Station_Code_NotEmpty CHECK (LEN(TRIM(Code)) > 0)
);

-- 3. StationCapability: what a station is allowed to do (composite primary key)
CREATE TABLE trace.StationCapability
(
    StationId    INT          NOT NULL,
    MovementType NVARCHAR(20) NOT NULL,

    CONSTRAINT PK_StationCapability PRIMARY KEY (StationId, MovementType),
    CONSTRAINT FK_StationCapability_Station FOREIGN KEY (StationId)
        REFERENCES trace.Station (StationId),
    CONSTRAINT CK_StationCapability_MovementType
        CHECK (MovementType IN (N'RECEPTION', N'SORTING', N'PACKING', N'SHIPMENT'))
);

-- 4. Batch: current state of a batch (the "photo")
CREATE TABLE trace.Batch
(
    BatchId     INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_Batch PRIMARY KEY,
    BatchCode   NVARCHAR(30)  NOT NULL CONSTRAINT UQ_Batch_BatchCode UNIQUE,
    FarmId      INT           NOT NULL,
    Variety     NVARCHAR(50)  NOT NULL,
    HarvestDate DATE          NOT NULL,
    QuantityKg  DECIMAL(10,2) NOT NULL,
    Status      NVARCHAR(20)  NOT NULL,

    CONSTRAINT FK_Batch_Farm FOREIGN KEY (FarmId) REFERENCES trace.Farm (FarmId),
    CONSTRAINT CK_Batch_BatchCode_NotEmpty CHECK (LEN(TRIM(BatchCode)) > 0),
    CONSTRAINT CK_Batch_QuantityKg_Positive CHECK (QuantityKg > 0),
    CONSTRAINT CK_Batch_Status
        CHECK (Status IN (N'RECEIVED', N'SORTED', N'PACKED', N'SHIPPED'))
);

-- 5. Movement: the journal (the "film"). Rows are added, never changed or deleted.
-- Lot 11: each row records its author, read from the validated token by the API:
-- AuthorId = stable identifier of the account (claim "sub"), AuthorName = user name at the
-- time of the entry (claim "preferred_username"). No default value: the procedures must give both.
-- (StationId, MovementType) is a two-column foreign key to StationCapability:
-- the database only accepts a movement if the station has that function.
CREATE TABLE trace.Movement
(
    MovementId   BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_Movement PRIMARY KEY,
    BatchId      INT           NOT NULL,
    StationId    INT           NOT NULL,
    MovementType NVARCHAR(20)  NOT NULL,
    QuantityKg   DECIMAL(10,2) NOT NULL,
    OccurredAt   DATETIME2     NOT NULL,   -- UTC
    AuthorId     NVARCHAR(64)  NOT NULL,
    AuthorName   NVARCHAR(100) NOT NULL,

    CONSTRAINT FK_Movement_Batch FOREIGN KEY (BatchId) REFERENCES trace.Batch (BatchId),
    CONSTRAINT FK_Movement_StationCapability FOREIGN KEY (StationId, MovementType)
        REFERENCES trace.StationCapability (StationId, MovementType),
    CONSTRAINT CK_Movement_MovementType
        CHECK (MovementType IN (N'RECEPTION', N'SORTING', N'PACKING', N'SHIPMENT')),
    CONSTRAINT CK_Movement_QuantityKg_Positive CHECK (QuantityKg > 0),
    CONSTRAINT CK_Movement_AuthorId_NotEmpty CHECK (LEN(TRIM(AuthorId)) > 0),
    CONSTRAINT CK_Movement_AuthorName_NotEmpty CHECK (LEN(TRIM(AuthorName)) > 0)
);

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

COMMIT TRANSACTION;

PRINT N'Schema trace and 6 tables created.';
GO

-- Check (read only): the 6 tables of the schema trace.
SELECT s.name AS schema_name, t.name AS table_name
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = N'trace'
ORDER BY t.name;
GO
