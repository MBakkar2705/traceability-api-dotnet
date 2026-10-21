using Microsoft.AspNetCore.Mvc;
using Traceability.Api.Models;
using Traceability.Api.Validation;
using Traceability.Data;

namespace Traceability.Api.Controllers;

[ApiController]
[Route("stations")]
public sealed class StationsController(TraceabilityDb db) : ControllerBase
{
    /// <summary>Creates a station.</summary>
    /// <response code="201">The station is created. The Location header points to it.</response>
    /// <response code="400">A field is missing or malformed or too long (no errorCode), or the code is empty (errorCode 50400).</response>
    /// <response code="409">The code is already taken (errorCode 50201).</response>
    [HttpPost]
    [ProducesResponseType<StationResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<StationResponse>> Create(
        CreateStationRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("code", request.Code, CodeRules.StationMaxLength);
        errors.RequireText("name", request.Name, FieldLimits.NameMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        var station = await db.CreateStationAsync(request.Code, request.Name, cancellationToken);
        return CreatedAtAction(
            nameof(Get),
            new { stationCode = station.Code },
            new StationResponse(station.Code, station.Name));
    }

    /// <summary>Lists the stations, one page at a time, with the total count.</summary>
    /// <param name="pageNumber">Page number, from 1. Default 1.</param>
    /// <param name="pageSize">Items per page, from 1 to 1000. Default 20.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="200">A page of stations: items, totalCount, pageNumber and pageSize.</response>
    /// <response code="400">The page number or the page size is invalid (errorCode 50404).</response>
    [HttpGet]
    [ProducesResponseType<PageResponse<StationResponse>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PageResponse<StationResponse>>> List(
        int pageNumber = Paging.DefaultPageNumber,
        int pageSize = Paging.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        var page = await db.ListStationsAsync(pageNumber, pageSize, cancellationToken);
        var items = page.Items.Select(s => new StationResponse(s.Code, s.Name)).ToList();
        return new PageResponse<StationResponse>(items, page.TotalCount, pageNumber, pageSize);
    }

    /// <summary>Reads a station with its functions, in life-cycle order.</summary>
    /// <param name="stationCode">Code of the station.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="200">The station and its functions (empty if none).</response>
    /// <response code="400">The code is malformed (no errorCode).</response>
    /// <response code="404">Unknown station (errorCode 50102).</response>
    [HttpGet("{stationCode}")]
    [ProducesResponseType<StationDetailsResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<StationDetailsResponse>> Get(
        string stationCode, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("stationCode", stationCode, CodeRules.StationMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        var station = await db.GetStationAsync(stationCode, cancellationToken);
        return new StationDetailsResponse(station.Code, station.Name, station.Capabilities);
    }

    /// <summary>Declares that a station can do one type of movement.</summary>
    /// <param name="stationCode">Code of the station.</param>
    /// <param name="request">The JSON body of the request.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="201">The function is declared. The body is empty; the Location header points to the station.</response>
    /// <response code="400">A field is missing, malformed or too long (no errorCode), or the movement type is unknown (errorCode 50402).</response>
    /// <response code="404">Unknown station (errorCode 50102).</response>
    /// <response code="409">The function is already declared for this station (errorCode 50203).</response>
    [HttpPost("{stationCode}/capabilities")]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> AddCapability(
        string stationCode, AddCapabilityRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("stationCode", stationCode, CodeRules.StationMaxLength);
        errors.RequireText("movementType", request.MovementType, FieldLimits.MovementTypeMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        await db.AddStationCapabilityAsync(stationCode, request.MovementType, cancellationToken);

        // 201 with an empty body: the Location header points to the station.
        Response.Headers["Location"] = Url.Action(nameof(Get), new { stationCode });
        return StatusCode(StatusCodes.Status201Created);
    }
}
