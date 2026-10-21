using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Traceability.IntegrationTests;

// B1 to B11 and additions: the batch routes, on the test database. Every test creates its own
// farms, stations and batches with unique codes, so the checks do not depend on the other tests.
[Collection(ApiCollection.Name)]
public class BatchesTests(ApiFixture api)
{
    private static readonly string[] AllFunctions = ["RECEPTION", "SORTING", "PACKING", "SHIPMENT"];

    private HttpClient Client => api.Client;

    private async Task<string> CreateFarmAsync()
    {
        var code = TestData.NewCode();
        var response = await Client.PostAsJsonAsync("/farms", new { code, name = "Test farm", region = "Test region" });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return code;
    }

    // A station with the given functions (declared in the order given).
    private async Task<string> CreateStationAsync(params string[] movementTypes)
    {
        var code = TestData.NewCode();
        var created = await Client.PostAsJsonAsync("/stations", new { code, name = "Test station" });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        foreach (var movementType in movementTypes)
        {
            var added = await Client.PostAsJsonAsync($"/stations/{code}/capabilities", new { movementType });
            Assert.Equal(HttpStatusCode.Created, added.StatusCode);
        }

        return code;
    }

    private Task<HttpResponseMessage> PostBatchAsync(
        string batchCode, string farmCode, string stationCode, decimal quantityKg = 500m) =>
        Client.PostAsJsonAsync("/batches", new
        {
            batchCode,
            farmCode,
            variety = "Roma",
            harvestDate = "2026-10-14",
            quantityKg,
            stationCode,
            occurredAt = "2026-10-14T06:00:00Z",
        });

    private async Task<string> CreateBatchAsync(string farmCode, string stationCode, decimal quantityKg = 500m)
    {
        var code = TestData.NewCode();
        var response = await PostBatchAsync(code, farmCode, stationCode, quantityKg);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return code;
    }

    private Task<HttpResponseMessage> PostMovementAsync(
        string batchCode, string stationCode, string movementType, decimal quantityKg) =>
        Client.PostAsJsonAsync($"/batches/{batchCode}/movements", new
        {
            stationCode,
            movementType,
            quantityKg,
            occurredAt = "2026-10-14T08:00:00Z",
        });

    private async Task AddMovementAsync(string batchCode, string stationCode, string movementType, decimal quantityKg)
    {
        var response = await PostMovementAsync(batchCode, stationCode, movementType, quantityKg);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // A batch that went through the whole life cycle on one station that has all the functions.
    private async Task<(string FarmCode, string StationCode, string BatchCode)> CreateShippedBatchAsync()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync(AllFunctions);
        var batch = await CreateBatchAsync(farm, station, 500m);
        await AddMovementAsync(batch, station, "SORTING", 480m);
        await AddMovementAsync(batch, station, "PACKING", 470m);
        await AddMovementAsync(batch, station, "SHIPMENT", 470m);
        return (farm, station, batch);
    }

