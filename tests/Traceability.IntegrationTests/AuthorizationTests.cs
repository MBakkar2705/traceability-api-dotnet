using System.Net;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Routing;

namespace Traceability.IntegrationTests;

// Lot 10b: who may call which route. The tests use the test authentication of TestAuth (no
// Keycloak, no real token): they check the rules of the roles route by route. The check of a real
// token is tried by hand (verification.md, section 19).
[Collection(ApiCollection.Name)]
public class AuthorizationTests(ApiFixture api)
{
    // The 10 routes of the API: 5 readings (GET) and 5 writings (POST). The codes in the paths do
    // not exist, and the bodies are empty: a route that lets the caller in answers 400 or 404,
    // which is neither 401 nor 403, and nothing is written.
    public static TheoryData<string, string> Routes => new()
    {
        { "GET", "/farms" },
        { "GET", "/stations" },
        { "GET", "/stations/ZZ-NONE" },
        { "GET", "/batches" },
        { "GET", "/batches/ZZ-NONE" },
        { "POST", "/farms" },
        { "POST", "/stations" },
        { "POST", "/stations/ZZ-NONE/capabilities" },
        { "POST", "/batches" },
        { "POST", "/batches/ZZ-NONE/movements" },
    };

    private static async Task<HttpStatusCode> SendAsync(HttpClient client, string method, string url)
    {
        using var request = new HttpRequestMessage(new HttpMethod(method), url);
        if (method == "POST")
        {
            request.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        }

        using var response = await client.SendAsync(request);
        return response.StatusCode;
    }

    private static void AssertLetIn(HttpStatusCode status)
    {
        Assert.NotEqual(HttpStatusCode.Unauthorized, status);
        Assert.NotEqual(HttpStatusCode.Forbidden, status);
    }

    [Theory]
    [MemberData(nameof(Routes))]
    public async Task Without_a_token_the_route_answers_401(string method, string url)
    {
        using var client = api.CreateClient(roles: null);

        Assert.Equal(HttpStatusCode.Unauthorized, await SendAsync(client, method, url));
    }

    [Theory]
    [MemberData(nameof(Routes))]
    public async Task A_reader_may_read_and_may_not_write(string method, string url)
    {
        using var client = api.CreateClient("reader");

        var status = await SendAsync(client, method, url);

        if (method == "POST")
        {
            Assert.Equal(HttpStatusCode.Forbidden, status);
        }
        else
        {
            AssertLetIn(status);
        }
    }

    [Theory]
    [MemberData(nameof(Routes))]
    public async Task A_writer_may_read_and_write(string method, string url)
    {
        using var client = api.CreateClient("writer");

        AssertLetIn(await SendAsync(client, method, url));
    }

    [Theory]
    [MemberData(nameof(Routes))]
    public async Task A_caller_with_another_role_gets_403_everywhere(string method, string url)
    {
        using var client = api.CreateClient("other");

        Assert.Equal(HttpStatusCode.Forbidden, await SendAsync(client, method, url));
    }

    // A new route changes the number below: add it to Routes above, and give it a policy.
    [Fact]
    public void Every_route_of_the_controllers_asks_for_a_policy()
    {
        var routes = api.Factory.Services
            .GetRequiredService<EndpointDataSource>()
            .Endpoints
            .Where(endpoint => endpoint.Metadata.GetMetadata<ControllerActionDescriptor>() is not null)
            .ToList();

        Assert.Equal(10, routes.Count);

        var withoutPolicy = routes
            .Where(endpoint => !endpoint.Metadata
                .GetOrderedMetadata<IAuthorizeData>()
                .Any(rule => !string.IsNullOrEmpty(rule.Policy)))
            .Select(endpoint => endpoint.DisplayName)
            .ToList();

        Assert.Empty(withoutPolicy);
    }
}
