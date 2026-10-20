using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Traceability.IntegrationTests;

/// <summary>
/// Starts the real API in memory, connected to the test database (variable
/// ConnectionStrings__Test), never to the development database.
/// </summary>
public sealed class ApiFactory : WebApplicationFactory<Program>
{
    public ApiFactory()
    {
        TestConnectionString = Environment.GetEnvironmentVariable("ConnectionStrings__Test")
            ?? throw new InvalidOperationException("The environment variable ConnectionStrings__Test is not set.");
    }

    public string TestConnectionString { get; }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Replaces the connection string the API reads (key ConnectionStrings:Default).
        builder.ConfigureAppConfiguration((_, configuration) =>
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Default"] = TestConnectionString,
            }));
    }
}
