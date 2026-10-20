namespace Traceability.Api.Models;

// Request bodies. Every field is nullable on purpose: a missing field is detected
// by the API (400, before any procedure call), not by the JSON reader.

public sealed record CreateFarmRequest(string? Code, string? Name, string? Region);

public sealed record CreateStationRequest(string? Code, string? Name);

public sealed record AddCapabilityRequest(string? MovementType);
