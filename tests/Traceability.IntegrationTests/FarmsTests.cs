using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Traceability.IntegrationTests;

// F1 to F5: the farm routes, on the test database.
[Collection(ApiCollection.Name)]
public class FarmsTests(ApiFixture api)
{
    private HttpClient Client => api.Client;

    // F1: creation answers 201 with the farm; no technical id, no Location header
    // (there is no GET /farms/{code} route).
    [Fact]
    public async Task A_farm_is_created()
    {
        var code = TestData.NewCode();

        var response = await Client.PostAsJsonAsync("/farms", new { code, name = "Test farm", region = "Region A" });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.False(response.Headers.Contains("Location"));

        var body = await TestData.ReadJsonAsync(response);
        Assert.Equal(code, body.GetProperty("code").GetString());
        Assert.Equal("Test farm", body.GetProperty("name").GetString());
        Assert.Equal("Region A", body.GetProperty("region").GetString());
        Assert.False(body.TryGetProperty("farmId", out _));
    }

    // F2: the same code twice: 409 with errorCode 50200 (raised by the procedure).
    [Fact]
    public async Task A_code_already_taken_gives_409()
    {
        var code = TestData.NewCode();
        var first = await Client.PostAsJsonAsync("/farms", new { code, name = "Test farm", region = "Region A" });
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);

        var second = await Client.PostAsJsonAsync("/farms", new { code, name = "Other", region = "Region B" });

        await TestData.AssertProcedureErrorAsync(second, HttpStatusCode.Conflict, 50200);
    }

    // F3: an empty code goes through the API (shape only) and the procedure refuses it: 50400.
    [Fact]
    public async Task An_empty_code_gives_400_from_the_procedure()
    {
        var response = await Client.PostAsJsonAsync("/farms", new { code = "", name = "Test farm", region = "Region A" });

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50400);
    }

    // F4: the list. Other tests also create farms, so the checks are relative: the three
    // farms created here appear, in creation order; without parameters the page is 1 of 20.
    [Fact]
    public async Task The_list_returns_the_farms_in_creation_order_with_the_total()
    {
        var codes = new[] { TestData.NewCode(), TestData.NewCode(), TestData.NewCode() };
        foreach (var code in codes)
        {
            var created = await Client.PostAsJsonAsync("/farms", new { code, name = "Test farm", region = "Region A" });
            Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        }

        var everything = await TestData.ReadJsonAsync(await Client.GetAsync("/farms?pageNumber=1&pageSize=1000"));
        var totalCount = everything.GetProperty("totalCount").GetInt32();
        Assert.True(totalCount >= 3);

        var listed = everything.GetProperty("items").EnumerateArray()
            .Select(item => item.GetProperty("code").GetString())
            .ToList();
        var positions = codes.Select(code => listed.IndexOf(code)).ToList();
        Assert.DoesNotContain(-1, positions);
        Assert.Equal(positions.OrderBy(p => p).ToList(), positions);

        var defaultPage = await TestData.ReadJsonAsync(await Client.GetAsync("/farms"));
        Assert.Equal(1, defaultPage.GetProperty("pageNumber").GetInt32());
        Assert.Equal(20, defaultPage.GetProperty("pageSize").GetInt32());
        Assert.True(defaultPage.GetProperty("items").GetArrayLength() <= 20);
        Assert.Equal(totalCount, defaultPage.GetProperty("totalCount").GetInt32());
    }

    // F5: an invalid page or page size is refused by the procedure (50404) ...
    [Theory]
    [InlineData("pageNumber=0")]
    [InlineData("pageNumber=-1")]
    [InlineData("pageSize=0")]
    [InlineData("pageSize=1001")]
    public async Task An_invalid_page_gives_400_from_the_procedure(string query)
    {
        var response = await Client.GetAsync($"/farms?{query}");

        await TestData.AssertProcedureErrorAsync(response, HttpStatusCode.BadRequest, 50404);
    }

    // ... and a page beyond the end is not an error: no items, but the same total.
    [Fact]
    public async Task A_page_beyond_the_end_is_empty_with_the_same_total()
    {
        var firstPage = await TestData.ReadJsonAsync(await Client.GetAsync("/farms"));
        var beyond = await TestData.ReadJsonAsync(await Client.GetAsync("/farms?pageNumber=999999&pageSize=20"));

        Assert.Equal(0, beyond.GetProperty("items").GetArrayLength());
        Assert.Equal(firstPage.GetProperty("totalCount").GetInt32(), beyond.GetProperty("totalCount").GetInt32());
        Assert.Equal(999999, beyond.GetProperty("pageNumber").GetInt32());
    }

    // NVARCHAR(100) for the name and the region. The expectation is the behaviour we want: a 400
    // on the field. It is NOT known whether the API does it today: a failure tells what happens.
    [Fact]
    public async Task A_farm_name_that_is_too_long_gives_400()
    {
        var response = await Client.PostAsJsonAsync(
            "/farms", new { code = TestData.NewCode(), name = new string('N', 101), region = "Region A" });

        Assert.True(response.StatusCode == HttpStatusCode.BadRequest, await TestData.DescribeAsync(response));
        await TestData.AssertShapeErrorAsync(response, "name");
    }

    [Fact]
    public async Task A_farm_region_that_is_too_long_gives_400()
    {
        var response = await Client.PostAsJsonAsync(
            "/farms", new { code = TestData.NewCode(), name = "Test farm", region = new string('R', 101) });

        Assert.True(response.StatusCode == HttpStatusCode.BadRequest, await TestData.DescribeAsync(response));
        await TestData.AssertShapeErrorAsync(response, "region");
    }
}
