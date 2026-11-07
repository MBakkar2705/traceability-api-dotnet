using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Traceability.IntegrationTests;

/// <summary>
/// Authentication of the tests (lot 10b): no Keycloak and no real token. The header
/// X-Test-Roles lists the roles of the caller, separated by commas. Without that header, the
/// caller has no token and the API answers 401; a caller whose roles are not allowed gets 403.
/// This proves the rules of the roles route by route, not the check of a real token.
/// </summary>
public static class TestAuth
{
    public const string Scheme = "Test";

    public const string RolesHeader = "X-Test-Roles";
}

public sealed class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(TestAuth.RolesHeader, out var header))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        var claims = header.ToString()
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(role => new Claim(ClaimTypes.Role, role))
            .Append(new Claim(ClaimTypes.Name, "test-user"));

        var identity = new ClaimsIdentity(claims, TestAuth.Scheme);
        var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), TestAuth.Scheme);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
