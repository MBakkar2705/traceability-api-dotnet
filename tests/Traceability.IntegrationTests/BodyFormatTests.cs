using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Traceability.IntegrationTests;

// F1 to F3: the format of numbers, dates and times in a JSON body, on the test database.
// Several expectations below are hypotheses written before the run (marked as such):
// the test observes them, and a failure is information, not a surprise to hide.
[Collection(ApiCollection.Name)]
public class BodyFormatTests(ApiFixture api)
{
    private HttpClient Client => api.Client;

    // A farm and a station with the RECEPTION function, enough to create batches.
    private async Task<(string Farm, string Station)> CreateFarmAndStationAsync()
    {
        var farm = TestData.NewCode();
        var farmResponse = await Client.PostAsJsonAsync("/farms", new { code = farm, name = "Test farm", region = "Test region" });
        Assert.Equal(HttpStatusCode.Created, farmResponse.StatusCode);

        var station = TestData.NewCode();
        var stationResponse = await Client.PostAsJsonAsync("/stations", new { code = station, name = "Test station" });
        Assert.Equal(HttpStatusCode.Created, stationResponse.StatusCode);

        var capability = await Client.PostAsJsonAsync($"/stations/{station}/capabilities", new { movementType = "RECEPTION" });
        Assert.Equal(HttpStatusCode.Created, capability.StatusCode);

        return (farm, station);
    }

    // The body is written as text, so each value can be sent exactly as the test wants
    // (a number, a text, an unreadable value). The values are JSON: texts keep their quotes.
    private async Task<HttpResponseMessage> PostBatchJsonAsync(
        string batchCode, string farm, string station,
        string quantityJson = "500",
        string harvestDateJson = "\"2026-10-14\"",
        string occurredAtJson = "\"2026-10-14T06:00:00Z\"",
        string variety = "Roma")
    {
        var json = $$"""
            {"batchCode":"{{batchCode}}","farmCode":"{{farm}}","variety":"{{variety}}","harvestDate":{{harvestDateJson}},"quantityKg":{{quantityJson}},"stationCode":"{{station}}","occurredAt":{{occurredAtJson}}}
            """;
        return await Client.PostAsync("/batches", TestData.Json(json));
    }

