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

    // Lot 4a allows GET only. Before a POST the browser asks first (preflight). Observed: the API
    // answers with the allowed origin and the methods of its policy (GET), whatever method is asked.
    [Fact]
    public async Task A_preflight_for_POST_lists_only_GET_as_allowed_method()
    {
        var request = Request(HttpMethod.Options, "/farms", WebUiOrigin);
        request.Headers.Add("Access-Control-Request-Method", "POST");

        var response = await Client.SendAsync(request);

        var allowMethods = response.Headers.TryGetValues("Access-Control-Allow-Methods", out var values)
            ? string.Join(",", values)
            : null;
        Assert.Equal("GET", allowMethods);
    }
}
