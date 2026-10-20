using Microsoft.Data.SqlClient;

namespace Traceability.IntegrationTests;

// I1 to I3: the tests never touch the wrong database, and the cleaning works.
[Collection(ApiCollection.Name)]
public class DatabaseSafetyTests(ApiFixture api)
{
    // I1: the connection string the API under test reads points to TraceabilityTest, even
    // though the environment variable ConnectionStrings__Default points to TraceabilityDev.
    [Fact]
    public void The_api_under_test_uses_the_test_database()
    {
        var connectionString = api.Factory.Services
            .GetRequiredService<IConfiguration>()
            .GetConnectionString("Default");

        Assert.Equal(TestDatabase.Name, new SqlConnectionStringBuilder(connectionString).InitialCatalog);
    }

    // I2: the check refuses another database. It only runs a SELECT on "master": no DELETE
    // is ever sent to a database that is not the test database.
    [Fact]
    public async Task The_check_refuses_a_database_that_is_not_the_test_database()
    {
        var otherDatabase = new SqlConnectionStringBuilder(api.Factory.TestConnectionString)
        {
            InitialCatalog = "master",
        }.ConnectionString;

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => TestDatabase.AssertIsTestDatabaseAsync(otherDatabase));

        Assert.Contains("master", exception.Message);
    }

    // I3: the cleaning empties the five tables, including rows put there on purpose.
    [Fact]
    public async Task The_cleaning_empties_the_five_tables()
    {
        var connectionString = api.Factory.TestConnectionString;
        await TestDatabase.ExecuteAsync(connectionString,
            "INSERT INTO trace.Farm (Code, Name, Region) VALUES (N'ZX-CLEAN', N'Cleaning test', N'Region A');");
        await TestDatabase.ExecuteAsync(connectionString,
            "INSERT INTO trace.Station (Code, Name) VALUES (N'ZX-CLEAN', N'Cleaning test');");
        Assert.True(await TestDatabase.CountRowsAsync(connectionString, "trace.Farm") > 0);
        Assert.True(await TestDatabase.CountRowsAsync(connectionString, "trace.Station") > 0);

        await TestDatabase.CleanAsync(connectionString);

        foreach (var table in TestDatabase.Tables)
        {
            Assert.Equal(0, await TestDatabase.CountRowsAsync(connectionString, table));
        }
    }
}
