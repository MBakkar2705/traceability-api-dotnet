using System.Net;
using System.Net.Http.Json;

namespace Traceability.IntegrationTests;

// S1 to S7: the station routes, on the test database.
[Collection(ApiCollection.Name)]
public class StationsTests(ApiFixture api)
{
    private HttpClient Client => api.Client;

    private async Task<string> CreateStationAsync()
    {
        var code = TestData.NewCode();
        var response = await Client.PostAsJsonAsync("/stations", new { code, name = "Test station" });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return code;
    }

    private async Task<HttpResponseMessage> PostCapabilityAsync(string stationCode, string movementType) =>
        await Client.PostAsJsonAsync($"/stations/{stationCode}/capabilities", new { movementType });

    private async Task<List<string?>> CapabilitiesAsync(string stationCode)
    {
        var response = await Client.GetAsync($"/stations/{stationCode}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = await TestData.ReadJsonAsync(response);
        return body.GetProperty("capabilities").EnumerateArray().Select(c => c.GetString()).ToList();
    }

    // S1: creation answers 201 with the station and a Location header pointing to it.
    [Fact]
    public async Task A_station_is_created()
    {
        var code = TestData.NewCode();

        var response = await Client.PostAsJsonAsync("/stations", new { code, name = "Test station" });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
        Assert.EndsWith($"/stations/{code}", response.Headers.Location.ToString());

        var body = await TestData.ReadJsonAsync(response);
        Assert.Equal(code, body.GetProperty("code").GetString());
        Assert.Equal("Test station", body.GetProperty("name").GetString());
        Assert.False(body.TryGetProperty("stationId", out _));
    }

    // S2: the same code twice: 409 with errorCode 50201.
    [Fact]
    public async Task A_code_already_taken_gives_409()
    {
        var code = await CreateStationAsync();

        var second = await Client.PostAsJsonAsync("/stations", new { code, name = "Other" });

        await TestData.AssertProcedureErrorAsync(second, HttpStatusCode.Conflict, 50201);
    }

    // S3: a new station has no function; capabilities are added (201, empty body, Location)
    // and read back in life-cycle order, whatever the order they were added in.
    [Fact]
    public async Task Capabilities_are_added_and_read_in_life_cycle_order()
    {
        var code = await CreateStationAsync();
        Assert.Empty(await CapabilitiesAsync(code));

        var first = await PostCapabilityAsync(code, "PACKING");
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        Assert.NotNull(first.Headers.Location);
        Assert.EndsWith($"/stations/{code}", first.Headers.Location.ToString());
        Assert.Equal("", await first.Content.ReadAsStringAsync());

        Assert.Equal(HttpStatusCode.Created, (await PostCapabilityAsync(code, "RECEPTION")).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await PostCapabilityAsync(code, "SORTING")).StatusCode);

        Assert.Equal(new List<string?> { "RECEPTION", "SORTING", "PACKING" }, await CapabilitiesAsync(code));
    }

    // S4: the same function twice: 409 with errorCode 50203.
    [Fact]
    public async Task A_function_already_declared_gives_409()
    {
        var code = await CreateStationAsync();
        Assert.Equal(HttpStatusCode.Created, (await PostCapabilityAsync(code, "RECEPTION")).StatusCode);

        var second = await PostCapabilityAsync(code, "RECEPTION");

        await TestData.AssertProcedureErrorAsync(second, HttpStatusCode.Conflict, 50203);
    }

    // S5: an unknown movement type: 400 with errorCode 50402 ...
    [Fact]
    public async Task An_unknown_movement_type_gives_400()
    {
        var code = await CreateStationAsync();

        var response = await PostCapabilityAsync(code, "TELEPORT");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50402);
    }

    // ... and lower case is accepted. The expectation that it is read back in upper case
    // is a hypothesis of the design: this test observes it.
    [Fact]
    public async Task A_movement_type_in_lower_case_is_accepted()
    {
        var code = await CreateStationAsync();

        var response = await PostCapabilityAsync(code, "sorting");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(new List<string?> { "SORTING" }, await CapabilitiesAsync(code));
    }

    // S6: an unknown station: 404 with errorCode 50102, on reading and on adding a function.
    [Fact]
    public async Task An_unknown_station_gives_404_when_read()
    {
        var response = await Client.GetAsync($"/stations/{TestData.NewCode()}");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50102);
    }

    [Fact]
    public async Task An_unknown_station_gives_404_when_a_function_is_added()
    {
        var response = await PostCapabilityAsync(TestData.NewCode(), "RECEPTION");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50102);
    }

    // S7: the list, with relative checks as for the farms.
    [Fact]
    public async Task The_list_returns_the_stations_in_creation_order_with_the_total()
    {
        var codes = new[] { await CreateStationAsync(), await CreateStationAsync(), await CreateStationAsync() };

        var everything = await TestData.ReadJsonAsync(await Client.GetAsync("/stations?pageNumber=1&pageSize=1000"));
        var totalCount = everything.GetProperty("totalCount").GetInt32();
        Assert.True(totalCount >= 3);

        var listed = everything.GetProperty("items").EnumerateArray()
            .Select(item => item.GetProperty("code").GetString())
            .ToList();
        var positions = codes.Select(code => listed.IndexOf(code)).ToList();
        Assert.DoesNotContain(-1, positions);
        Assert.Equal(positions.OrderBy(p => p).ToList(), positions);

        var defaultPage = await TestData.ReadJsonAsync(await Client.GetAsync("/stations"));
        Assert.Equal(1, defaultPage.GetProperty("pageNumber").GetInt32());
        Assert.Equal(20, defaultPage.GetProperty("pageSize").GetInt32());
        Assert.True(defaultPage.GetProperty("items").GetArrayLength() <= 20);
        Assert.Equal(totalCount, defaultPage.GetProperty("totalCount").GetInt32());
    }

    [Theory]
    [InlineData("pageNumber=0")]
    [InlineData("pageSize=1001")]
    public async Task An_invalid_page_gives_400_from_the_procedure(string query)
    {
        var response = await Client.GetAsync($"/stations?{query}");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50404);
    }

    // Additions to the plan: the shape checks written in the station controller.
    [Fact]
    public async Task A_malformed_station_code_in_the_address_gives_400()
    {
        var response = await Client.GetAsync("/stations/AB%20CD");

        await TestData.AssertShapeErrorAsync(response, "stationCode");
    }

    [Fact]
    public async Task A_missing_movement_type_gives_400()
    {
        var code = await CreateStationAsync();

        var response = await Client.PostAsync($"/stations/{code}/capabilities", TestData.Json("{}"));

        await TestData.AssertShapeErrorAsync(response, "movementType");
    }
}
