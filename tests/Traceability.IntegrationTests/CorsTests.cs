using System.Net;

namespace Traceability.IntegrationTests;

// Lot 4a: the CORS policy of the API (development only) for the web interface served by the
// Vite development server. A browser hides an answer from a page unless the header
// Access-Control-Allow-Origin names the origin of that page; these tests read that header
// on real answers. The API still executes the request: CORS is enforced by the browser.
[Collection(ApiCollection.Name)]
public class CorsTests(ApiFixture api)
{
    private const string WebUiOrigin = "http://localhost:5173";

    private HttpClient Client => api.Client;

    private static HttpRequestMessage Request(HttpMethod method, string url, string? origin)
    {
        var request = new HttpRequestMessage(method, url);
        if (origin is not null)
        {
            request.Headers.Add("Origin", origin);
        }

        return request;
    }

    private static string? AllowOrigin(HttpResponseMessage response) =>
        response.Headers.TryGetValues("Access-Control-Allow-Origin", out var values) ? values.Single() : null;

    [Fact]
    public async Task The_web_interface_origin_gets_the_allow_origin_header()
    {
        var response = await Client.SendAsync(Request(HttpMethod.Get, "/farms", WebUiOrigin));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(WebUiOrigin, AllowOrigin(response));
    }

    [Fact]
    public async Task Another_origin_gets_no_allow_origin_header()
    {
        var response = await Client.SendAsync(Request(HttpMethod.Get, "/farms", "http://localhost:5174"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(AllowOrigin(response));
    }

    [Fact]
    public async Task A_request_without_origin_gets_no_allow_origin_header()
    {
        var response = await Client.SendAsync(Request(HttpMethod.Get, "/farms", origin: null));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Null(AllowOrigin(response));
    }

    // The errors of the stored procedures are written by the exception handler. If it dropped
    // the CORS header, the browser would hide "batch not found" from the web interface.
    [Fact]
    public async Task An_error_written_by_the_exception_handler_keeps_the_allow_origin_header()
    {
        var response = await Client.SendAsync(Request(HttpMethod.Get, "/batches/" + TestData.NewCode(), WebUiOrigin));

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50100);
        Assert.Equal(WebUiOrigin, AllowOrigin(response));
    }

    // Lot 4b: the web interface writes with POST and a JSON body. The browser then asks first
    // (preflight): it sends OPTIONS with the method and the headers it wants to use, reads the
    // answer, and sends the real request only if the policy allows both.
    private static HttpRequestMessage Preflight(string method, string? headers = null)
    {
        var request = Request(HttpMethod.Options, "/farms", WebUiOrigin);
        request.Headers.Add("Access-Control-Request-Method", method);
        if (headers is not null)
        {
            request.Headers.Add("Access-Control-Request-Headers", headers);
        }

        return request;
    }

    // The values of a header written as a comma separated list (Allow-Methods, Allow-Headers).
    private static string[] ListedValues(HttpResponseMessage response, string name) =>
        response.Headers.TryGetValues(name, out var values)
            ? values.SelectMany(v => v.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)).ToArray()
            : [];

    [Fact]
    public async Task A_preflight_for_POST_with_Content_Type_allows_both()
    {
        var response = await Client.SendAsync(Preflight("POST", "content-type"));

        Assert.Equal(WebUiOrigin, AllowOrigin(response));
        Assert.Contains("POST", ListedValues(response, "Access-Control-Allow-Methods"));
        Assert.Contains(
            ListedValues(response, "Access-Control-Allow-Headers"),
            header => string.Equals(header, "content-type", StringComparison.OrdinalIgnoreCase));
    }

    // The policy opens GET and POST and nothing else: an open policy would pass the test above too.
    [Fact]
    public async Task A_preflight_does_not_list_PUT_or_DELETE()
    {
        var response = await Client.SendAsync(Preflight("DELETE"));

        var methods = ListedValues(response, "Access-Control-Allow-Methods");
        Assert.DoesNotContain("PUT", methods);
        Assert.DoesNotContain("DELETE", methods);
    }

    [Fact]
    public async Task A_POST_from_the_web_interface_origin_gets_the_allow_origin_header()
    {
        var request = Request(HttpMethod.Post, "/farms", WebUiOrigin);
        request.Content = TestData.Json($$"""{"code":"{{TestData.NewCode()}}","name":"Test farm","region":"Region A"}""");

        var response = await Client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(WebUiOrigin, AllowOrigin(response));
    }

    // The errors by field of a POST are read by the page: if the 400 dropped the header, the
    // browser would hide them and the form could not show them.
    [Fact]
    public async Task A_POST_refused_with_400_keeps_the_allow_origin_header()
    {
        var request = Request(HttpMethod.Post, "/farms", WebUiOrigin);
        request.Content = TestData.Json("{}");

        var response = await Client.SendAsync(request);

        await TestData.AssertShapeErrorAsync(response, "code", "name", "region");
        Assert.Equal(WebUiOrigin, AllowOrigin(response));
    }
}
