using System.Security.Claims;
using Traceability.Api.Authentication;

namespace Traceability.UnitTests;

// Lot 11: the author of a movement is read from the validated token: the claims sub (stable
// identifier of the account) and preferred_username (user name). Without both, there is no author.
public class CurrentUserTests
{
    private static ClaimsPrincipal Principal(params (string Type, string Value)[] claims) =>
        new(new ClaimsIdentity(claims.Select(c => new Claim(c.Type, c.Value)), authenticationType: "test"));

    [Fact]
    public void The_user_is_read_from_sub_and_preferred_username()
    {
        var principal = Principal(("sub", "account-1"), ("preferred_username", "writer-test"));

        var found = CurrentUser.TryRead(principal, out var user);

        Assert.True(found);
        Assert.NotNull(user);
        Assert.Equal("account-1", user.Id);
        Assert.Equal("writer-test", user.Name);
    }

    [Fact]
    public void The_names_of_the_two_claims_are_those_of_the_token()
    {
        Assert.Equal("sub", CurrentUser.IdClaim);
        Assert.Equal("preferred_username", CurrentUser.NameClaim);
    }

    [Fact]
    public void Without_sub_there_is_no_user()
    {
        var found = CurrentUser.TryRead(Principal(("preferred_username", "writer-test")), out var user);

        Assert.False(found);
        Assert.Null(user);
    }

    [Fact]
    public void Without_preferred_username_there_is_no_user()
    {
        var found = CurrentUser.TryRead(Principal(("sub", "account-1")), out var user);

        Assert.False(found);
        Assert.Null(user);
    }

    [Theory]
    [InlineData("", "writer-test")]
    [InlineData("   ", "writer-test")]
    [InlineData("account-1", "")]
    [InlineData("account-1", "   ")]
    public void An_empty_or_blank_value_gives_no_user(string id, string name)
    {
        var found = CurrentUser.TryRead(Principal(("sub", id), ("preferred_username", name)), out var user);

        Assert.False(found);
        Assert.Null(user);
    }

    // If the handler had renamed sub (to NameIdentifier), the API would not find it: the field
    // is read by its name in the token, never by another name.
    [Fact]
    public void A_renamed_identifier_is_not_accepted()
    {
        var principal = Principal((ClaimTypes.NameIdentifier, "account-1"), ("preferred_username", "writer-test"));

        var found = CurrentUser.TryRead(principal, out var user);

        Assert.False(found);
        Assert.Null(user);
    }

    [Fact]
    public void No_principal_gives_no_user()
    {
        var found = CurrentUser.TryRead(null, out var user);

        Assert.False(found);
        Assert.Null(user);
    }
}
