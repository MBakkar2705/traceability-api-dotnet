using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Traceability.IntegrationTests;

// Lot 12a: the correction routes (replace and cancel a movement) and what GET /batches/{batchCode}
// returns about them, on the test database. Like BatchesTests, every test creates its own farms,
// stations and batches with unique codes. The default client is a writer (it enters the movements);
// the corrections are made by a client with the role supervisor.
[Collection(ApiCollection.Name)]
public class CorrectionsTests(ApiFixture api)
{
    private static readonly string[] AllFunctions = ["RECEPTION", "SORTING", "PACKING", "SHIPMENT"];

    // The writer enters the data.
    private HttpClient Writer => api.Client;

    private HttpClient NewSupervisor(string userId = "sup-id-1", string userName = "Sup One") =>
        api.CreateClient("supervisor", userId, userName);

    private async Task<string> CreateFarmAsync()
    {
        var code = TestData.NewCode();
        var response = await Writer.PostAsJsonAsync("/farms", new { code, name = "Test farm", region = "Test region" });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return code;
    }

    private async Task<string> CreateStationAsync(params string[] movementTypes)
    {
        var code = TestData.NewCode();
        var created = await Writer.PostAsJsonAsync("/stations", new { code, name = "Test station" });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        foreach (var movementType in movementTypes)
        {
            var added = await Writer.PostAsJsonAsync($"/stations/{code}/capabilities", new { movementType });
            Assert.Equal(HttpStatusCode.Created, added.StatusCode);
        }

        return code;
    }

    private async Task AddMovementAsync(string batchCode, string stationCode, string movementType, decimal quantityKg)
    {
        var response = await Writer.PostAsJsonAsync($"/batches/{batchCode}/movements", new
        {
            stationCode,
            movementType,
            quantityKg,
            occurredAt = "2026-10-14T08:00:00Z",
        });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // A batch SHIPPED on one station that has all the functions: RECEPTION 500, SORTING 480,
    // PACKING 470, SHIPMENT 470. Every movement after the reception is at 2026-10-14T08:00:00Z.
    private async Task<(string StationCode, string BatchCode)> CreateShippedBatchAsync()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync(AllFunctions);
        var batch = TestData.NewCode();
        var created = await Writer.PostAsJsonAsync("/batches", new
        {
            batchCode = batch,
            farmCode = farm,
            variety = "Roma",
            harvestDate = "2026-10-14",
            quantityKg = 500m,
            stationCode = station,
            occurredAt = "2026-10-14T06:00:00Z",
        });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        await AddMovementAsync(batch, station, "SORTING", 480m);
        await AddMovementAsync(batch, station, "PACKING", 470m);
        await AddMovementAsync(batch, station, "SHIPMENT", 470m);
        return (station, batch);
    }

    private async Task<JsonElement> GetBatchJsonAsync(string batchCode)
    {
        var response = await Writer.GetAsync($"/batches/{batchCode}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await TestData.ReadJsonAsync(response);
    }

    private static long MovementId(JsonElement batch, string movementType) =>
        batch.GetProperty("movements").EnumerateArray()
            .Single(m => m.GetProperty("movementType").GetString() == movementType)
            .GetProperty("movementId").GetInt64();

    private static JsonElement Movement(JsonElement batch, string movementType) =>
        batch.GetProperty("movements").EnumerateArray()
            .Single(m => m.GetProperty("movementType").GetString() == movementType);

    private static Task<HttpResponseMessage> ReplaceAsync(
        HttpClient client, string batchCode, long movementId, string stationCode, decimal quantityKg,
        string reasonCode = "DATA_ENTRY_ERROR", string? reasonComment = null,
        string occurredAt = "2026-10-14T08:00:00Z") =>
        client.PostAsJsonAsync($"/batches/{batchCode}/movements/{movementId}/replace", new
        {
            stationCode,
            quantityKg,
            occurredAt,
            reasonCode,
            reasonComment,
        });

    private static Task<HttpResponseMessage> CancelAsync(
        HttpClient client, string batchCode, long movementId,
        string reasonCode = "DATA_ENTRY_ERROR", string? reasonComment = null) =>
        client.PostAsJsonAsync($"/batches/{batchCode}/movements/{movementId}/cancel", new
        {
            reasonCode,
            reasonComment,
        });

    // ---------- What a batch without correction looks like ----------

    [Fact]
    public async Task A_batch_without_correction_has_no_corrections_and_its_original_values_are_its_values()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();

        var batch = await GetBatchJsonAsync(batchCode);

        Assert.Equal(0, batch.GetProperty("corrections").GetArrayLength());
        foreach (var movement in batch.GetProperty("movements").EnumerateArray())
        {
            Assert.False(movement.GetProperty("isCancelled").GetBoolean());
            Assert.Equal(0, movement.GetProperty("correctionCount").GetInt32());
            Assert.Equal(
                movement.GetProperty("stationCode").GetString(),
                movement.GetProperty("originalStationCode").GetString());
            Assert.Equal(
                movement.GetProperty("quantityKg").GetDecimal(),
                movement.GetProperty("originalQuantityKg").GetDecimal());
            Assert.Equal(
                movement.GetProperty("occurredAt").GetDateTime(),
                movement.GetProperty("originalOccurredAt").GetDateTime());
        }
    }

