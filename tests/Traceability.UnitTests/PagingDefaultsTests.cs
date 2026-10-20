using Traceability.Api.Controllers;
using Traceability.Api.Models;

namespace Traceability.UnitTests;

// U8: without pageNumber and pageSize, the list routes use page 1 of 20.
// The action parameters are read by reflection; the real HTTP behavior is
// observed by the integration tests.
public class PagingDefaultsTests
{
    [Fact]
    public void Default_page_is_1_of_20()
    {
        Assert.Equal(1, Paging.DefaultPageNumber);
        Assert.Equal(20, Paging.DefaultPageSize);
    }

    [Theory]
    [InlineData(typeof(FarmsController))]
    [InlineData(typeof(StationsController))]
    public void List_actions_use_the_default_page(Type controller)
    {
        var method = controller.GetMethod("List");
        Assert.NotNull(method);

        var parameters = method.GetParameters().ToDictionary(p => p.Name!);

        Assert.Equal(1, parameters["pageNumber"].DefaultValue);
        Assert.Equal(20, parameters["pageSize"].DefaultValue);
    }
}
