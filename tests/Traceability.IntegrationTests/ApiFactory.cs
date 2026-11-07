using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;

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

        // Lot 10b: the tests need no Keycloak. The test authentication (TestAuth) takes the place of the
        // check of the Keycloak token, so that no real token is needed to call the routes.
        builder.ConfigureTestServices(services => services
            .AddAuthentication(options => options.DefaultScheme = TestAuth.Scheme)
            .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(TestAuth.Scheme, _ => { }));
    }
}
