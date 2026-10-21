using Microsoft.AspNetCore.Mvc;
using Traceability.Api.Models;
using Traceability.Api.Validation;
using Traceability.Data;

namespace Traceability.Api.Controllers;

[ApiController]
[Route("farms")]
public sealed class FarmsController(TraceabilityDb db) : ControllerBase
{
    /// <summary>Creates a farm.</summary>
    /// <response code="201">The farm is created. The body has the farm; there is no Location header (no route reads one farm).</response>
    /// <response code="400">A field is missing or malformed or too long (no errorCode), or the code is empty (errorCode 50400).</response>
    /// <response code="409">The code is already taken (errorCode 50200).</response>
    [HttpPost]
    [ProducesResponseType<FarmResponse>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<FarmResponse>> Create(
        CreateFarmRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("code", request.Code, CodeRules.FarmMaxLength);
        errors.RequireText("name", request.Name, FieldLimits.NameMaxLength);
        errors.RequireText("region", request.Region, FieldLimits.RegionMaxLength);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        var farm = await db.CreateFarmAsync(request.Code, request.Name, request.Region, cancellationToken);
        return StatusCode(StatusCodes.Status201Created, new FarmResponse(farm.Code, farm.Name, farm.Region));
    }

    /// <summary>Lists the farms, one page at a time, with the total count.</summary>
    /// <param name="pageNumber">Page number, from 1. Default 1.</param>
    /// <param name="pageSize">Items per page, from 1 to 1000. Default 20.</param>
    /// <param name="cancellationToken">Cancels the call if the client disconnects.</param>
    /// <response code="200">A page of farms: items, totalCount, pageNumber and pageSize.</response>
    /// <response code="400">The page number or the page size is invalid (errorCode 50404).</response>
    [HttpGet]
    [ProducesResponseType<PageResponse<FarmResponse>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PageResponse<FarmResponse>>> List(
        int pageNumber = Paging.DefaultPageNumber,
        int pageSize = Paging.DefaultPageSize,
        CancellationToken cancellationToken = default)
    {
        var page = await db.ListFarmsAsync(pageNumber, pageSize, cancellationToken);
        var items = page.Items.Select(f => new FarmResponse(f.Code, f.Name, f.Region)).ToList();
        return new PageResponse<FarmResponse>(items, page.TotalCount, pageNumber, pageSize);
    }
}
