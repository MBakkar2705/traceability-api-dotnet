using Microsoft.AspNetCore.Mvc;
using Traceability.Api.Models;
using Traceability.Api.Validation;
using Traceability.Data;

namespace Traceability.Api.Controllers;

[ApiController]
[Route("farms")]
public sealed class FarmsController(TraceabilityDb db) : ControllerBase
{
    [HttpPost]
    public async Task<ActionResult<FarmResponse>> Create(
        CreateFarmRequest request, CancellationToken cancellationToken)
    {
        var errors = new FieldErrors();
        errors.RequireCode("code", request.Code, CodeRules.FarmMaxLength);
        errors.RequireValue("name", request.Name);
        errors.RequireValue("region", request.Region);
        if (errors.HasErrors)
        {
            errors.ApplyTo(ModelState);
            return ValidationProblem();
        }

        var farm = await db.CreateFarmAsync(request.Code, request.Name, request.Region, cancellationToken);
        return StatusCode(StatusCodes.Status201Created, new FarmResponse(farm.Code, farm.Name, farm.Region));
    }

    [HttpGet]
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
