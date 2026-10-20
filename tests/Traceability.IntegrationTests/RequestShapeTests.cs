using System.Net;
using System.Net.Http.Json;

namespace Traceability.IntegrationTests;

// T1 and T2: errors of shape, raised by the API itself before any procedure call.
[Collection(ApiCollection.Name)]
public class RequestShapeTests(ApiFixture api)
{
    private HttpClient Client => api.Client;

    // T1: required fields missing from the JSON body: 400 listing each missing field.
    [Fact]
    public async Task All_required_fields_missing_gives_400_listing_them()
    {
        var response = await Client.PostAsync("/farms", TestData.Json("{}"));

        await TestData.AssertShapeErrorAsync(response, "code", "name", "region");
    }

    [Fact]
    public async Task One_required_field_missing_gives_400_listing_only_that_field()
    {
        var response = await Client.PostAsJsonAsync("/farms", new { code = TestData.NewCode(), region = "Region A" });

        await TestData.AssertShapeErrorAsync(response, "name");
    }

    // T2: an unreadable number in the address: 400 from ASP.NET Core, naming the field.
    [Fact]
    public async Task An_unreadable_number_gives_400()
    {
        var response = await Client.GetAsync("/farms?pageNumber=abc");

        await TestData.AssertShapeErrorAsync(response, "pageNumber");
    }
}
