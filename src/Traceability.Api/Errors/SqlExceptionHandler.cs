using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

namespace Traceability.Api.Errors;

/// <summary>
/// Catches SQL errors raised by the stored procedures and answers with Problem Details
/// plus an "errorCode" field. Unexpected SQL errors answer 500 with a generic text;
/// the real error goes to the server log. Other exceptions are left to the default handler.
/// </summary>
public sealed class SqlExceptionHandler(
    IProblemDetailsService problemDetailsService,
    ILogger<SqlExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is not SqlException sqlException)
        {
            return false;
        }

        var error = SqlErrorTranslator.Translate(sqlException.Number, sqlException.Message);

        if (error.Status == StatusCodes.Status500InternalServerError)
        {
            logger.LogError(sqlException, "Unexpected SQL error (number {Number}).", sqlException.Number);
        }

        var problem = new ProblemDetails
        {
            Status = error.Status,
            Title = TitleFor(error.Status),
            Detail = error.Detail,
        };

        if (error.ErrorCode is int errorCode)
        {
            problem.Extensions["errorCode"] = errorCode;
        }

        httpContext.Response.StatusCode = error.Status;

        return await problemDetailsService.TryWriteAsync(new ProblemDetailsContext
        {
            HttpContext = httpContext,
            Exception = exception,
            ProblemDetails = problem,
        });
    }

    private static string TitleFor(int status) => status switch
    {
        400 => "Bad Request",
        404 => "Not Found",
        409 => "Conflict",
        422 => "Unprocessable Entity",
        _ => "Internal Server Error",
    };
}
