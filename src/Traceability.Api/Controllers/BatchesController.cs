using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Traceability.Api.Authentication;
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
    /// <response code="401">No valid token.</response>
    /// <response code="403">The token does not have the role writer; or it does not give the claims sub and preferred_username, so the author of the movement is unknown.</response>
    [HttpPost]
    [Authorize(Policy = Policies.CanWrite)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> Create(
        CreateBatchRequest request, CancellationToken cancellationToken)
    {
        if (!CurrentUser.TryRead(User, out var author))
        {
            return AuthorUnknown();
        }

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
            request.QuantityKg, request.StationCode, ToUtc(request.OccurredAt),
            author.Id, author.Name, cancellationToken);

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
    /// <response code="401">No valid token.</response>
    /// <response code="403">The token has none of the roles reader, writer and supervisor.</response>
    [HttpGet]
    [Authorize(Policy = Policies.CanRead)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
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

    /// <summary>Reads a batch with its movements, in the order they were recorded, and the corrections of these movements.</summary>
    /// <remarks>
    /// Each movement carries the name of its author and its VALID values (its latest correction
    /// applied); the original values are given next to them. A cancelled movement stays in the list
    /// with isCancelled true. The corrections are listed in the order they were made.
    /// </remarks>
    /// <param name="batchCode">Code of the batch.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="200">The batch, its movements and its corrections. Times are in UTC and end with Z.</response>
    /// <response code="400">The code is malformed or too long (no errorCode).</response>
    /// <response code="404">Unknown batch (errorCode 50100).</response>
    /// <response code="401">No valid token.</response>
    /// <response code="403">The token has none of the roles reader, writer and supervisor.</response>
    [HttpGet("{batchCode}")]
    [Authorize(Policy = Policies.CanRead)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
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
            .Select(m => new MovementResponse(
                m.MovementId, m.MovementType, m.StationCode, m.QuantityKg, m.OccurredAt, m.AuthorName,
                m.IsCancelled, m.CorrectionCount,
                m.OriginalStationCode, m.OriginalQuantityKg, m.OriginalOccurredAt))
            .ToList();
        var corrections = details.Corrections
            .Select(c => new CorrectionResponse(
                c.CorrectionId, c.MovementId, c.Kind, c.MovementType, c.StationCode,
                c.QuantityKg, c.OccurredAt, c.ReasonCode, c.ReasonComment, c.AuthorName, c.CorrectedAt))
            .ToList();
        return new BatchDetailsResponse(
            batch.BatchCode, batch.FarmCode, batch.Variety, batch.HarvestDate,
            batch.QuantityKg, batch.Status, movements, corrections);
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
    /// <response code="401">No valid token.</response>
    /// <response code="403">The token does not have the role writer; or it does not give the claims sub and preferred_username, so the author of the movement is unknown.</response>
    [HttpPost("{batchCode}/movements")]
    [Authorize(Policy = Policies.CanWrite)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> AddMovement(
        string batchCode, AddMovementRequest request, CancellationToken cancellationToken)
    {
        if (!CurrentUser.TryRead(User, out var author))
        {
            return AuthorUnknown();
        }

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
            request.QuantityKg, ToUtc(request.OccurredAt), author.Id, author.Name, cancellationToken);

        // 201 with an empty body: the Location header points to the batch.
        Response.Headers["Location"] = Url.Action(nameof(Get), new { batchCode });
        return StatusCode(StatusCodes.Status201Created);
    }

    /// <summary>Replaces the values of a movement (station, quantity, time) and keeps the original.</summary>
    /// <remarks>
    /// Lot 12a. The movement itself is never changed: a correction is recorded next to it, with the
    /// reason and the supervisor who made it. The movement keeps its type. The quantity must not go
    /// above the previous valid step nor below the next valid step (an equal quantity is accepted).
    /// A cancelled movement cannot be corrected. A SHIPPED batch can be corrected too. When the last
    /// valid movement is corrected, the quantity of the batch follows. The new values must differ
    /// from the current ones.
    /// </remarks>
    /// <param name="batchCode">Code of the batch.</param>
    /// <param name="movementId">Identifier of the movement, as returned by GET /batches/{batchCode}.</param>
    /// <param name="request">The JSON body of the request.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="201">The correction is recorded. The body is empty; the Location header points to the batch.</response>
    /// <response code="400">A field is missing, malformed or too long, or the time has no Z or offset (no errorCode); or the quantity is 0 or less (errorCode 50401); or the reason is unknown (errorCode 50407); or the reason is OTHER without a comment (errorCode 50408); or the comment is too long (errorCode 50409).</response>
    /// <response code="404">Unknown batch (errorCode 50100), unknown station (errorCode 50102), or the movement is not in this batch (errorCode 50103).</response>
    /// <response code="422">The station does not have the function of the movement (errorCode 50303); or the quantity is higher than the previous step or lower than the next step (errorCode 50304); or the movement is cancelled (errorCode 50305); or the new values are the same as the current ones (errorCode 50308).</response>
    /// <response code="401">No valid token.</response>
    /// <response code="403">The token does not have the role supervisor; or it does not give the claims sub and preferred_username, so the author of the correction is unknown.</response>
    [HttpPost("{batchCode}/movements/{movementId}/replace")]
    [Authorize(Policy = Policies.CanCorrect)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> ReplaceMovement(
        string batchCode, long movementId, ReplaceMovementRequest request, CancellationToken cancellationToken)
    {
        if (!CurrentUser.TryRead(User, out var author))
        {
            return AuthorUnknown();
        }

        var errors = new FieldErrors();
        errors.RequireCode("batchCode", batchCode, CodeRules.BatchMaxLength);
        errors.RequireCode("stationCode", request.StationCode, CodeRules.StationMaxLength);
        errors.RequireQuantity("quantityKg", request.QuantityKg);
        errors.RequireUtcTime("occurredAt", request.OccurredAt);
        errors.RequireText("reasonCode", request.ReasonCode, FieldLimits.ReasonCodeMaxLength);
        errors.OptionalText("reasonComment", request.ReasonComment, FieldLimits.ReasonCommentMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        await db.ReplaceMovementAsync(
            batchCode, movementId, request.StationCode, request.QuantityKg, ToUtc(request.OccurredAt),
            request.ReasonCode, request.ReasonComment, author.Id, author.Name, cancellationToken);

        // 201 with an empty body: the Location header points to the batch.
        Response.Headers["Location"] = Url.Action(nameof(Get), new { batchCode });
        return StatusCode(StatusCodes.Status201Created);
    }

    /// <summary>Says that a movement did not happen. The movement stays in the journal, marked as cancelled.</summary>
    /// <remarks>
    /// Lot 12a. Only the last valid movement of a batch can be cancelled, and never its RECEPTION (a
    /// batch is never deleted). The batch goes back to the status and the quantity of the step
    /// before. A SHIPPED batch can be corrected too. A cancelled movement stays cancelled.
    /// </remarks>
    /// <param name="batchCode">Code of the batch.</param>
    /// <param name="movementId">Identifier of the movement, as returned by GET /batches/{batchCode}.</param>
    /// <param name="request">The JSON body of the request.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="201">The cancellation is recorded. The body is empty; the Location header points to the batch.</response>
    /// <response code="400">A field is missing, malformed or too long (no errorCode); or the reason is unknown (errorCode 50407); or the reason is OTHER without a comment (errorCode 50408); or the comment is too long (errorCode 50409).</response>
    /// <response code="404">Unknown batch (errorCode 50100), or the movement is not in this batch (errorCode 50103).</response>
    /// <response code="422">The movement is already cancelled (errorCode 50305); or it is not the last valid movement (errorCode 50306); or it is the RECEPTION (errorCode 50307).</response>
    /// <response code="401">No valid token.</response>
    /// <response code="403">The token does not have the role supervisor; or it does not give the claims sub and preferred_username, so the author of the correction is unknown.</response>
    [HttpPost("{batchCode}/movements/{movementId}/cancel")]
    [Authorize(Policy = Policies.CanCorrect)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> CancelMovement(
        string batchCode, long movementId, CancelMovementRequest request, CancellationToken cancellationToken)
    {
        if (!CurrentUser.TryRead(User, out var author))
        {
            return AuthorUnknown();
        }

        var errors = new FieldErrors();
        errors.RequireCode("batchCode", batchCode, CodeRules.BatchMaxLength);
        errors.RequireText("reasonCode", request.ReasonCode, FieldLimits.ReasonCodeMaxLength);
        errors.OptionalText("reasonComment", request.ReasonComment, FieldLimits.ReasonCommentMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        await db.CancelMovementAsync(
            batchCode, movementId, request.ReasonCode, request.ReasonComment,
            author.Id, author.Name, cancellationToken);

        // 201 with an empty body: the Location header points to the batch.
        Response.Headers["Location"] = Url.Action(nameof(Get), new { batchCode });
        return StatusCode(StatusCodes.Status201Created);
    }

    // Decision D5 of lot 11: a valid token that does not give sub or preferred_username cannot write
    // a movement, because there would be no author to record. 403, not 401: the token is valid.
    private ObjectResult AuthorUnknown() =>
        Problem(
            detail: "The token does not give the identity of the user (claims sub and preferred_username).",
            statusCode: StatusCodes.Status403Forbidden);

    private static BatchResponse ToResponse(BatchRow batch) =>
        new(batch.BatchCode, batch.FarmCode, batch.Variety, batch.HarvestDate, batch.QuantityKg, batch.Status);

    // A time with "Z" is already UTC. A time with an offset is converted to UTC here. A time with
    // no indication never gets here: RequireUtcTime refused it (decision of lot 3c).
    private static DateTime? ToUtc(DateTime? value) =>
        value is { } moment && moment.Kind == DateTimeKind.Local ? moment.ToUniversalTime() : value;
}
