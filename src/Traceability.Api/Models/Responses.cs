namespace Traceability.Api.Models;

// Response bodies. JSON field names are camelCase (code, name, totalCount, ...).

public sealed record FarmResponse(string Code, string Name, string Region);

public sealed record StationResponse(string Code, string Name);

public sealed record StationDetailsResponse(string Code, string Name, IReadOnlyList<string> Capabilities);

public sealed record PageResponse<T>(IReadOnlyList<T> Items, int TotalCount, int PageNumber, int PageSize);

public sealed record BatchResponse(
    string BatchCode, string FarmCode, string Variety, DateOnly HarvestDate, decimal QuantityKg, string Status);

// AuthorName is the user name at the time of the entry (lot 11). The identifier of the author is
// never returned.
public sealed record MovementResponse(
    long MovementId, string MovementType, string StationCode, decimal QuantityKg, DateTime OccurredAt,
    string AuthorName);

public sealed record BatchDetailsResponse(
    string BatchCode, string FarmCode, string Variety, DateOnly HarvestDate, decimal QuantityKg,
    string Status, IReadOnlyList<MovementResponse> Movements);
