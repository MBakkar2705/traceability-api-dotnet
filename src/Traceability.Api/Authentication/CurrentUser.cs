using System.Diagnostics.CodeAnalysis;
using System.Security.Claims;

namespace Traceability.Api.Authentication;

/// <summary>
/// The user who calls the API, as the validated token describes it (lot 11). Id is the stable
/// identifier of the account (claim sub) and Name is the user name at the time of the call (claim
/// preferred_username). Both are read from the token, never from the body of a request, and both
/// are recorded as the author of a movement.
/// </summary>
public sealed record CurrentUser(string Id, string Name)
{
    /// <summary>Name of the claim that holds the stable identifier of the account.</summary>
    public const string IdClaim = "sub";

    /// <summary>Name of the claim that holds the user name.</summary>
    public const string NameClaim = "preferred_username";

    /// <summary>
    /// Reads the user from the claims. Both claims must be there and not empty: otherwise there is
    /// no author to record and the result is false (the API then answers 403, decision D5 of
    /// lot 11). The names are those of the token: Program.cs keeps them by setting
    /// MapInboundClaims to false, otherwise the handler renames sub.
    /// </summary>
    public static bool TryRead(ClaimsPrincipal? user, [NotNullWhen(true)] out CurrentUser? current)
    {
        var id = user?.FindFirst(IdClaim)?.Value;
        var name = user?.FindFirst(NameClaim)?.Value;
        if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(name))
        {
            current = null;
            return false;
        }

        current = new CurrentUser(id, name);
        return true;
    }
}
