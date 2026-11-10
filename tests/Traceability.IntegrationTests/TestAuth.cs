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
/// Lot 11: the caller also has an identity, as a real token has it: the claims sub and
/// preferred_username, given by the headers X-Test-UserId and X-Test-UserName (default values
/// if absent). The header X-Test-NoIdentity gives a valid caller without these two claims.
/// </summary>
public static class TestAuth
{
    public const string Scheme = "Test";

    public const string RolesHeader = "X-Test-Roles";

    /// <summary>Identifier of the account (claim sub). Without the header: DefaultUserId.</summary>
    public const string UserIdHeader = "X-Test-UserId";

    /// <summary>User name (claim preferred_username). Without the header: DefaultUserName.</summary>
    public const string UserNameHeader = "X-Test-UserName";

    /// <summary>With this header, the caller has neither sub nor preferred_username.</summary>
    public const string NoIdentityHeader = "X-Test-NoIdentity";

    public const string DefaultUserId = "test-user-id";

    public const string DefaultUserName = "test-user";
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
            .Append(new Claim(ClaimTypes.Name, "test-user"))
            .ToList();

        // The names of the two claims are written out here on purpose, not taken from CurrentUser:
        // a wrong name in the API would otherwise be copied here and stay hidden.
        if (!Request.Headers.ContainsKey(TestAuth.NoIdentityHeader))
        {
            claims.Add(new Claim("sub", HeaderOrDefault(TestAuth.UserIdHeader, TestAuth.DefaultUserId)));
            claims.Add(new Claim(
                "preferred_username", HeaderOrDefault(TestAuth.UserNameHeader, TestAuth.DefaultUserName)));
        }

        var identity = new ClaimsIdentity(claims, TestAuth.Scheme);
        var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), TestAuth.Scheme);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }

    private string HeaderOrDefault(string name, string fallback) =>
        Request.Headers.TryGetValue(name, out var value) && !string.IsNullOrWhiteSpace(value)
            ? value.ToString()
            : fallback;
}
