namespace Traceability.Api.Models;

// Request bodies. Every field is nullable on purpose: a missing field is detected
// by the API (400, before any procedure call), not by the JSON reader.

/// <summary>The body of POST /farms.</summary>
/// <param name="Code">Readable code of the farm: letters A-Z, digits, '-' and '_', at most 20 characters.</param>
/// <param name="Name">Name of the farm, at most 100 characters.</param>
/// <param name="Region">Region of the farm, at most 100 characters.</param>
public sealed record CreateFarmRequest(string? Code, string? Name, string? Region);

/// <summary>The body of POST /stations.</summary>
/// <param name="Code">Readable code of the station: letters A-Z, digits, '-' and '_', at most 20 characters.</param>
/// <param name="Name">Name of the station, at most 100 characters.</param>
public sealed record CreateStationRequest(string? Code, string? Name);

/// <summary>The body of POST /stations/{stationCode}/capabilities.</summary>
/// <param name="MovementType">RECEPTION, SORTING, PACKING or SHIPMENT (upper or lower case), at most 20 characters.</param>
public sealed record AddCapabilityRequest(string? MovementType);

/// <summary>The body of POST /batches.</summary>
/// <param name="BatchCode">Readable code of the new batch: letters A-Z, digits, '-' and '_', at most 30 characters.</param>
/// <param name="FarmCode">Code of the farm that harvested the batch, at most 20 characters.</param>
/// <param name="Variety">Tomato variety, at most 50 characters.</param>
/// <param name="HarvestDate">Harvest day, written like 2026-10-14 (a day, no time).</param>
/// <param name="QuantityKg">Quantity in kilograms: more than 0, at most 2 decimals, at most 99999999.99.</param>
/// <param name="StationCode">Code of the station that received the batch. It must have the RECEPTION function.</param>
/// <param name="OccurredAt">Time of the reception, always in UTC: it must end with Z (for example 2026-10-14T06:00:00Z) or carry an offset. A time with no indication is refused.</param>
public sealed record CreateBatchRequest(
    string? BatchCode, string? FarmCode, string? Variety, DateOnly? HarvestDate,
    decimal? QuantityKg, string? StationCode, DateTime? OccurredAt);

/// <summary>The body of POST /batches/{batchCode}/movements.</summary>
/// <param name="StationCode">Code of the station where the movement happens. It must have the function of the movement.</param>
/// <param name="MovementType">The next step of the batch: SORTING after RECEIVED, PACKING after SORTED, SHIPMENT after PACKED.</param>
/// <param name="QuantityKg">Quantity in kilograms after the movement: more than 0, at most 2 decimals, never more than the current quantity of the batch.</param>
/// <param name="OccurredAt">Time of the movement, always in UTC: it must end with Z (for example 2026-10-14T08:00:00Z) or carry an offset. A time with no indication is refused.</param>
public sealed record AddMovementRequest(
    string? StationCode, string? MovementType, decimal? QuantityKg, DateTime? OccurredAt);
