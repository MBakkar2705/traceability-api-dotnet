using System.Security.Claims;
using Traceability.Api.Authentication;

namespace Traceability.UnitTests;

// Lot 10b: the roles that Keycloak writes in a token (claim realm_access) become roles of the API.
// The shape below is the one observed in lot 10a (verification.md, section 18).
public class KeycloakRolesTests
{
    private const string ReaderAccess =
        """{"roles":["default-roles-traceability","offline_access","uma_authorization","reader"]}""";

    [Fact]
    public void The_roles_are_read_from_realm_access()
    {
        var roles = KeycloakRoles.ReadRoles(ReaderAccess);

        Assert.Equal(4, roles.Count);
        Assert.Contains("reader", roles);
        Assert.DoesNotContain("writer", roles);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not json")]
    [InlineData("[]")]
    [InlineData("{}")]
    [InlineData("""{"roles":"reader"}""")]
    [InlineData("""{"roles":{"reader":true}}""")]
    public void Anything_unexpected_gives_no_role(string? realmAccess)
    {
        Assert.Empty(KeycloakRoles.ReadRoles(realmAccess));
    }

    [Fact]
    public void Entries_that_are_not_text_and_empty_entries_are_ignored()
    {
        var roles = KeycloakRoles.ReadRoles("""{"roles":["reader",1,null,"","writer"]}""");

        Assert.Equal(2, roles.Count);
        Assert.Contains("reader", roles);
        Assert.Contains("writer", roles);
    }

    [Fact]
    public void A_role_that_is_repeated_counts_once()
    {
        Assert.Single(KeycloakRoles.ReadRoles("""{"roles":["reader","reader"]}"""));
    }

    private static ClaimsIdentity IdentityWith(string realmAccess) =>
        new([new Claim(KeycloakRoles.RealmAccessClaim, realmAccess, "JSON")], authenticationType: "test");

    [Fact]
    public void The_roles_become_role_claims_of_the_identity()
    {
        var identity = IdentityWith(ReaderAccess);

        KeycloakRoles.AddRoleClaims(identity);

        var user = new ClaimsPrincipal(identity);
        Assert.True(user.IsInRole("reader"));
        Assert.False(user.IsInRole("writer"));
    }

    [Fact]
    public void Adding_the_roles_twice_does_not_repeat_them()
    {
        var identity = IdentityWith(ReaderAccess);

        KeycloakRoles.AddRoleClaims(identity);
        KeycloakRoles.AddRoleClaims(identity);

        Assert.Equal(4, identity.FindAll(identity.RoleClaimType).Count());
    }

    [Fact]
    public void An_identity_without_realm_access_gets_no_role()
    {
        var identity = new ClaimsIdentity([new Claim("sub", "someone")], authenticationType: "test");

        KeycloakRoles.AddRoleClaims(identity);

        Assert.Empty(identity.FindAll(identity.RoleClaimType));
    }
}
