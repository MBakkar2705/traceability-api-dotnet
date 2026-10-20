using Microsoft.AspNetCore.Mvc;
using Traceability.Api.Models;
using Traceability.Api.Validation;
using Traceability.Data;

namespace Traceability.Api.Controllers;

[ApiController]
[Route("stations")]
public sealed class StationsController(TraceabilityDb db) : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<StationResponse>> Create(
        CreateStationRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("code", request.Code, CodeRules.StationMaxLength);
        errors.RequireValue("name", request.Name);
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

    [HttpGet]
    public async Task<ActionResult<PageResponse<StationResponse>>> List(
        int pageNumber = Paging.DefaultPageNumber,
        int pageSize = Paging.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        var page = await db.ListStationsAsync(pageNumber, pageSize, cancellationToken);
        var items = page.Items.Select(s => new StationResponse(s.Code, s.Name)).ToList();
        return new PageResponse<StationResponse>(items, page.TotalCount, pageNumber, pageSize);
    }

    [HttpGet("{stationCode}")]
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

    [HttpPost("{stationCode}/capabilities")]
    public async Task<IActionResult> AddCapability(
        string stationCode, AddCapabilityRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("stationCode", stationCode, CodeRules.StationMaxLength);
        errors.RequireValue("movementType", request.MovementType);
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