    private async Task<JsonElement> GetBatchJsonAsync(string batchCode)
    {
        var response = await Client.GetAsync($"/batches/{batchCode}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await TestData.ReadJsonAsync(response);
    }

    // F1: a quantity with two decimals goes in and comes back unchanged.
    [Fact]
    public async Task A_quantity_with_two_decimals_comes_back_unchanged()
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, quantityJson: "500.55");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var quantity = (await GetBatchJsonAsync(batchCode)).GetProperty("quantityKg");
        Assert.Equal(500.55m, quantity.GetDecimal());
        Assert.Equal("500.55", quantity.GetRawText());
    }

    // F1, hypothesis: a quantity sent as 500.5 is read back with the two decimals of the
    // DECIMAL(10,2) column, trailing zero included. This test observes the real text.
    [Fact]
    public async Task A_quantity_with_one_decimal_is_shown_with_two_decimals()
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, quantityJson: "500.5");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var quantity = (await GetBatchJsonAsync(batchCode)).GetProperty("quantityKg");
        Assert.Equal(500.5m, quantity.GetDecimal());
        Assert.Equal("500.50", quantity.GetRawText());
    }

    // F2, hypothesis: a value that cannot be read in the body (not a number, not a date, a
    // time where a day is expected) is refused with 400 before any procedure call, in the
    // Problem Details form and without errorCode.
    [Theory]
    [InlineData("\"abc\"", "\"2026-10-14\"", "\"2026-10-14T06:00:00Z\"")]
    [InlineData("500", "\"not-a-date\"", "\"2026-10-14T06:00:00Z\"")]
    [InlineData("500", "\"2026-10-14T06:30:00\"", "\"2026-10-14T06:00:00Z\"")]
    [InlineData("500", "\"2026-10-14\"", "\"yesterday\"")]
    public async Task An_unreadable_value_in_the_body_gives_400(
        string quantityJson, string harvestDateJson, string occurredAtJson)
    {
        var response = await PostBatchJsonAsync(
            TestData.NewCode(), TestData.NewCode(), TestData.NewCode(),
            quantityJson, harvestDateJson, occurredAtJson);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = await TestData.ReadJsonAsync(response);
        Assert.False(body.TryGetProperty("errorCode", out _));
    }

    // F2, hypothesis: a number written as a text ("500") is accepted by ASP.NET Core.
    // This test observes it.
    [Fact]
    public async Task A_quantity_written_as_a_text_is_accepted()
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, quantityJson: "\"500\"");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(500m, (await GetBatchJsonAsync(batchCode)).GetProperty("quantityKg").GetDecimal());
    }

    // F3: a time without "Z" and without offset is refused with 400 on the field occurredAt
    // (decision of lot 3c: the time is always explicitly UTC). Hypothesis: the JSON reader reads it
    // as a time with no indication, which RequireUtcTime refuses. This test observes it.
    [Fact]
    public async Task A_time_without_z_or_offset_gives_400()
    {
        var response = await PostBatchJsonAsync(
            TestData.NewCode(), TestData.NewCode(), TestData.NewCode(),
            occurredAtJson: "\"2026-10-14T06:00:00\"");

        await TestData.AssertShapeErrorAsync(response, "occurredAt");
    }

    // F3: the time of the first movement is read back in UTC with a "Z". Observed before the
    // decision above: a time with an offset is converted to UTC (08:00+02:00 is 06:00Z).
    [Theory]
    [InlineData("\"2026-10-14T06:00:00Z\"", "2026-10-14T06:00:00Z")]
    [InlineData("\"2026-10-14T08:00:00+02:00\"", "2026-10-14T06:00:00Z")]
    public async Task The_time_of_a_movement_is_read_back_in_utc(string occurredAtJson, string expected)
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, occurredAtJson: occurredAtJson);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var movements = (await GetBatchJsonAsync(batchCode)).GetProperty("movements");
        Assert.Equal(expected, movements[0].GetProperty("occurredAt").GetString());
    }

    // Limits of the columns. The expectation is the behaviour we want: a 400 on the field. It is NOT
    // known whether the API does it today: a failure tells what really happens (see its message).
    private async Task<string> DescribeBatchAsync(HttpResponseMessage response, string batchCode)
    {
        var text = await TestData.DescribeAsync(response);
        if (response.StatusCode == HttpStatusCode.Created)
        {
            var batch = await TestData.ReadJsonAsync(await Client.GetAsync($"/batches/{batchCode}"));
            text += $" | stored quantity {batch.GetProperty("quantityKg").GetRawText()}"
                + $" | stored variety length {batch.GetProperty("variety").GetString()!.Length}";
        }

        return text;
    }

    // DECIMAL(10,2): a third decimal cannot be stored. Rounded, cut or refused: not known.
    [Fact]
    public async Task A_quantity_with_three_decimals_gives_400()
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, quantityJson: "500.555");

        Assert.True(response.StatusCode == HttpStatusCode.BadRequest, await DescribeBatchAsync(response, batchCode));
        await TestData.AssertShapeErrorAsync(response, "quantityKg");
    }

    // DECIMAL(10,2): at most 8 digits before the decimal point. 100000000 has 9.
    [Fact]
    public async Task A_quantity_with_too_many_digits_gives_400()
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, quantityJson: "100000000");

        Assert.True(response.StatusCode == HttpStatusCode.BadRequest, await DescribeBatchAsync(response, batchCode));
        await TestData.AssertShapeErrorAsync(response, "quantityKg");
    }

    // NVARCHAR(50): a variety of 51 characters.
    [Fact]
    public async Task A_variety_that_is_too_long_gives_400()
    {
        var (farm, station) = await CreateFarmAndStationAsync();
        var batchCode = TestData.NewCode();

        var response = await PostBatchJsonAsync(batchCode, farm, station, variety: new string('V', 51));

        Assert.True(response.StatusCode == HttpStatusCode.BadRequest, await DescribeBatchAsync(response, batchCode));
        await TestData.AssertShapeErrorAsync(response, "variety");
    }
}