    private async Task<JsonElement> GetBatchJsonAsync(string batchCode)
    {
        var response = await Client.GetAsync($"/batches/{batchCode}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await TestData.ReadJsonAsync(response);
    }

    private async Task<JsonElement> ListAsync(string query)
    {
        var response = await Client.GetAsync(query.Length == 0 ? "/batches" : $"/batches?{query}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await TestData.ReadJsonAsync(response);
    }

    private static List<string?> Codes(JsonElement page) =>
        page.GetProperty("items").EnumerateArray().Select(i => i.GetProperty("batchCode").GetString()).ToList();

    // B1: the whole life cycle: creation, three movements, then the batch is SHIPPED with its
    // four movements in the order they were recorded. The POST answers have an empty body and
    // a Location header pointing to the batch.
    [Fact]
    public async Task A_batch_goes_through_the_whole_life_cycle()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync(AllFunctions);
        var batchCode = TestData.NewCode();

        var created = await PostBatchAsync(batchCode, farm, station, 500m);

        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        Assert.NotNull(created.Headers.Location);
        Assert.EndsWith($"/batches/{batchCode}", created.Headers.Location.ToString());
        Assert.Equal("", await created.Content.ReadAsStringAsync());

        var afterCreation = await GetBatchJsonAsync(batchCode);
        Assert.Equal("RECEIVED", afterCreation.GetProperty("status").GetString());
        Assert.Equal(1, afterCreation.GetProperty("movements").GetArrayLength());

        var moved = await PostMovementAsync(batchCode, station, "SORTING", 480m);
        Assert.Equal(HttpStatusCode.Created, moved.StatusCode);
        Assert.NotNull(moved.Headers.Location);
        Assert.EndsWith($"/batches/{batchCode}", moved.Headers.Location.ToString());
        Assert.Equal("", await moved.Content.ReadAsStringAsync());

        await AddMovementAsync(batchCode, station, "PACKING", 470m);
        await AddMovementAsync(batchCode, station, "SHIPMENT", 470m);

        var batch = await GetBatchJsonAsync(batchCode);
        Assert.Equal(batchCode, batch.GetProperty("batchCode").GetString());
        Assert.Equal(farm, batch.GetProperty("farmCode").GetString());
        Assert.Equal("Roma", batch.GetProperty("variety").GetString());
        Assert.Equal("2026-10-14", batch.GetProperty("harvestDate").GetString());
        Assert.Equal(470m, batch.GetProperty("quantityKg").GetDecimal());
        Assert.Equal("SHIPPED", batch.GetProperty("status").GetString());
        Assert.False(batch.TryGetProperty("batchId", out _));

        var movements = batch.GetProperty("movements").EnumerateArray().ToList();
        Assert.Equal(
            new List<string?> { "RECEPTION", "SORTING", "PACKING", "SHIPMENT" },
            movements.Select(m => m.GetProperty("movementType").GetString()).ToList());
        Assert.Equal(
            new List<decimal> { 500m, 480m, 470m, 470m },
            movements.Select(m => m.GetProperty("quantityKg").GetDecimal()).ToList());
        Assert.All(movements, m => Assert.Equal(station, m.GetProperty("stationCode").GetString()));

        var ids = movements.Select(m => m.GetProperty("movementId").GetInt64()).ToList();
        Assert.Equal(ids.OrderBy(id => id).ToList(), ids);
        Assert.Equal(4, ids.Distinct().Count());
    }

    // B2: the same batch code twice: 409 with errorCode 50202.
    [Fact]
    public async Task A_batch_code_already_taken_gives_409()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");
        var batchCode = await CreateBatchAsync(farm, station);

        var second = await PostBatchAsync(batchCode, farm, station);

        await TestData.AssertProcedureErrorAsync(second, HttpStatusCode.Conflict, 50202);
    }