    // ---------- Replace: accepted ----------

    [Fact]
    public async Task A_supervisor_replaces_a_middle_movement_and_the_original_is_kept()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var before = await GetBatchJsonAsync(batchCode);
        var sortingId = MovementId(before, "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(
            supervisor, batchCode, sortingId, station, 475m,
            reasonCode: "MEASUREMENT_ERROR", reasonComment: "Scale was not zeroed",
            occurredAt: "2026-10-14T09:30:00Z");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
        Assert.EndsWith($"/batches/{batchCode}", response.Headers.Location.ToString());
        Assert.Equal("", await response.Content.ReadAsStringAsync());

        var after = await GetBatchJsonAsync(batchCode);

        // The valid values are the corrected ones, the original values are still there.
        var sorting = Movement(after, "SORTING");
        Assert.Equal(475m, sorting.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(480m, sorting.GetProperty("originalQuantityKg").GetDecimal());
        Assert.Equal(
            DateTime.Parse("2026-10-14T09:30:00Z").ToUniversalTime(),
            sorting.GetProperty("occurredAt").GetDateTime().ToUniversalTime());
        Assert.Equal(
            DateTime.Parse("2026-10-14T08:00:00Z").ToUniversalTime(),
            sorting.GetProperty("originalOccurredAt").GetDateTime().ToUniversalTime());
        Assert.Equal(1, sorting.GetProperty("correctionCount").GetInt32());
        Assert.False(sorting.GetProperty("isCancelled").GetBoolean());

        // The batch is not the last step: it is not changed.
        Assert.Equal("SHIPPED", after.GetProperty("status").GetString());
        Assert.Equal(470m, after.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(4, after.GetProperty("movements").GetArrayLength());

        // The correction: kind, reason, comment, author name (never the author identifier).
        var corrections = after.GetProperty("corrections").EnumerateArray().ToList();
        var correction = Assert.Single(corrections);
        Assert.Equal("REPLACE", correction.GetProperty("kind").GetString());
        Assert.Equal(sortingId, correction.GetProperty("movementId").GetInt64());
        Assert.Equal("SORTING", correction.GetProperty("movementType").GetString());
        Assert.Equal(475m, correction.GetProperty("quantityKg").GetDecimal());
        Assert.Equal("MEASUREMENT_ERROR", correction.GetProperty("reasonCode").GetString());
        Assert.Equal("Scale was not zeroed", correction.GetProperty("reasonComment").GetString());
        Assert.Equal("Sup One", correction.GetProperty("authorName").GetString());
        Assert.False(correction.TryGetProperty("authorId", out _));
        Assert.True(correction.TryGetProperty("correctedAt", out _));
    }

    [Fact]
    public async Task Replacing_the_last_movement_updates_the_quantity_of_the_batch()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var shipmentId = MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batchCode, shipmentId, station, 460m);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var after = await GetBatchJsonAsync(batchCode);
        Assert.Equal("SHIPPED", after.GetProperty("status").GetString());
        Assert.Equal(460m, after.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(470m, Movement(after, "SHIPMENT").GetProperty("originalQuantityKg").GetDecimal());
    }

