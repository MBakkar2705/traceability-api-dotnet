using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace Traceability.IntegrationTests;

/// <summary>Helpers shared by the HTTP tests.</summary>
public static class TestData
{
    // A code that no other test uses: 15 characters, letters and digits only.
    public static string NewCode() => "ZT-" + Guid.NewGuid().ToString("N")[..12].ToUpperInvariant();

    public static async Task<JsonElement> ReadJsonAsync(HttpResponseMessage response) =>
        await response.Content.ReadFromJsonAsync<JsonElement>();

    public static StringContent Json(string json) => new(json, Encoding.UTF8, "application/json");

    // An error raised by a stored procedure: status, Problem Details content type,
    // errorCode (the SQL number) and a detail text.
    public static async Task AssertProcedureErrorAsync(
        HttpResponseMessage response, HttpStatusCode status, int errorCode)
    {
        Assert.Equal(status, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);

        var body = await ReadJsonAsync(response);
        Assert.Equal((int)status, body.GetProperty("status").GetInt32());
        Assert.Equal(errorCode, body.GetProperty("errorCode").GetInt32());
        Assert.False(string.IsNullOrWhiteSpace(body.GetProperty("detail").GetString()));
    }

    // A shape error raised before any procedure call: 400, an "errors" object with exactly
    // the given fields, and no errorCode.
    public static async Task AssertShapeErrorAsync(HttpResponseMessage response, params string[] fields)
    {
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);

        var body = await ReadJsonAsync(response);
        Assert.False(body.TryGetProperty("errorCode", out _));
        Assert.True(body.TryGetProperty("traceId", out _));

        var names = body.GetProperty("errors").EnumerateObject().Select(p => p.Name).OrderBy(n => n).ToList();
        Assert.Equal(fields.OrderBy(n => n).ToList(), names);
    }

    // For failure messages: what the API really answered.
    public static async Task<string> DescribeAsync(HttpResponseMessage response) =>
        $"status {(int)response.StatusCode}, body: {await response.Content.ReadAsStringAsync()}";
}
