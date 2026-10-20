namespace Traceability.Api.Models;

// Response bodies. JSON field names are camelCase (code, name, totalCount, ...).

public sealed record FarmResponse(string Code, string Name, string Region);

public sealed record StationResponse(string Code, string Name);

public sealed record StationDetailsResponse(string Code, string Name, IReadOnlyList<string> Capabilities);

public sealed record PageResponse<T>(IReadOnlyList<T> Items, int TotalCount, int PageNumber, int PageSize);