    [Fact]
    public async Task A_comment_is_optional_when_the_reason_is_not_OTHER()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        // No comment at all (null), and a reason code in lower case.
        var response = await ReplaceAsync(supervisor, batchCode, sortingId, station, 475m, reasonCode: "data_entry_error");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var correction = (await GetBatchJsonAsync(batchCode)).GetProperty("corrections").EnumerateArray().Single();
        Assert.Equal("DATA_ENTRY_ERROR", correction.GetProperty("reasonCode").GetString());
        Assert.Equal("", correction.GetProperty("reasonComment").GetString());
    }

    [Fact]
    public async Task Each_correction_keeps_the_name_of_its_author()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var first = NewSupervisor("sup-id-1", "Sup One");
        using var second = NewSupervisor("sup-id-2", "Sup Two");

        Assert.Equal(HttpStatusCode.Created, (await ReplaceAsync(first, batchCode, sortingId, station, 478m)).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await ReplaceAsync(second, batchCode, sortingId, station, 475m)).StatusCode);

        var batch = await GetBatchJsonAsync(batchCode);
        var names = batch.GetProperty("corrections").EnumerateArray()
            .Select(c => c.GetProperty("authorName").GetString())
            .ToList();
        Assert.Equal(new List<string?> { "Sup One", "Sup Two" }, names);

        // The valid version is the latest correction.
        var sorting = Movement(batch, "SORTING");
        Assert.Equal(475m, sorting.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(480m, sorting.GetProperty("originalQuantityKg").GetDecimal());
        Assert.Equal(2, sorting.GetProperty("correctionCount").GetInt32());
    }

    // ---------- Cancel ----------

    [Fact]
    public async Task Cancelling_the_last_movement_sends_the_batch_one_step_back_and_the_step_can_be_entered_again()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var shipmentId = MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT");
        using var supervisor = NewSupervisor();

        var cancelled = await CancelAsync(supervisor, batchCode, shipmentId, "OTHER", "The truck never left");

        Assert.Equal(HttpStatusCode.Created, cancelled.StatusCode);
        Assert.NotNull(cancelled.Headers.Location);
        Assert.Equal("", await cancelled.Content.ReadAsStringAsync());

        var after = await GetBatchJsonAsync(batchCode);
        Assert.Equal("PACKED", after.GetProperty("status").GetString());
        Assert.Equal(470m, after.GetProperty("quantityKg").GetDecimal());

        // The cancelled movement stays in the list, marked as cancelled.
        Assert.Equal(4, after.GetProperty("movements").GetArrayLength());
        var shipment = Movement(after, "SHIPMENT");
        Assert.True(shipment.GetProperty("isCancelled").GetBoolean());
        Assert.Equal(1, shipment.GetProperty("correctionCount").GetInt32());

        var correction = after.GetProperty("corrections").EnumerateArray().Single();
        Assert.Equal("CANCEL", correction.GetProperty("kind").GetString());
        Assert.Equal("OTHER", correction.GetProperty("reasonCode").GetString());
        Assert.Equal("The truck never left", correction.GetProperty("reasonComment").GetString());

        // The writer can enter the SHIPMENT again: the batch was really sent one step back.
        await AddMovementAsync(batchCode, station, "SHIPMENT", 465m);
        var shippedAgain = await GetBatchJsonAsync(batchCode);
        Assert.Equal("SHIPPED", shippedAgain.GetProperty("status").GetString());
        Assert.Equal(465m, shippedAgain.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(5, shippedAgain.GetProperty("movements").GetArrayLength());
    }

    [Fact]
    public async Task Cancelling_steps_one_by_one_brings_the_batch_back_to_RECEIVED()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        using var supervisor = NewSupervisor();

        foreach (var movementType in new[] { "SHIPMENT", "PACKING", "SORTING" })
        {
            var id = MovementId(await GetBatchJsonAsync(batchCode), movementType);
            Assert.Equal(HttpStatusCode.Created, (await CancelAsync(supervisor, batchCode, id)).StatusCode);
        }

        var batch = await GetBatchJsonAsync(batchCode);
        Assert.Equal("RECEIVED", batch.GetProperty("status").GetString());
        Assert.Equal(500m, batch.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(3, batch.GetProperty("corrections").GetArrayLength());
    }

    [Fact]
    public async Task The_RECEPTION_cannot_be_cancelled()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        var receptionId = MovementId(await GetBatchJsonAsync(batchCode), "RECEPTION");
        using var supervisor = NewSupervisor();

        var response = await CancelAsync(supervisor, batchCode, receptionId);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50307);
    }

    [Fact]
    public async Task Only_the_last_valid_movement_can_be_cancelled()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await CancelAsync(supervisor, batchCode, sortingId);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50306);
    }

    [Fact]
    public async Task A_cancelled_movement_cannot_be_cancelled_again_nor_replaced()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var shipmentId = MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT");
        using var supervisor = NewSupervisor();
        Assert.Equal(HttpStatusCode.Created, (await CancelAsync(supervisor, batchCode, shipmentId)).StatusCode);

        var again = await CancelAsync(supervisor, batchCode, shipmentId);
        var replaced = await ReplaceAsync(supervisor, batchCode, shipmentId, station, 465m);

        await TestData.AssertProcedureErrorAsync(again, HttpStatusCode.UnprocessableEntity, 50305);
        await TestData.AssertProcedureErrorAsync(replaced, HttpStatusCode.UnprocessableEntity, 50305);
    }

    // ---------- Replace: refused by a rule of the procedure ----------

    [Fact]
    public async Task A_quantity_higher_than_the_previous_step_is_refused()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batchCode, sortingId, station, 500.01m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50304);
    }

    [Fact]
    public async Task A_quantity_lower_than_the_next_step_is_refused()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batchCode, sortingId, station, 469.99m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50304);
    }

    [Fact]
    public async Task The_same_values_as_the_current_ones_are_refused()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        // The SORTING was entered on this station, at 480, at 2026-10-14T08:00:00Z.
        var response = await ReplaceAsync(supervisor, batchCode, sortingId, station, 480m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50308);
    }

    [Fact]
    public async Task A_station_without_the_function_of_the_movement_is_refused()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        var receptionOnly = await CreateStationAsync("RECEPTION");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batchCode, sortingId, receptionOnly, 475m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50303);
    }

    [Fact]
    public async Task An_unknown_station_is_refused_with_404()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(supervisor, batchCode, sortingId, "ZZ-NO-SUCH-STATION", 475m);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50102);
    }

    [Fact]
    public async Task An_unknown_batch_is_refused_with_404()
    {
        using var supervisor = NewSupervisor();

        var replaced = await ReplaceAsync(supervisor, "ZZ-NO-SUCH-BATCH", 1, "ZZ-S", 475m);
        var cancelled = await CancelAsync(supervisor, "ZZ-NO-SUCH-BATCH", 1);

        await TestData.AssertProcedureErrorAsync(replaced, HttpStatusCode.NotFound, 50100);
        await TestData.AssertProcedureErrorAsync(cancelled, HttpStatusCode.NotFound, 50100);
    }

    [Fact]
    public async Task A_movement_of_another_batch_is_refused_with_404()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var (_, otherBatchCode) = await CreateShippedBatchAsync();
        var otherSortingId = MovementId(await GetBatchJsonAsync(otherBatchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var replaced = await ReplaceAsync(supervisor, batchCode, otherSortingId, station, 475m);
        var cancelled = await CancelAsync(supervisor, batchCode, otherSortingId);

        await TestData.AssertProcedureErrorAsync(replaced, HttpStatusCode.NotFound, 50103);
        await TestData.AssertProcedureErrorAsync(cancelled, HttpStatusCode.NotFound, 50103);
    }

    [Fact]
    public async Task An_unknown_reason_is_refused_with_400()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var replaced = await ReplaceAsync(supervisor, batchCode, sortingId, station, 475m, reasonCode: "BECAUSE");
        var cancelled = await CancelAsync(supervisor, batchCode, MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT"), "BECAUSE");

        await TestData.AssertProcedureErrorAsync(replaced, HttpStatusCode.BadRequest, 50407);
        await TestData.AssertProcedureErrorAsync(cancelled, HttpStatusCode.BadRequest, 50407);
    }

    [Fact]
    public async Task The_reason_OTHER_needs_a_comment()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var replaced = await ReplaceAsync(supervisor, batchCode, sortingId, station, 475m, "OTHER", "   ");
        var cancelled = await CancelAsync(supervisor, batchCode, MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT"), "OTHER", null);

        await TestData.AssertProcedureErrorAsync(replaced, HttpStatusCode.BadRequest, 50408);
        await TestData.AssertProcedureErrorAsync(cancelled, HttpStatusCode.BadRequest, 50408);
    }

    [Fact]
    public async Task A_refused_correction_changes_nothing()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        var beforeText = await (await Writer.GetAsync($"/batches/{batchCode}")).Content.ReadAsStringAsync();
        using var supervisor = NewSupervisor();

        var refused = await ReplaceAsync(supervisor, batchCode, sortingId, station, 500.01m);
        var refusedCancel = await CancelAsync(supervisor, batchCode, sortingId);

        Assert.Equal(HttpStatusCode.UnprocessableEntity, refused.StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, refusedCancel.StatusCode);
        var afterText = await (await Writer.GetAsync($"/batches/{batchCode}")).Content.ReadAsStringAsync();
        Assert.Equal(beforeText, afterText);
    }

    // ---------- Refused before the procedure (shape of the request) ----------

    [Fact]
    public async Task A_replace_without_fields_is_refused_with_the_missing_fields()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await supervisor.PostAsync(
            $"/batches/{batchCode}/movements/{sortingId}/replace", TestData.Json("{}"));

        await TestData.AssertShapeErrorAsync(response, "stationCode", "quantityKg", "occurredAt", "reasonCode");
    }

    [Fact]
    public async Task A_cancel_without_reason_is_refused_with_the_missing_field()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        var shipmentId = MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT");
        using var supervisor = NewSupervisor();

        var response = await supervisor.PostAsync(
            $"/batches/{batchCode}/movements/{shipmentId}/cancel", TestData.Json("{}"));

        await TestData.AssertShapeErrorAsync(response, "reasonCode");
    }

    [Fact]
    public async Task A_comment_of_501_characters_is_refused_before_the_procedure()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(
            supervisor, batchCode, sortingId, station, 475m, "OTHER", new string('c', 501));

        await TestData.AssertShapeErrorAsync(response, "reasonComment");
    }

    [Fact]
    public async Task A_comment_of_500_characters_is_accepted_and_kept_whole()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();
        var comment = new string('c', 500);

        var response = await ReplaceAsync(supervisor, batchCode, sortingId, station, 475m, "OTHER", comment);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var correction = (await GetBatchJsonAsync(batchCode)).GetProperty("corrections").EnumerateArray().Single();
        Assert.Equal(comment, correction.GetProperty("reasonComment").GetString());
    }

    [Fact]
    public async Task A_time_without_Z_or_offset_is_refused()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var supervisor = NewSupervisor();

        var response = await ReplaceAsync(
            supervisor, batchCode, sortingId, station, 475m, occurredAt: "2026-10-14T09:30:00");

        await TestData.AssertShapeErrorAsync(response, "occurredAt");
    }

    [Fact]
    public async Task A_movement_id_that_is_not_a_number_is_refused_with_400()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        using var supervisor = NewSupervisor();

        var replaced = await supervisor.PostAsync(
            $"/batches/{batchCode}/movements/abc/replace", TestData.Json("{}"));
        var cancelled = await supervisor.PostAsync(
            $"/batches/{batchCode}/movements/abc/cancel", TestData.Json("{}"));

        Assert.Equal(HttpStatusCode.BadRequest, replaced.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, cancelled.StatusCode);
    }

    // ---------- Who may correct ----------

    [Fact]
    public async Task A_supervisor_whose_token_gives_no_identity_cannot_correct()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var anonymous = api.CreateClient("supervisor", withoutIdentity: true);

        var replaced = await ReplaceAsync(anonymous, batchCode, sortingId, station, 475m);
        var cancelled = await CancelAsync(anonymous, batchCode, MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT"));

        Assert.Equal(HttpStatusCode.Forbidden, replaced.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, cancelled.StatusCode);
        Assert.Equal(0, (await GetBatchJsonAsync(batchCode)).GetProperty("corrections").GetArrayLength());
    }

    [Theory]
    [InlineData("writer")]
    [InlineData("reader")]
    public async Task A_writer_or_a_reader_cannot_correct(string role)
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        using var client = api.CreateClient(role);

        var replaced = await ReplaceAsync(client, batchCode, sortingId, station, 475m);
        var cancelled = await CancelAsync(client, batchCode, MovementId(await GetBatchJsonAsync(batchCode), "SHIPMENT"));

        Assert.Equal(HttpStatusCode.Forbidden, replaced.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, cancelled.StatusCode);
        Assert.Equal(0, (await GetBatchJsonAsync(batchCode)).GetProperty("corrections").GetArrayLength());
    }

    [Fact]
    public async Task A_supervisor_cannot_enter_a_movement()
    {
        var (station, batchCode) = await CreateShippedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await supervisor.PostAsJsonAsync($"/batches/{batchCode}/movements", new
        {
            stationCode = station,
            movementType = "SORTING",
            quantityKg = 400m,
            occurredAt = "2026-10-14T08:00:00Z",
        });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task A_supervisor_can_read_a_batch()
    {
        var (_, batchCode) = await CreateShippedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await supervisor.GetAsync($"/batches/{batchCode}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
