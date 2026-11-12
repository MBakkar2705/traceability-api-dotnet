namespace Traceability.Api.Models;

// Response bodies. JSON field names are camelCase (code, name, totalCount, ...).

public sealed record FarmResponse(string Code, string Name, string Region);

public sealed record StationResponse(string Code, string Name);

public sealed record StationDetailsResponse(string Code, string Name, IReadOnlyList<string> Capabilities);

public sealed record PageResponse<T>(IReadOnlyList<T> Items, int TotalCount, int PageNumber, int PageSize);

public sealed record BatchResponse(
    string BatchCode, string FarmCode, string Variety, DateOnly HarvestDate, decimal QuantityKg, string Status);

// AuthorName is the user name at the time of the entry (lot 11). The identifier of the author is
// never returned. Lot 12a: StationCode, QuantityKg and OccurredAt are the VALID values (the latest
// correction applied); the Original fields are the values first entered. IsCancelled says that the
// movement did not happen; a cancelled movement stays in the list.
public sealed record MovementResponse(
    long MovementId, string MovementType, string StationCode, decimal QuantityKg, DateTime OccurredAt,
    string AuthorName, bool IsCancelled, int CorrectionCount,
    string OriginalStationCode, decimal OriginalQuantityKg, DateTime OriginalOccurredAt);

// One correction of a movement (lot 12a). Kind is REPLACE or CANCEL; a CANCEL repeats the values of
// the version it cancels. AuthorName is the name of the supervisor at the time of the correction.
public sealed record CorrectionResponse(
    long CorrectionId, long MovementId, string Kind, string MovementType, string StationCode,
    decimal QuantityKg, DateTime OccurredAt, string ReasonCode, string ReasonComment,
    string AuthorName, DateTime CorrectedAt);

public sealed record BatchDetailsResponse(
    string BatchCode, string FarmCode, string Variety, DateOnly HarvestDate, decimal QuantityKg,
    string Status, IReadOnlyList<MovementResponse> Movements, IReadOnlyList<CorrectionResponse> Corrections);
