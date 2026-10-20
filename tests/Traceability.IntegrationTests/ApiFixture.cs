using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.SqlClient;

namespace Traceability.IntegrationTests;

/// <summary>
/// Shared by all the integration tests. Before any test: reads the connection string the API
/// will really use (read only) and refuses to go on if it is not the test database; then
/// empties the test database.
/// </summary>
public sealed class ApiFixture : IAsyncLifetime
{
    public ApiFactory Factory { get; private set; } = null!;

    public HttpClient Client { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        Factory = new ApiFactory();

        var apiConnectionString = Factory.Services
            .GetRequiredService<IConfiguration>()
            .GetConnectionString("Default") ?? "";
        var catalog = new SqlConnectionStringBuilder(apiConnectionString).InitialCatalog;
        if (catalog != TestDatabase.Name)
        {
            throw new InvalidOperationException(
                $"The API under test would use the database '{catalog}', not '{TestDatabase.Name}'. No test is run.");
        }

        await TestDatabase.CleanAsync(Factory.TestConnectionString);

        Client = Factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"),
            AllowAutoRedirect = false,
        });
    }

    public async Task DisposeAsync()
    {
        Client.Dispose();
        await Factory.DisposeAsync();
    }
}

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ApiFixture>
{
    public const string Name = "Api";
}