    // B3: an unknown farm: 404 with errorCode 50101.
    [Fact]
    public async Task An_unknown_farm_gives_404_when_a_batch_is_created()
    {
        var station = await CreateStationAsync("RECEPTION");

        var response = await PostBatchAsync(TestData.NewCode(), TestData.NewCode(), station);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50101);
    }

    // B4: a station without the needed function: 422 with errorCode 50303,
    // on creation (RECEPTION) and on adding a movement (here SORTING).
    [Fact]
    public async Task A_station_without_the_reception_function_gives_422_when_a_batch_is_created()
    {
        var farm = await CreateFarmAsync();
        var stationWithoutFunction = await CreateStationAsync();

        var response = await PostBatchAsync(TestData.NewCode(), farm, stationWithoutFunction);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50303);
    }

    [Fact]
    public async Task A_station_without_the_function_gives_422_when_a_movement_is_added()
    {
        var farm = await CreateFarmAsync();
        var receptionStation = await CreateStationAsync("RECEPTION");
        var packingOnlyStation = await CreateStationAsync("PACKING");
        var batchCode = await CreateBatchAsync(farm, receptionStation);

        var response = await PostMovementAsync(batchCode, packingOnlyStation, "SORTING", 480m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50303);
    }

    // B5: a skipped step (PACKING on a RECEIVED batch): 422 with errorCode 50301.
    // The station has the function, so only the order of the steps can be refused.
    [Fact]
    public async Task A_skipped_step_gives_422()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION", "PACKING");
        var batchCode = await CreateBatchAsync(farm, station);

        var response = await PostMovementAsync(batchCode, station, "PACKING", 480m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50301);
    }

    // B6: a quantity that goes up: 422 with errorCode 50302.
    [Fact]
    public async Task A_quantity_that_goes_up_gives_422()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION", "SORTING");
        var batchCode = await CreateBatchAsync(farm, station, 500m);

        var response = await PostMovementAsync(batchCode, station, "SORTING", 600m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50302);
    }

    // B7: a batch that is already SHIPPED: 422 with errorCode 50300.
    [Fact]
    public async Task A_batch_already_shipped_gives_422()
    {
        var (_, station, batchCode) = await CreateShippedBatchAsync();

        var response = await PostMovementAsync(batchCode, station, "SORTING", 100m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50300);
    }

    // B8: a quantity of 0: 400 with errorCode 50401, on creation and on adding a movement.
    [Fact]
    public async Task A_quantity_of_zero_gives_400_when_a_batch_is_created()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");

        var response = await PostBatchAsync(TestData.NewCode(), farm, station, 0m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50401);
    }

    [Fact]
    public async Task A_quantity_of_zero_gives_400_when_a_movement_is_added()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION", "SORTING");
        var batchCode = await CreateBatchAsync(farm, station);

        var response = await PostMovementAsync(batchCode, station, "SORTING", 0m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50401);
    }

    // B9: an unknown batch: 404 with errorCode 50100, on reading and on adding a movement.
    [Fact]
    public async Task An_unknown_batch_gives_404_when_read()
    {
        var response = await Client.GetAsync($"/batches/{TestData.NewCode()}");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50100);
    }

    [Fact]
    public async Task An_unknown_batch_gives_404_when_a_movement_is_added()
    {
        var station = await CreateStationAsync("SORTING");

        var response = await PostMovementAsync(TestData.NewCode(), station, "SORTING", 100m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50100);
    }

    // B10: the list filtered by status, by farm, and by both. The farms are created by the test,
    // so the checks on a farm are exact; the check on the status alone is relative (other tests
    // create batches too).
    [Fact]
    public async Task The_list_can_be_filtered_by_status_and_by_farm()
    {
        var farmA = await CreateFarmAsync();
        var farmB = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION", "SORTING");

        var a1 = await CreateBatchAsync(farmA, station);
        var a2 = await CreateBatchAsync(farmA, station);
        await AddMovementAsync(a2, station, "SORTING", 480m);
        var b1 = await CreateBatchAsync(farmB, station);
        var b2 = await CreateBatchAsync(farmB, station);
        await AddMovementAsync(b2, station, "SORTING", 480m);

        var byFarm = await ListAsync($"farmCode={farmA}&pageSize=1000");
        Assert.Equal(new List<string?> { a1, a2 }, Codes(byFarm));
        Assert.Equal(2, byFarm.GetProperty("totalCount").GetInt32());

        var byFarmAndStatus = await ListAsync($"status=SORTED&farmCode={farmA}");
        Assert.Equal(new List<string?> { a2 }, Codes(byFarmAndStatus));
        Assert.Equal(1, byFarmAndStatus.GetProperty("totalCount").GetInt32());

        var receivedOfFarmB = await ListAsync($"status=RECEIVED&farmCode={farmB}");
        Assert.Equal(new List<string?> { b1 }, Codes(receivedOfFarmB));
        Assert.Equal(1, receivedOfFarmB.GetProperty("totalCount").GetInt32());

        var sorted = await ListAsync("status=SORTED&pageSize=1000");
        Assert.Contains(a2, Codes(sorted));
        Assert.Contains(b2, Codes(sorted));
        Assert.True(sorted.GetProperty("totalCount").GetInt32() >= 2);
        Assert.All(
            sorted.GetProperty("items").EnumerateArray(),
            item => Assert.Equal("SORTED", item.GetProperty("status").GetString()));

        var defaultPage = await ListAsync("");
        Assert.Equal(1, defaultPage.GetProperty("pageNumber").GetInt32());
        Assert.Equal(20, defaultPage.GetProperty("pageSize").GetInt32());
        Assert.True(defaultPage.GetProperty("items").GetArrayLength() <= 20);
        Assert.True(defaultPage.GetProperty("totalCount").GetInt32() >= 4);
    }

    // B11: an unknown status: 400 with errorCode 50403.
    [Fact]
    public async Task An_unknown_status_gives_400()
    {
        var response = await Client.GetAsync("/batches?status=TELEPORT");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50403);
    }

    // Additions to the plan.

    // A batch code of 31 characters (the limit is 30): a shape error raised by the API,
    // on creation and on reading, without any procedure call.
    [Fact]
    public async Task A_batch_code_that_is_too_long_gives_400()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");
        var tooLong = new string('A', 31);

        var created = await PostBatchAsync(tooLong, farm, station);
        await TestData.AssertShapeErrorAsync(created, "batchCode");

        var read = await Client.GetAsync($"/batches/{tooLong}");
        await TestData.AssertShapeErrorAsync(read, "batchCode");
    }

    // An unknown farm used as a filter: 404 with errorCode 50101.
    [Fact]
    public async Task An_unknown_farm_gives_404_when_used_as_a_filter()
    {
        var response = await Client.GetAsync($"/batches?farmCode={TestData.NewCode()}");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50101);
    }

    [Theory]
    [InlineData("pageNumber=0")]
    [InlineData("pageSize=1001")]
    public async Task An_invalid_page_gives_400_from_the_procedure(string query)
    {
        var response = await Client.GetAsync($"/batches?{query}");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50404);
    }

    // A page beyond the end. The expectation (200, no item, the real total) is a hypothesis:
    // this test observes it.
    [Fact]
    public async Task A_page_beyond_the_end_is_empty_with_the_real_total()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");
        await CreateBatchAsync(farm, station);

        var page = await ListAsync($"farmCode={farm}&pageNumber=2&pageSize=10");

        Assert.Equal(0, page.GetProperty("items").GetArrayLength());
        Assert.Equal(1, page.GetProperty("totalCount").GetInt32());
        Assert.Equal(2, page.GetProperty("pageNumber").GetInt32());
        Assert.Equal(10, page.GetProperty("pageSize").GetInt32());
    }

    // Missing fields: shape errors raised by the API, naming every missing field.
    [Fact]
    public async Task A_batch_without_fields_gives_400_naming_every_field()
    {
        var response = await Client.PostAsync("/batches", TestData.Json("{}"));

        await TestData.AssertShapeErrorAsync(
            response,
            "batchCode", "farmCode", "variety", "harvestDate", "quantityKg", "stationCode", "occurredAt");
    }

    [Fact]
    public async Task A_movement_without_fields_gives_400_naming_every_field()
    {
        var response = await Client.PostAsync($"/batches/{TestData.NewCode()}/movements", TestData.Json("{}"));

        await TestData.AssertShapeErrorAsync(
            response,
            "stationCode", "movementType", "quantityKg", "occurredAt");
    }

    // Hypothesis (the collation of the database ignores case): a batch is found whatever the case
    // of its code in the address, and the code is returned as it was stored.
    [Fact]
    public async Task A_batch_is_found_whatever_the_case_of_its_code()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");
        var batchCode = await CreateBatchAsync(farm, station);

        var response = await Client.GetAsync($"/batches/{batchCode.ToLowerInvariant()}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await TestData.ReadJsonAsync(response);
        Assert.Equal(batchCode, body.GetProperty("batchCode").GetString());
    }

    // The API refuses a quantity the column cannot hold also when a movement is added, and a
    // movement type or a status filter longer than their columns (20). Shape errors: no database call.
    [Theory]
    [InlineData("500.555")]
    [InlineData("100000000")]
    public async Task A_quantity_the_column_cannot_hold_gives_400_when_a_movement_is_added(string quantityJson)
    {
        var json = $$"""{"stationCode":"{{TestData.NewCode()}}","movementType":"SORTING","quantityKg":{{quantityJson}},"occurredAt":"2026-10-14T08:00:00Z"}""";

        var response = await Client.PostAsync($"/batches/{TestData.NewCode()}/movements", TestData.Json(json));

        await TestData.AssertShapeErrorAsync(response, "quantityKg");
    }

    [Fact]
    public async Task A_movement_type_that_is_too_long_gives_400()
    {
        var response = await PostMovementAsync(TestData.NewCode(), TestData.NewCode(), new string('M', 21), 100m);

        await TestData.AssertShapeErrorAsync(response, "movementType");
    }

    [Fact]
    public async Task A_status_filter_that_is_too_long_gives_400()
    {
        var response = await Client.GetAsync($"/batches?status={new string('S', 21)}");

        await TestData.AssertShapeErrorAsync(response, "status");
    }

    // Errors of the procedures that the batch routes can return and that the tests above do not
    // cover: unknown station (on creation and on adding a movement), empty batch code, unknown
    // movement type when a movement is added.
    [Fact]
    public async Task An_unknown_station_gives_404_when_a_batch_is_created()
    {
        var farm = await CreateFarmAsync();

        var response = await PostBatchAsync(TestData.NewCode(), farm, TestData.NewCode());

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50102);
    }

    [Fact]
    public async Task An_unknown_station_gives_404_when_a_movement_is_added()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");
        var batchCode = await CreateBatchAsync(farm, station);

        var response = await PostMovementAsync(batchCode, TestData.NewCode(), "SORTING", 480m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50102);
    }

    [Fact]
    public async Task An_empty_batch_code_gives_400_from_the_procedure()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");

        var response = await PostBatchAsync("", farm, station);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50400);
    }

    [Fact]
    public async Task An_unknown_movement_type_gives_400_when_a_movement_is_added()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");
        var batchCode = await CreateBatchAsync(farm, station);

        var response = await PostMovementAsync(batchCode, station, "TELEPORT", 480m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50402);
    }
}
