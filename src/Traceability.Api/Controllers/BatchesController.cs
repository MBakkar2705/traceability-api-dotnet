using Microsoft.AspNetCore.Mvc;
using Traceability.Api.Models;
using Traceability.Api.Validation;
using Traceability.Data;

namespace Traceability.Api.Controllers;

[ApiController]
[Route("batches")]
public sealed class BatchesController(TraceabilityDb db) : ControllerBase
{
    /// <summary>Creates a batch (status RECEIVED) and records its first movement, a RECEPTION.</summary>
    /// <response code="201">The batch is created. The body is empty; the Location header points to the batch.</response>
    /// <response code="400">A field is missing, malformed or too long, or the time has no Z or offset (no errorCode); or the batch code is empty (errorCode 50400); or the quantity is 0 or less (errorCode 50401).</response>
    /// <response code="404">Unknown farm (errorCode 50101) or unknown station (errorCode 50102).</response>
    /// <response code="409">The batch code is already taken (errorCode 50202).</response>
    /// <response code="422">The station does not have the RECEPTION function (errorCode 50303).</response>
    [HttpPost]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> Create(
        CreateBatchRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("batchCode", request.BatchCode, CodeRules.BatchMaxLength);
        errors.RequireCode("farmCode", request.FarmCode, CodeRules.FarmMaxLength);
        errors.RequireText("variety", request.Variety, FieldLimits.VarietyMaxLength);
        errors.RequireValue("harvestDate", request.HarvestDate);
        errors.RequireQuantity("quantityKg", request.QuantityKg);
        errors.RequireCode("stationCode", request.StationCode, CodeRules.StationMaxLength);
        errors.RequireUtcTime("occurredAt", request.OccurredAt);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        await db.CreateBatchAsync(
            request.BatchCode, request.FarmCode, request.Variety, request.HarvestDate,
            request.QuantityKg, request.StationCode, ToUtc(request.OccurredAt), cancellationToken);

        // 201 with an empty body: the Location header points to the batch.
        Response.Headers["Location"] = Url.Action(nameof(Get), new { batchCode = request.BatchCode });
        return StatusCode(StatusCodes.Status201Created);
    }

    /// <summary>Lists the batches, one page at a time, with the total count of the batches that match the filters.</summary>
    /// <remarks>
    /// Batches are sorted by creation order. The two filters can be combined. The total count is
    /// computed on every call: on a very large table the call is slow (see docs/mesures.md).
    /// </remarks>
    /// <param name="status">Optional filter: RECEIVED, SORTED, PACKED or SHIPPED.</param>
    /// <param name="farmCode">Optional filter: code of a farm.</param>
    /// <param name="pageNumber">Page number, from 1. Default 1.</param>
    /// <param name="pageSize">Items per page, from 1 to 1000. Default 20.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="200">A page of batches: items, totalCount, pageNumber and pageSize. A page beyond the end has no items.</response>
    /// <response code="400">A filter is malformed or too long (no errorCode); or the status is unknown (errorCode 50403); or the page number or size is invalid (errorCode 50404).</response>
    /// <response code="404">Unknown farm (errorCode 50101).</response>
    [HttpGet]
    [ProducesResponseType<PageResponse<BatchResponse>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PageResponse<BatchResponse>>> List(
        string? status = null,
        string? farmCode = null,
        int pageNumber = Paging.DefaultPageNumber,
        int pageSize = Paging.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        // Filters are optional: their shape is checked only when they are given. For the status,
        // only the length is checked: the procedure refuses an unknown status (50403).
        var errors = new FieldErrors();
        if (farmCode is not null)
        {
            errors.RequireCode("farmCode", farmCode, CodeRules.FarmMaxLength);
        }

        if (status is not null)
        {
            errors.RequireText("status", status, FieldLimits.StatusMaxLength);
        }

        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        var page = await db.ListBatchesAsync(status, farmCode, pageNumber, pageSize, cancellationToken);
        var items = page.Items.Select(ToResponse).ToList();
        return new PageResponse<BatchResponse>(items, page.TotalCount, pageNumber, pageSize);
    }

    /// <summary>Reads a batch with its movements, in the order they were recorded.</summary>
    /// <param name="batchCode">Code of the batch.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="200">The batch and its movements. Times are in UTC and end with Z.</response>
    /// <response code="400">The code is malformed or too long (no errorCode).</response>
    /// <response code="404">Unknown batch (errorCode 50100).</response>
    [HttpGet("{batchCode}")]
    [ProducesResponseType<BatchDetailsResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<BatchDetailsResponse>> Get(
        string batchCode, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("batchCode", batchCode, CodeRules.BatchMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        var details = await db.GetBatchAsync(batchCode, cancellationToken);
        var batch = details.Batch;
        var movements = details.Movements
            .Select(m => new MovementResponse(m.MovementId, m.MovementType, m.StationCode, m.QuantityKg, m.OccurredAt))
            .ToList();
        return new BatchDetailsResponse(
            batch.BatchCode, batch.FarmCode, batch.Variety, batch.HarvestDate,
            batch.QuantityKg, batch.Status, movements);
    }

    /// <summary>Adds the next movement of a batch and updates its status and quantity.</summary>
    /// <remarks>
    /// The next step depends on the status: SORTING after RECEIVED, PACKING after SORTED,
    /// SHIPMENT after PACKED. A SHIPPED batch accepts nothing more. Two movements sent at the same
    /// time for the same batch are handled one after the other.
    /// </remarks>
    /// <param name="batchCode">Code of the batch.</param>
    /// <param name="request">The JSON body of the request.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="201">The movement is recorded. The body is empty; the Location header points to the batch.</response>
    /// <response code="400">A field is missing, malformed or too long, or the time has no Z or offset (no errorCode); or the quantity is 0 or less (errorCode 50401); or the movement type is unknown (errorCode 50402).</response>
    /// <response code="404">Unknown batch (errorCode 50100) or unknown station (errorCode 50102).</response>
    /// <response code="422">The batch is already SHIPPED (errorCode 50300); or the movement is not the next step (errorCode 50301); or the quantity is higher than the current one (errorCode 50302); or the station does not have the function (errorCode 50303).</response>
    [HttpPost("{batchCode}/movements")]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> AddMovement(
        string batchCode, AddMovementRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("batchCode", batchCode, CodeRules.BatchMaxLength);
        errors.RequireCode("stationCode", request.StationCode, CodeRules.StationMaxLength);
        errors.RequireText("movementType", request.MovementType, FieldLimits.MovementTypeMaxLength);
        errors.RequireQuantity("quantityKg", request.QuantityKg);
        errors.RequireUtcTime("occurredAt", request.OccurredAt);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        await db.AddMovementAsync(
            batchCode, request.StationCode, request.MovementType,
            request.QuantityKg, ToUtc(request.OccurredAt), cancellationToken);

        // 201 with an empty body: the Location header points to the batch.
        Response.Headers["Location"] = Url.Action(nameof(Get), new { batchCode });
        return StatusCode(StatusCodes.Status201Created);
    }

    private static BatchResponse ToResponse(BatchRow batch) =>
        new(batch.BatchCode, batch.FarmCode, batch.Variety, batch.HarvestDate, batch.QuantityKg, batch.Status);

    // A time with "Z" is already UTC. A time with an offset is converted to UTC here. A time with
    // no indication never gets here: RequireUtcTime refused it (decision of lot 3c).
    private static DateTime? ToUtc(DateTime? value) =>
        value is { } moment && moment.Kind == DateTimeKind.Local ? moment.ToUniversalTime() : value;
}
