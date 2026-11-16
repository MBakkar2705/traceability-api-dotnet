namespace Traceability.Data;

// Plain result types returned by TraceabilityDb. They mirror the columns of the
// result tables of the stored procedures (docs/procedures.md).

public sealed record FarmRow(string Code, string Name, string Region);

public sealed record StationRow(string Code, string Name);

public sealed record StationDetailsRow(string Code, string Name, IReadOnlyList<string> Capabilities);

public sealed record PageRow<T>(IReadOnlyList<T> Items, int TotalCount);

public sealed record BatchRow(
    string BatchCode, string FarmCode, string Variety, DateOnly HarvestDate, decimal QuantityKg, string Status);

// Lot 12a: StationCode, QuantityKg and OccurredAt are the VALID values of the movement (its latest
// correction applied). The Original columns are the values first entered. IsCancelled says that the
// movement did not happen. CorrectionCount counts its corrections.
public sealed record MovementRow(
    long MovementId, string MovementType, string StationCode, decimal QuantityKg, DateTime OccurredAt,
    string AuthorName, bool IsCancelled, int CorrectionCount,
    string OriginalStationCode, decimal OriginalQuantityKg, DateTime OriginalOccurredAt);

// One row of trace.MovementCorrection: Kind is REPLACE or CANCEL. The identifier of the author is
// not read (like for the movements).
public sealed record CorrectionRow(
    long CorrectionId, long MovementId, string Kind, string MovementType, string StationCode,
    decimal QuantityKg, DateTime OccurredAt, string ReasonCode, string ReasonComment,
    string AuthorName, DateTime CorrectedAt);

// One row of trace.BatchCorrection (lot 12b): the sheet of a batch before (Old) and after (New) a
// correction. The farms are given by their code. The identifier of the author is not read (like
// for the movements).
public sealed record SheetCorrectionRow(
    long CorrectionId, string OldBatchCode, string NewBatchCode, string OldFarmCode, string NewFarmCode,
    string OldVariety, string NewVariety, DateOnly OldHarvestDate, DateOnly NewHarvestDate,
    string ReasonCode, string ReasonComment, string AuthorName, DateTime CorrectedAt);

public sealed record BatchDetailsRow(
    BatchRow Batch, IReadOnlyList<MovementRow> Movements, IReadOnlyList<CorrectionRow> Corrections,
    IReadOnlyList<SheetCorrectionRow> SheetCorrections);
