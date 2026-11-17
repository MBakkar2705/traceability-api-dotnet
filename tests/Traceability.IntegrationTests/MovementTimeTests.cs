using System.Globalization;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Traceability.IntegrationTests;

// Lot 12c: the time of the movements, through the API, on the test database. The procedures refuse a
// time more than 5 minutes after the clock of SQL Server (error 50310) and a time that is not after the
// previous valid step, or not before the next valid step when a movement is corrected (error 50311).
// These tests show that the errors reach the caller with the right status (422) and the right
// errorCode, and that a refusal changes nothing. The rules themselves are tested in 006.
// The times in the future are computed from the clock of this computer with a wide margin (+2 minutes
// accepted, +10 minutes refused): the exact limit of 5 minutes is not tested. All the other times are
// on 2026-10-14, a day in the past. Like the other tests, each test creates its own data.
[Collection(ApiCollection.Name)]
public class MovementTimeTests(ApiFixture api)
{
    private static readonly string[] AllFunctions = ["RECEPTION", "SORTING", "PACKING", "SHIPMENT"];

    // The writer enters the data, a supervisor corrects it.
    private HttpClient Writer => api.Client;

    private HttpClient NewSupervisor() => api.CreateClient("supervisor", "sup-id-1", "Sup One");

    private static string InMinutes(int minutes) =>
        DateTime.UtcNow.AddMinutes(minutes).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture);

    private async Task<string> CreateFarmAsync()
    {
        var code = TestData.NewCode();
        var response = await Writer.PostAsJsonAsync("/farms", new { code, name = "Test farm", region = "Test region" });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return code;
    }

    private async Task<string> CreateStationAsync()
    {
        var code = TestData.NewCode();
        var created = await Writer.PostAsJsonAsync("/stations", new { code, name = "Test station" });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        foreach (var movementType in AllFunctions)
        {
            var added = await Writer.PostAsJsonAsync($"/stations/{code}/capabilities", new { movementType });
            Assert.Equal(HttpStatusCode.Created, added.StatusCode);
        }

        return code;
    }

    private Task<HttpResponseMessage> PostBatchAsync(string batchCode, string farmCode, string stationCode, string occurredAt) =>
        Writer.PostAsJsonAsync("/batches", new
        {
            batchCode,
            farmCode,
            variety = "Roma",
            harvestDate = "2026-10-14",
            quantityKg = 500m,
            stationCode,
            occurredAt,
        });

    private Task<HttpResponseMessage> PostMovementAsync(
        string batchCode, string stationCode, string movementType, decimal quantityKg, string occurredAt) =>
        Writer.PostAsJsonAsync($"/batches/{batchCode}/movements", new
        {
            stationCode,
            movementType,
            quantityKg,
            occurredAt,
        });

    private Task<HttpResponseMessage> ReplaceAsync(
        HttpClient client, string batchCode, long movementId, string stationCode, decimal quantityKg, string occurredAt) =>
        client.PostAsJsonAsync($"/batches/{batchCode}/movements/{movementId}/replace", new
        {
            stationCode,
            quantityKg,
            occurredAt,
            reasonCode = "DATA_ENTRY_ERROR",
            reasonComment = (string?)null,
        });

    // A RECEIVED batch: one RECEPTION of 500 kg at 06:00.
    private async Task<(string StationCode, string BatchCode)> CreateReceivedBatchAsync()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync();
        var batch = TestData.NewCode();
        var created = await PostBatchAsync(batch, farm, station, "2026-10-14T06:00:00Z");
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        return (station, batch);
    }

    // A SHIPPED batch: RECEPTION 500 at 06:00, SORTING 480 at 08:00, PACKING 470 at 09:00, SHIPMENT 470 at 10:00.
    private async Task<(string StationCode, string BatchCode)> CreateShippedBatchAsync()
    {
        var (station, batch) = await CreateReceivedBatchAsync();
        foreach (var (movementType, quantityKg) in new[] { ("SORTING", 480m), ("PACKING", 470m), ("SHIPMENT", 470m) })
        {
            var response = await PostMovementAsync(batch, station, movementType, quantityKg, TestData.TimeOfStep(movementType));
            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        }

        return (station, batch);
    }

    private async Task<JsonElement> GetBatchJsonAsync(string batchCode, HttpClient? client = null)
    {
        var response = await (client ?? Writer).GetAsync($"/batches/{batchCode}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await TestData.ReadJsonAsync(response);
    }

    private static JsonElement Movement(JsonElement batch, string movementType) =>
        batch.GetProperty("movements").EnumerateArray()
            .Single(m => m.GetProperty("movementType").GetString() == movementType);

    private static long MovementId(JsonElement batch, string movementType) =>
        Movement(batch, movementType).GetProperty("movementId").GetInt64();

    // ---------- A time in the future ----------

    [Fact]
    public async Task A_reception_10_minutes_in_the_future_is_refused_and_no_batch_is_created()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync();
        var batch = TestData.NewCode();

        var response = await PostBatchAsync(batch, farm, station, InMinutes(10));

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50310);
        var read = await Writer.GetAsync($"/batches/{batch}");
        Assert.Equal(HttpStatusCode.NotFound, read.StatusCode);
    }

    [Fact]
    public async Task A_movement_10_minutes_in_the_future_is_refused_and_the_batch_is_unchanged()
    {
        var (station, batch) = await CreateReceivedBatchAsync();

        var response = await PostMovementAsync(batch, station, "SORTING", 480m, InMinutes(10));

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50310);
        var after = await GetBatchJsonAsync(batch);
        Assert.Equal("RECEIVED", after.GetProperty("status").GetString());
        Assert.Equal(1, after.GetProperty("movements").GetArrayLength());
    }

    [Fact]
    public async Task A_movement_2_minutes_in_the_future_is_accepted()
    {
        var (station, batch) = await CreateReceivedBatchAsync();

        var response = await PostMovementAsync(batch, station, "SORTING", 480m, InMinutes(2));

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var after = await GetBatchJsonAsync(batch);
        Assert.Equal("SORTED", after.GetProperty("status").GetString());
        Assert.Equal(2, after.GetProperty("movements").GetArrayLength());
    }

    [Fact]
    public async Task A_replacement_10_minutes_in_the_future_is_refused_and_nothing_is_corrected()
    {
        var (station, batch) = await CreateShippedBatchAsync();
        var shipmentId = MovementId(await GetBatchJsonAsync(batch), "SHIPMENT");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batch, shipmentId, station, 470m, InMinutes(10));

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50310);
        Assert.Equal(0, (await GetBatchJsonAsync(batch)).GetProperty("corrections").GetArrayLength());
    }

    // A time in the future that is also after the next step: the future is the error that is given.
    [Fact]
    public async Task A_replacement_in_the_future_gives_50310_even_when_it_is_also_after_the_next_step()
    {
        var (station, batch) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batch), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batch, sortingId, station, 480m, InMinutes(10));

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50310);
    }

    // ---------- The order of the movements: adding ----------

    [Theory]
    [InlineData("2026-10-14T06:00:00Z")] // the same time as the reception
    [InlineData("2026-10-14T05:00:00Z")] // before the reception
    public async Task A_movement_that_is_not_after_the_previous_step_is_refused_and_the_batch_is_unchanged(string occurredAt)
    {
        var (station, batch) = await CreateReceivedBatchAsync();

        var response = await PostMovementAsync(batch, station, "SORTING", 480m, occurredAt);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50311);
        var after = await GetBatchJsonAsync(batch);
        Assert.Equal("RECEIVED", after.GetProperty("status").GetString());
        Assert.Equal(1, after.GetProperty("movements").GetArrayLength());
    }

    [Fact]
    public async Task A_packing_at_the_same_time_as_the_sorting_is_refused()
    {
        var (station, batch) = await CreateReceivedBatchAsync();
        var sorted = await PostMovementAsync(batch, station, "SORTING", 480m, "2026-10-14T08:00:00Z");
        Assert.Equal(HttpStatusCode.Created, sorted.StatusCode);

        var response = await PostMovementAsync(batch, station, "PACKING", 470m, "2026-10-14T08:00:00Z");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50311);
        Assert.Equal("SORTED", (await GetBatchJsonAsync(batch)).GetProperty("status").GetString());
    }

    // ---------- The order of the movements: replacing ----------

    // The quantity and the station stay the same: only the time is wrong. The batch is SHIPPED:
    // RECEPTION 06:00, SORTING 08:00, PACKING 09:00, SHIPMENT 10:00.
    [Theory]
    [InlineData("RECEPTION", 500, "2026-10-14T08:00:00Z")] // the same time as the next step
    [InlineData("RECEPTION", 500, "2026-10-14T08:30:00Z")] // after the next step
    [InlineData("SORTING", 480, "2026-10-14T06:00:00Z")]   // the same time as the previous step
    [InlineData("SORTING", 480, "2026-10-14T05:00:00Z")]   // before the previous step
    [InlineData("SORTING", 480, "2026-10-14T09:00:00Z")]   // the same time as the next step
    [InlineData("SORTING", 480, "2026-10-14T09:30:00Z")]   // after the next step
    [InlineData("SHIPMENT", 470, "2026-10-14T09:00:00Z")]  // the same time as the previous step
    [InlineData("SHIPMENT", 470, "2026-10-14T08:30:00Z")]  // before the previous step
    public async Task A_replacement_out_of_order_is_refused_and_nothing_is_corrected(
        string movementType, int quantityKg, string occurredAt)
    {
        var (station, batch) = await CreateShippedBatchAsync();
        var movementId = MovementId(await GetBatchJsonAsync(batch), movementType);
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batch, movementId, station, quantityKg, occurredAt);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50311);
        var after = await GetBatchJsonAsync(batch);
        Assert.Equal(0, after.GetProperty("corrections").GetArrayLength());
        Assert.Equal(0, Movement(after, movementType).GetProperty("correctionCount").GetInt32());
    }

    [Fact]
    public async Task A_replacement_between_the_two_neighbours_is_accepted_and_the_original_time_is_kept()
    {
        var (station, batch) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batch), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batch, sortingId, station, 480m, "2026-10-14T07:00:00Z");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var sorting = Movement(await GetBatchJsonAsync(batch), "SORTING");
        Assert.Equal(
            DateTime.Parse("2026-10-14T07:00:00Z").ToUniversalTime(),
            sorting.GetProperty("occurredAt").GetDateTime().ToUniversalTime());
        Assert.Equal(
            DateTime.Parse("2026-10-14T08:00:00Z").ToUniversalTime(),
            sorting.GetProperty("originalOccurredAt").GetDateTime().ToUniversalTime());
        Assert.Equal(1, sorting.GetProperty("correctionCount").GetInt32());
    }
}
