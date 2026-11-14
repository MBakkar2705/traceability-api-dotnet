/*
  020_add_batch_correction.sql
  Lot 12b: adds the table trace.BatchCorrection (the corrections of the batch sheet: code, farm,
  variety, harvest date) to a database that already exists. A new database gets the same table
  from 002.

  - Run in SSMS in SQLCMD mode (menu Query > SQLCMD Mode). As written, DbName is
    TraceabilityDev. To run on TraceabilityTest, change the :setvar line below to
    TraceabilityTest. Do NOT save that change in the file.
  - Only TraceabilityDev and TraceabilityTest are allowed. Any other name is refused.
  - Replayable: if the table already exists, nothing is done.
  - All or nothing: one transaction, and any error rolls everything back.
  - It adds an EMPTY table and two indexes. It reads no row of the other tables and changes none:
    the batches, the movements and the other tables are not touched.
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
IF OBJECT_ID(N'trace.BatchCorrection', N'U') IS NOT NULL
BEGIN
    PRINT N'The table trace.BatchCorrection already exists. Nothing done.';
    RETURN;
END;

BEGIN TRANSACTION;

-- 7. BatchCorrection: the corrections of the batch sheet (lot 12b). Rows are added, never changed
-- or deleted. trace.Batch keeps the CURRENT values: the procedure CorrectBatch updates them in the
-- same transaction as it adds the row here. The row keeps the values before (Old...) and after
-- (New...) of the four fields: code, farm, variety and harvest date. A field that does not change
-- repeats its value in both columns. At least one field must differ; the codes and the variety
-- are compared with a binary collation, so that a change of case only (lot-1 to LOT-1) counts.
-- The old codes are kept on purpose: a batch is found by an old code when it is read (GetBatch),
-- and an old code stays reserved for the batch that had it (CorrectBatch, CreateBatch).
-- ReasonCode is DATA_ENTRY_ERROR or OTHER (then the comment is required). ReasonComment is an
-- empty text when there is no comment. The author follows the rules of trace.Movement (no default
-- value). CorrectedAt is set by the database, in UTC.
CREATE TABLE trace.BatchCorrection
(
    CorrectionId   BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_BatchCorrection PRIMARY KEY,
    BatchId        INT           NOT NULL,
    OldBatchCode   NVARCHAR(30)  NOT NULL,
    NewBatchCode   NVARCHAR(30)  NOT NULL,
    OldFarmId      INT           NOT NULL,
    NewFarmId      INT           NOT NULL,
    OldVariety     NVARCHAR(50)  NOT NULL,
    NewVariety     NVARCHAR(50)  NOT NULL,
    OldHarvestDate DATE          NOT NULL,
    NewHarvestDate DATE          NOT NULL,
    ReasonCode     NVARCHAR(20)  NOT NULL,
    ReasonComment  NVARCHAR(500) NOT NULL,
    AuthorId       NVARCHAR(64)  NOT NULL,
    AuthorName     NVARCHAR(100) NOT NULL,
    CorrectedAt    DATETIME2     NOT NULL
        CONSTRAINT DF_BatchCorrection_CorrectedAt DEFAULT SYSUTCDATETIME(),   -- UTC

    CONSTRAINT FK_BatchCorrection_Batch FOREIGN KEY (BatchId) REFERENCES trace.Batch (BatchId),
    CONSTRAINT FK_BatchCorrection_OldFarm FOREIGN KEY (OldFarmId) REFERENCES trace.Farm (FarmId),
    CONSTRAINT FK_BatchCorrection_NewFarm FOREIGN KEY (NewFarmId) REFERENCES trace.Farm (FarmId),
    CONSTRAINT CK_BatchCorrection_NewBatchCode_NotEmpty CHECK (LEN(TRIM(NewBatchCode)) > 0),
    CONSTRAINT CK_BatchCorrection_Something_Changed
        CHECK (OldBatchCode COLLATE Latin1_General_BIN2 <> NewBatchCode COLLATE Latin1_General_BIN2
               OR OldFarmId <> NewFarmId
               OR OldVariety COLLATE Latin1_General_BIN2 <> NewVariety COLLATE Latin1_General_BIN2
               OR OldHarvestDate <> NewHarvestDate),
    CONSTRAINT CK_BatchCorrection_ReasonCode
        CHECK (ReasonCode IN (N'DATA_ENTRY_ERROR', N'OTHER')),
    CONSTRAINT CK_BatchCorrection_Comment_Required
        CHECK (ReasonCode <> N'OTHER' OR LEN(TRIM(ReasonComment)) > 0),
    CONSTRAINT CK_BatchCorrection_AuthorId_NotEmpty CHECK (LEN(TRIM(AuthorId)) > 0),
    CONSTRAINT CK_BatchCorrection_AuthorName_NotEmpty CHECK (LEN(TRIM(AuthorName)) > 0)
);

-- The corrections of a batch are found by its BatchId (GetBatch). A batch is found by an old code
-- through OldBatchCode (GetBatch, and the reservation of old codes). Both indexes are created
-- with the table; they are not measured, the table starts empty.
CREATE INDEX IX_BatchCorrection_BatchId ON trace.BatchCorrection (BatchId);
CREATE INDEX IX_BatchCorrection_OldBatchCode ON trace.BatchCorrection (OldBatchCode);

-- Check (read only), before the transaction ends.
-- a. The columns of the new table: type, size, NULL not allowed (expected: 15 rows, all 0).
SELECT c.name AS column_name, ty.name AS type_name, c.max_length / 2 AS max_chars, c.is_nullable
FROM sys.columns AS c
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'trace.BatchCorrection')
ORDER BY c.column_id;

-- b. The constraints and the indexes of the new table.
SELECT name AS constraint_name, type_desc
FROM sys.objects
WHERE parent_object_id = OBJECT_ID(N'trace.BatchCorrection')
ORDER BY type_desc, name;

SELECT name AS index_name, type_desc
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'trace.BatchCorrection')
ORDER BY index_id;

COMMIT TRANSACTION;
PRINT N'Table trace.BatchCorrection created.';
GO
