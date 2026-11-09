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

        // Lot 10b: the routes need a role. This client acts as a writer, who may read and write,
        // so that the tests written before the authentication stay as they are.
        Client.DefaultRequestHeaders.Add(TestAuth.RolesHeader, "writer");
    }

    /// <summary>
    /// A new client of the same API. With roles (several are separated by commas), it sends the
    /// test header of TestAuth. With null, it sends no header at all: a caller without a token.
    /// </summary>
    public HttpClient CreateClient(string? roles)
    {
        var client = Factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            BaseAddress = new Uri("https://localhost"),
            AllowAutoRedirect = false,
        });

        if (roles is not null)
        {
            client.DefaultRequestHeaders.Add(TestAuth.RolesHeader, roles);
        }

        return client;
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
