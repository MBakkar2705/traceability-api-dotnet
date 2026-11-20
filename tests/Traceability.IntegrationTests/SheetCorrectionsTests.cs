using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Traceability.IntegrationTests;

// Lot 12b: the correction of the sheet of a batch (POST /batches/{batchCode}/correct) and what
// GET /batches/{batchCode} returns about it, on the test database. Like CorrectionsTests, every test
// creates its own farms, stations and batches with unique codes. The default client is a writer (it
// enters the data); the corrections are made by a client with the role supervisor.
[Collection(ApiCollection.Name)]
public class SheetCorrectionsTests(ApiFixture api)
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

    // A RECEIVED batch: variety Roma, one RECEPTION of 500 kg at 2026-10-14T06:00:00Z on a station that
    // has all the functions. The harvest day is 2026-10-14 unless given.
    private async Task<(string FarmCode, string StationCode, string BatchCode)> CreateReceivedBatchAsync(
        string harvestDate = "2026-10-14")
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync(AllFunctions);
        var batch = TestData.NewCode();
        var created = await Writer.PostAsJsonAsync("/batches", new
        {
            batchCode = batch,
            farmCode = farm,
            variety = "Roma",
            harvestDate,
            quantityKg = 500m,
            stationCode = station,
            occurredAt = "2026-10-14T06:00:00Z",
        });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        return (farm, station, batch);
    }

    private async Task AddMovementAsync(string batchCode, string stationCode, string movementType, decimal quantityKg)
    {
        var response = await Writer.PostAsJsonAsync($"/batches/{batchCode}/movements", new
        {
            stationCode,
            movementType,
            quantityKg,
            occurredAt = TestData.TimeOfStep(movementType),
        });
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
    }

    // A SHIPPED batch: RECEPTION 500, SORTING 480, PACKING 470, SHIPMENT 470.
    private async Task<(string FarmCode, string StationCode, string BatchCode)> CreateShippedBatchAsync()
    {
        var (farm, station, batch) = await CreateReceivedBatchAsync();
        await AddMovementAsync(batch, station, "SORTING", 480m);
        await AddMovementAsync(batch, station, "PACKING", 470m);
        await AddMovementAsync(batch, station, "SHIPMENT", 470m);
        return (farm, station, batch);
    }

    // With no client given, the writer reads. A writer gets authorName null: the names of the authors
    // are given to the auditor and the supervisor only.
    private async Task<JsonElement> GetBatchJsonAsync(string batchCode, HttpClient? client = null)
    {
        var response = await (client ?? Writer).GetAsync($"/batches/{batchCode}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await TestData.ReadJsonAsync(response);
    }

    private static long MovementId(JsonElement batch, string movementType) =>
        batch.GetProperty("movements").EnumerateArray()
            .Single(m => m.GetProperty("movementType").GetString() == movementType)
            .GetProperty("movementId").GetInt64();

    // The four new values are always given: a field that does not change repeats its current value.
    private static Task<HttpResponseMessage> CorrectAsync(
        HttpClient client, string batchCode, string? newBatchCode, string? farmCode,
        string? variety = "Roma", string? harvestDate = "2026-10-14",
        string? reasonCode = "DATA_ENTRY_ERROR", string? reasonComment = null) =>
        client.PostAsJsonAsync($"/batches/{batchCode}/correct", new
        {
            newBatchCode,
            farmCode,
            variety,
            harvestDate,
            reasonCode,
            reasonComment,
        });

    // The sheet is as CreateReceivedBatchAsync made it: same code, farm, variety and harvest day, and
    // no correction.
    private async Task AssertUnchangedAsync(string batchCode, string farmCode, string harvestDate = "2026-10-14")
    {
        var batch = await GetBatchJsonAsync(batchCode);
        Assert.Equal(batchCode, batch.GetProperty("batchCode").GetString());
        Assert.Equal(farmCode, batch.GetProperty("farmCode").GetString());
        Assert.Equal("Roma", batch.GetProperty("variety").GetString());
        Assert.Equal(harvestDate, batch.GetProperty("harvestDate").GetString());
        Assert.Equal(0, batch.GetProperty("sheetCorrections").GetArrayLength());
    }

    // authorName is always in the answer: the name for the auditor and the supervisor, null for the
    // other roles. The identifier of the author is never there.
    private static void AssertAuthorName(JsonElement item, string? expected)
    {
        Assert.True(item.TryGetProperty("authorName", out var name));
        if (expected is null)
        {
            Assert.Equal(JsonValueKind.Null, name.ValueKind);
        }
        else
        {
            Assert.Equal(expected, name.GetString());
        }

        Assert.False(item.TryGetProperty("authorId", out _));
    }

    // ---------- What a batch without correction looks like ----------

    [Fact]
    public async Task A_batch_without_correction_has_an_empty_list_of_sheet_corrections()
    {
        var (_, _, batchCode) = await CreateShippedBatchAsync();

        var batch = await GetBatchJsonAsync(batchCode);

        Assert.Equal(0, batch.GetProperty("sheetCorrections").GetArrayLength());
        Assert.Equal(0, batch.GetProperty("corrections").GetArrayLength());
    }

    // ---------- Accepted corrections ----------

    [Fact]
    public async Task A_supervisor_corrects_the_code_and_the_old_code_is_kept()
    {
        var (farm, _, batchCode) = await CreateShippedBatchAsync();
        var newCode = TestData.NewCode();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batchCode, newCode, farm);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(response.Headers.Location);
        Assert.EndsWith($"/batches/{newCode}", response.Headers.Location.ToString());
        Assert.Equal("", await response.Content.ReadAsStringAsync());

        var batch = await GetBatchJsonAsync(newCode, supervisor);
        Assert.Equal(newCode, batch.GetProperty("batchCode").GetString());

        var correction = Assert.Single(batch.GetProperty("sheetCorrections").EnumerateArray());
        Assert.Equal(batchCode, correction.GetProperty("oldBatchCode").GetString());
        Assert.Equal(newCode, correction.GetProperty("newBatchCode").GetString());
        Assert.Equal(farm, correction.GetProperty("oldFarmCode").GetString());
        Assert.Equal(farm, correction.GetProperty("newFarmCode").GetString());
        Assert.Equal("Roma", correction.GetProperty("oldVariety").GetString());
        Assert.Equal("Roma", correction.GetProperty("newVariety").GetString());
        Assert.Equal("2026-10-14", correction.GetProperty("oldHarvestDate").GetString());
        Assert.Equal("2026-10-14", correction.GetProperty("newHarvestDate").GetString());
        Assert.Equal("DATA_ENTRY_ERROR", correction.GetProperty("reasonCode").GetString());
        Assert.Equal("", correction.GetProperty("reasonComment").GetString());
        AssertAuthorName(correction, "Sup One");
        Assert.True(correction.TryGetProperty("correctedAt", out _));

        // The status and the quantity of the batch never change with a correction of the sheet.
        Assert.Equal("SHIPPED", batch.GetProperty("status").GetString());
        Assert.Equal(470m, batch.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(4, batch.GetProperty("movements").GetArrayLength());
    }

    [Fact]
    public async Task Several_fields_can_be_corrected_at_once()
    {
        var (farm, _, batchCode) = await CreateShippedBatchAsync();
        var otherFarm = await CreateFarmAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(
            supervisor, batchCode, batchCode, otherFarm, "Cherry", "2026-10-13",
            "OTHER", "Wrong farm, variety and day on the paper sheet");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var batch = await GetBatchJsonAsync(batchCode, supervisor);
        Assert.Equal(batchCode, batch.GetProperty("batchCode").GetString());
        Assert.Equal(otherFarm, batch.GetProperty("farmCode").GetString());
        Assert.Equal("Cherry", batch.GetProperty("variety").GetString());
        Assert.Equal("2026-10-13", batch.GetProperty("harvestDate").GetString());

        var correction = Assert.Single(batch.GetProperty("sheetCorrections").EnumerateArray());
        Assert.Equal(batchCode, correction.GetProperty("oldBatchCode").GetString());
        Assert.Equal(batchCode, correction.GetProperty("newBatchCode").GetString());
        Assert.Equal(farm, correction.GetProperty("oldFarmCode").GetString());
        Assert.Equal(otherFarm, correction.GetProperty("newFarmCode").GetString());
        Assert.Equal("Roma", correction.GetProperty("oldVariety").GetString());
        Assert.Equal("Cherry", correction.GetProperty("newVariety").GetString());
        Assert.Equal("2026-10-14", correction.GetProperty("oldHarvestDate").GetString());
        Assert.Equal("2026-10-13", correction.GetProperty("newHarvestDate").GetString());
        Assert.Equal("OTHER", correction.GetProperty("reasonCode").GetString());
        Assert.Equal("Wrong farm, variety and day on the paper sheet", correction.GetProperty("reasonComment").GetString());

        // The movements, the status and the quantity are not touched.
        Assert.Equal("SHIPPED", batch.GetProperty("status").GetString());
        Assert.Equal(470m, batch.GetProperty("quantityKg").GetDecimal());
        Assert.Equal(4, batch.GetProperty("movements").GetArrayLength());
    }

    // The reception is on 2026-10-14: a harvest day of 2026-10-14 (the same day) is accepted.
    [Fact]
    public async Task A_harvest_on_the_day_of_the_reception_is_accepted()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync("2026-10-13");
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batchCode, batchCode, farm, harvestDate: "2026-10-14");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var batch = await GetBatchJsonAsync(batchCode);
        Assert.Equal("2026-10-14", batch.GetProperty("harvestDate").GetString());
    }

    // A change of letter case only is a change (binary comparison in the database).
    [Fact]
    public async Task A_change_of_letter_case_only_is_accepted()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        var lowerCode = batchCode.ToLowerInvariant();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batchCode, lowerCode, farm);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var batch = await GetBatchJsonAsync(lowerCode);
        Assert.Equal(lowerCode, batch.GetProperty("batchCode").GetString());
        var correction = Assert.Single(batch.GetProperty("sheetCorrections").EnumerateArray());
        Assert.Equal(batchCode, correction.GetProperty("oldBatchCode").GetString());
        Assert.Equal(lowerCode, correction.GetProperty("newBatchCode").GetString());
    }

    // A batch may take back a code it had: the old codes of a batch stay reserved for it.
    [Fact]
    public async Task A_batch_can_take_back_one_of_its_own_old_codes()
    {
        var (farm, _, firstCode) = await CreateReceivedBatchAsync();
        var secondCode = TestData.NewCode();
        using var supervisor = NewSupervisor();

        var toSecond = await CorrectAsync(supervisor, firstCode, secondCode, farm);
        var backToFirst = await CorrectAsync(supervisor, secondCode, firstCode, farm);

        Assert.Equal(HttpStatusCode.Created, toSecond.StatusCode);
        Assert.Equal(HttpStatusCode.Created, backToFirst.StatusCode);
        var batch = await GetBatchJsonAsync(firstCode);
        Assert.Equal(firstCode, batch.GetProperty("batchCode").GetString());
        Assert.Equal(2, batch.GetProperty("sheetCorrections").GetArrayLength());
    }

    [Fact]
    public async Task A_comment_is_optional_when_the_reason_is_not_OTHER_and_the_reason_may_be_in_lower_case()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        var newCode = TestData.NewCode();
        using var supervisor = NewSupervisor();

        // No comment at all (null), and a reason code in lower case.
        var response = await CorrectAsync(supervisor, batchCode, newCode, farm, reasonCode: "data_entry_error");

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var correction = (await GetBatchJsonAsync(newCode)).GetProperty("sheetCorrections").EnumerateArray().Single();
        Assert.Equal("DATA_ENTRY_ERROR", correction.GetProperty("reasonCode").GetString());
        Assert.Equal("", correction.GetProperty("reasonComment").GetString());
    }

    [Fact]
    public async Task A_comment_of_500_characters_is_accepted_and_kept_whole()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        var newCode = TestData.NewCode();
        using var supervisor = NewSupervisor();
        var comment = new string('c', 500);

        var response = await CorrectAsync(supervisor, batchCode, newCode, farm, reasonCode: "OTHER", reasonComment: comment);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var correction = (await GetBatchJsonAsync(newCode)).GetProperty("sheetCorrections").EnumerateArray().Single();
        Assert.Equal(comment, correction.GetProperty("reasonComment").GetString());
    }

    // ---------- Reading a batch by an old code ----------

    [Fact]
    public async Task Reading_by_an_old_code_finds_the_batch_under_its_current_code()
    {
        var (farm, _, firstCode) = await CreateReceivedBatchAsync();
        var secondCode = TestData.NewCode();
        var thirdCode = TestData.NewCode();
        using var supervisor = NewSupervisor();
        Assert.Equal(HttpStatusCode.Created, (await CorrectAsync(supervisor, firstCode, secondCode, farm)).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await CorrectAsync(supervisor, secondCode, thirdCode, farm)).StatusCode);

        var byFirst = await GetBatchJsonAsync(firstCode);
        var bySecond = await GetBatchJsonAsync(secondCode);

        // Both old codes lead to the same batch, which carries its current code.
        Assert.Equal(thirdCode, byFirst.GetProperty("batchCode").GetString());
        Assert.Equal(thirdCode, bySecond.GetProperty("batchCode").GetString());
        var corrections = byFirst.GetProperty("sheetCorrections").EnumerateArray().ToList();
        Assert.Equal(2, corrections.Count);
        Assert.Equal(firstCode, corrections[0].GetProperty("oldBatchCode").GetString());
        Assert.Equal(secondCode, corrections[0].GetProperty("newBatchCode").GetString());
        Assert.Equal(secondCode, corrections[1].GetProperty("oldBatchCode").GetString());
        Assert.Equal(thirdCode, corrections[1].GetProperty("newBatchCode").GetString());
    }

    // ---------- Writing with an old code ----------

    [Fact]
    public async Task Writing_with_an_old_code_is_refused_with_404_and_the_message_gives_the_current_code()
    {
        var (farm, station, batchCode) = await CreateReceivedBatchAsync();
        var newCode = TestData.NewCode();
        using var supervisor = NewSupervisor();
        Assert.Equal(HttpStatusCode.Created, (await CorrectAsync(supervisor, batchCode, newCode, farm)).StatusCode);
        var receptionId = MovementId(await GetBatchJsonAsync(newCode), "RECEPTION");

        var added = await Writer.PostAsJsonAsync($"/batches/{batchCode}/movements", new
        {
            stationCode = station,
            movementType = "SORTING",
            quantityKg = 480m,
            occurredAt = "2026-10-14T08:00:00Z",
        });
        var replaced = await supervisor.PostAsJsonAsync($"/batches/{batchCode}/movements/{receptionId}/replace", new
        {
            stationCode = station,
            quantityKg = 490m,
            occurredAt = "2026-10-14T06:00:00Z",
            reasonCode = "DATA_ENTRY_ERROR",
            reasonComment = (string?)null,
        });
        var cancelled = await supervisor.PostAsJsonAsync($"/batches/{batchCode}/movements/{receptionId}/cancel", new
        {
            reasonCode = "DATA_ENTRY_ERROR",
            reasonComment = (string?)null,
        });
        var corrected = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm);

        // The message of the first refusal says which code is the right one.
        Assert.Equal(HttpStatusCode.NotFound, added.StatusCode);
        var body = await TestData.ReadJsonAsync(added);
        Assert.Equal(50104, body.GetProperty("errorCode").GetInt32());
        Assert.Contains(newCode, body.GetProperty("detail").GetString());

        await TestData.AssertProcedureErrorAsync(replaced, HttpStatusCode.NotFound, 50104);
        await TestData.AssertProcedureErrorAsync(cancelled, HttpStatusCode.NotFound, 50104);
        await TestData.AssertProcedureErrorAsync(corrected, HttpStatusCode.NotFound, 50104);

        // Nothing was written under the batch: still its reception only, and one correction of the sheet.
        var batch = await GetBatchJsonAsync(newCode);
        Assert.Equal(1, batch.GetProperty("movements").GetArrayLength());
        Assert.Equal(0, batch.GetProperty("corrections").GetArrayLength());
        Assert.Equal(1, batch.GetProperty("sheetCorrections").GetArrayLength());
    }

    [Fact]
    public async Task Creating_a_batch_with_an_old_code_of_another_batch_is_refused_with_409()
    {
        var (farm, station, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();
        Assert.Equal(HttpStatusCode.Created, (await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm)).StatusCode);

        var response = await Writer.PostAsJsonAsync("/batches", new
        {
            batchCode,
            farmCode = farm,
            variety = "Roma",
            harvestDate = "2026-10-14",
            quantityKg = 500m,
            stationCode = station,
            occurredAt = "2026-10-14T06:00:00Z",
        });

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.Conflict, 50203);
    }

    // ---------- The harvest day against the reception (50309) ----------

    [Fact]
    public async Task Creating_a_batch_harvested_after_its_reception_is_refused_with_422()
    {
        var farm = await CreateFarmAsync();
        var station = await CreateStationAsync("RECEPTION");

        // The reception is on 2026-10-14, the harvest day is the next day.
        var response = await Writer.PostAsJsonAsync("/batches", new
        {
            batchCode = TestData.NewCode(),
            farmCode = farm,
            variety = "Roma",
            harvestDate = "2026-10-15",
            quantityKg = 500m,
            stationCode = station,
            occurredAt = "2026-10-14T06:00:00Z",
        });

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50309);
    }

    [Fact]
    public async Task Moving_the_reception_before_the_harvest_day_is_refused_with_422()
    {
        var (farm, station, batchCode) = await CreateReceivedBatchAsync();
        var receptionId = MovementId(await GetBatchJsonAsync(batchCode), "RECEPTION");
        using var supervisor = NewSupervisor();

        // The harvest day is 2026-10-14: a reception on the 13th would be before it.
        var response = await supervisor.PostAsJsonAsync($"/batches/{batchCode}/movements/{receptionId}/replace", new
        {
            stationCode = station,
            quantityKg = 500m,
            occurredAt = "2026-10-13T20:00:00Z",
            reasonCode = "DATA_ENTRY_ERROR",
            reasonComment = (string?)null,
        });

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50309);
        await AssertUnchangedAsync(batchCode, farm);
    }

    // ---------- Refused corrections ----------

    [Fact]
    public async Task Missing_fields_are_refused_with_400_before_the_procedure()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await supervisor.PostAsJsonAsync($"/batches/{batchCode}/correct", new { });

        await TestData.AssertShapeErrorAsync(
            response, "newBatchCode", "farmCode", "variety", "harvestDate", "reasonCode");
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task Malformed_or_too_long_codes_are_refused_with_400_before_the_procedure()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var badShape = await CorrectAsync(supervisor, batchCode, "bad code!", farm);
        var tooLongBatchCode = await CorrectAsync(supervisor, batchCode, new string('A', 31), farm);
        var tooLongFarmCode = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), new string('F', 21));
        var tooLongVariety = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm, new string('v', 51));

        await TestData.AssertShapeErrorAsync(badShape, "newBatchCode");
        await TestData.AssertShapeErrorAsync(tooLongBatchCode, "newBatchCode");
        await TestData.AssertShapeErrorAsync(tooLongFarmCode, "farmCode");
        await TestData.AssertShapeErrorAsync(tooLongVariety, "variety");
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task An_empty_new_code_is_refused_with_400_by_the_procedure()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batchCode, "", farm);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50400);
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task A_reason_that_is_not_accepted_for_a_sheet_is_refused_with_400()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        // MEASUREMENT_ERROR is for the quantities of the movements, not for a sheet.
        var measurement = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm, reasonCode: "MEASUREMENT_ERROR");
        var unknown = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm, reasonCode: "BECAUSE");

        await TestData.AssertProcedureErrorAsync(measurement, HttpStatusCode.BadRequest, 50407);
        await TestData.AssertProcedureErrorAsync(unknown, HttpStatusCode.BadRequest, 50407);
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task The_reason_OTHER_needs_a_comment()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var blank = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm, reasonCode: "OTHER", reasonComment: "   ");
        var none = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), farm, reasonCode: "OTHER", reasonComment: null);

        await TestData.AssertProcedureErrorAsync(blank, HttpStatusCode.BadRequest, 50408);
        await TestData.AssertProcedureErrorAsync(none, HttpStatusCode.BadRequest, 50408);
        await AssertUnchangedAsync(batchCode, farm);
    }

    // The API refuses a comment of more than 500 characters before the procedure does (50409).
    [Fact]
    public async Task A_comment_of_501_characters_is_refused_before_the_procedure()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(
            supervisor, batchCode, TestData.NewCode(), farm, reasonCode: "OTHER", reasonComment: new string('c', 501));

        await TestData.AssertShapeErrorAsync(response, "reasonComment");
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task An_unknown_batch_is_refused_with_404()
    {
        var farm = await CreateFarmAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, TestData.NewCode(), TestData.NewCode(), farm);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50100);
    }

    [Fact]
    public async Task An_unknown_farm_is_refused_with_404()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batchCode, TestData.NewCode(), TestData.NewCode());

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.NotFound, 50101);
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task A_new_code_that_is_the_code_of_another_batch_is_refused_with_409()
    {
        var (farm1, _, batch1) = await CreateReceivedBatchAsync();
        var (farm2, _, batch2) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batch1, batch2, farm1);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.Conflict, 50202);
        await AssertUnchangedAsync(batch1, farm1);
        await AssertUnchangedAsync(batch2, farm2);
    }

    [Fact]
    public async Task A_new_code_that_is_an_old_code_of_another_batch_is_refused_with_409()
    {
        var (farm1, _, batch1) = await CreateReceivedBatchAsync();
        var (farm2, _, batch2) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();
        var renamed = TestData.NewCode();
        Assert.Equal(HttpStatusCode.Created, (await CorrectAsync(supervisor, batch1, renamed, farm1)).StatusCode);

        // batch1 was called batch1 before: that code is kept for it, so batch2 cannot take it.
        var response = await CorrectAsync(supervisor, batch2, batch1, farm2);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.Conflict, 50203);
        await AssertUnchangedAsync(batch2, farm2);
    }

    [Fact]
    public async Task Values_that_are_all_the_same_as_the_current_ones_are_refused_with_422()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        var response = await CorrectAsync(supervisor, batchCode, batchCode, farm);

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50308);
        await AssertUnchangedAsync(batchCode, farm);
    }

    [Fact]
    public async Task A_harvest_day_after_the_reception_is_refused_with_422()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var supervisor = NewSupervisor();

        // The reception is on 2026-10-14: the 15th is after it.
        var response = await CorrectAsync(supervisor, batchCode, batchCode, farm, harvestDate: "2026-10-15");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.UnprocessableEntity, 50309);
        await AssertUnchangedAsync(batchCode, farm);
    }

    // ---------- Who may correct a sheet ----------

    [Theory]
    [InlineData("writer")]
    [InlineData("reader")]
    [InlineData("auditor")]
    [InlineData("other")]
    public async Task Only_a_supervisor_may_correct_a_sheet(string role)
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var client = api.CreateClient(role);

        var response = await CorrectAsync(client, batchCode, TestData.NewCode(), farm);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        await AssertUnchangedAsync(batchCode, farm);
    }

    // Decision D5 of lot 11, for the sheets too: a valid token without sub or preferred_username has
    // no author to record, so it cannot correct (403, not 401) and nothing is recorded.
    [Fact]
    public async Task A_supervisor_without_identity_cannot_correct_a_sheet()
    {
        var (farm, _, batchCode) = await CreateReceivedBatchAsync();
        using var anonymous = api.CreateClient("supervisor", withoutIdentity: true);

        var response = await CorrectAsync(anonymous, batchCode, TestData.NewCode(), farm);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        await AssertUnchangedAsync(batchCode, farm);
    }

    // ---------- The names of the authors ----------

    // The auditor and the supervisor see the names of the authors; the other roles get authorName
    // null, in the movements, in the corrections of the movements and in the corrections of the
    // sheet. The identifiers of the authors are never in the answer.
    [Theory]
    [InlineData("auditor", true)]
    [InlineData("supervisor", true)]
    [InlineData("reader", false)]
    [InlineData("writer", false)]
    public async Task The_names_of_the_authors_are_given_to_the_auditor_and_the_supervisor_only(string role, bool seesNames)
    {
        var (farm, station, batchCode) = await CreateShippedBatchAsync();
        var supervisorId = "id-" + TestData.NewCode();
        using var supervisor = NewSupervisor(supervisorId, "Sup One");
        var sortingId = MovementId(await GetBatchJsonAsync(batchCode), "SORTING");
        var replaced = await supervisor.PostAsJsonAsync($"/batches/{batchCode}/movements/{sortingId}/replace", new
        {
            stationCode = station,
            quantityKg = 475m,
            occurredAt = "2026-10-14T08:00:00Z",
            reasonCode = "DATA_ENTRY_ERROR",
            reasonComment = (string?)null,
        });
        Assert.Equal(HttpStatusCode.Created, replaced.StatusCode);
        var newCode = TestData.NewCode();
        Assert.Equal(HttpStatusCode.Created, (await CorrectAsync(supervisor, batchCode, newCode, farm)).StatusCode);

        using var client = api.CreateClient(role);
        var batch = await GetBatchJsonAsync(newCode, client);

        // The four movements were entered by the default writer of the tests.
        var movements = batch.GetProperty("movements").EnumerateArray().ToList();
        Assert.Equal(4, movements.Count);
        Assert.All(movements, m => AssertAuthorName(m, seesNames ? TestAuth.DefaultUserName : null));

        var movementCorrection = Assert.Single(batch.GetProperty("corrections").EnumerateArray());
        AssertAuthorName(movementCorrection, seesNames ? "Sup One" : null);

        var sheetCorrection = Assert.Single(batch.GetProperty("sheetCorrections").EnumerateArray());
        AssertAuthorName(sheetCorrection, seesNames ? "Sup One" : null);

        Assert.DoesNotContain(supervisorId, batch.GetRawText());
        Assert.DoesNotContain(TestAuth.DefaultUserId, batch.GetRawText());
    }

    // ---------- Two corrections at the same time ----------

    // The corrections lock the sheet they correct, not the other batches. Two supervisors who give
    // the same new code to two different batches at the same moment are separated by the unique key
    // on the current codes: one answers 201, the other 409 (errorCode 50202), and one batch only has
    // the code afterwards. The test proves this outcome, whichever of the two comes first.
    [Fact]
    public async Task Two_corrections_to_the_same_new_code_on_two_batches_give_one_201_and_one_409()
    {
        var (farm1, _, batch1) = await CreateReceivedBatchAsync();
        var (farm2, _, batch2) = await CreateReceivedBatchAsync();
        var target = TestData.NewCode();
        using var first = NewSupervisor("sup-id-1", "Sup One");
        using var second = NewSupervisor("sup-id-2", "Sup Two");

        var results = await Task.WhenAll(
            CorrectAsync(first, batch1, target, farm1),
            CorrectAsync(second, batch2, target, farm2));

        var statuses = results.Select(r => r.StatusCode).OrderBy(s => s).ToList();
        Assert.Equal(new List<HttpStatusCode> { HttpStatusCode.Created, HttpStatusCode.Conflict }, statuses);
        await TestData.AssertProcedureErrorAsync(
            results.Single(r => r.StatusCode == HttpStatusCode.Conflict), HttpStatusCode.Conflict, 50202);

        // One batch has the code, the other one is exactly as it was.
        var holder = await GetBatchJsonAsync(target);
        Assert.Equal(target, holder.GetProperty("batchCode").GetString());
        Assert.Equal(1, holder.GetProperty("sheetCorrections").GetArrayLength());

        var firstWon = results[0].StatusCode == HttpStatusCode.Created;
        if (firstWon)
        {
            await AssertUnchangedAsync(batch2, farm2);
        }
        else
        {
            await AssertUnchangedAsync(batch1, farm1);
        }
    }
}
