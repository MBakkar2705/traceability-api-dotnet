using System.Security.Claims;
using System.Text.Json;

namespace Traceability.Api.Authentication;

/// <summary>
/// Keycloak writes the roles of a realm in the token under realm_access, as a JSON object:
/// {"roles": ["reader", ...]} (observed in lot 10a). ASP.NET Core does not read that shape as
/// roles by itself, so the roles are copied into role claims once the token is validated.
/// </summary>
public static class KeycloakRoles
{
    /// <summary>Name of the claim of the token that holds the realm roles.</summary>
    public const string RealmAccessClaim = "realm_access";

    /// <summary>
    /// Reads the roles from the JSON text of the claim realm_access. Anything unexpected (no text,
    /// not JSON, no "roles", "roles" that is not a list, entries that are not text) gives no
    /// role: a caller is never given a role by mistake.
    /// </summary>
    public static IReadOnlyList<string> ReadRoles(string? realmAccessJson)
    {
        if (string.IsNullOrWhiteSpace(realmAccessJson))
        {
            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(realmAccessJson);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("roles", out var roles)
                || roles.ValueKind != JsonValueKind.Array)
            {
                return [];
            }

            return roles.EnumerateArray()
                .Where(role => role.ValueKind == JsonValueKind.String)
                .Select(role => role.GetString()!)
                .Where(role => role.Length > 0)
                .Distinct()
                .ToList();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    /// <summary>
    /// Adds a role claim, of the role type of the identity, for each role found in the claim
    /// realm_access. A role that is already there is not added twice.
    /// </summary>
    public static void AddRoleClaims(ClaimsIdentity identity)
    {
        foreach (var realmAccess in identity.FindAll(RealmAccessClaim).ToList())
        {
            foreach (var role in ReadRoles(realmAccess.Value))
            {
                if (!identity.HasClaim(identity.RoleClaimType, role))
                {
                    identity.AddClaim(new Claim(identity.RoleClaimType, role));
                }
            }
        }
    }
}
