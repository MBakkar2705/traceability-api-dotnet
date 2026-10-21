namespace Traceability.Data;

// Plain result types returned by TraceabilityDb. They mirror the columns of the
// result tables of the stored procedures (docs/procedures.md).

public sealed record FarmRow(string Code, string Name, string Region);

public sealed record StationRow(string Code, string Name);

public sealed record StationDetailsRow(string Code, string Name, IReadOnlyList<string> Capabilities);

public sealed record PageRow<T>(IReadOnlyList<T> Items, int TotalCount);

public sealed record BatchRow(
    string BatchCode, string FarmCode, string Variety, DateOnly HarvestDate, decimal QuantityKg, string Status);

public sealed record MovementRow(
    long MovementId, string MovementType, string StationCode, decimal QuantityKg, DateTime OccurredAt);

public sealed record BatchDetailsRow(BatchRow Batch, IReadOnlyList<MovementRow> Movements);
