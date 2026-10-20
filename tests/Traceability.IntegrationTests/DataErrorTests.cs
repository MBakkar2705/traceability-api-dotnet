using Microsoft.Data.SqlClient;
using Traceability.Api.Errors;
using Traceability.Data;

namespace Traceability.IntegrationTests;

// The two SQL errors that the HTTP tests cannot reach: the unique-key error (2627), which the
// procedures prevent by checking first, and the NOT NULL error (515), which the API prevents
// by checking the fields first. Here they are provoked on purpose, on the test database.
[Collection(ApiCollection.Name)]
public class DataErrorTests(ApiFixture api)
{
    private string ConnectionString => api.Factory.TestConnectionString;

    // The unique-key error, with its real SQL Server message, goes through the translator.
    [Fact]
    public async Task A_duplicate_code_inserted_directly_raises_the_unique_key_error()
    {
        // The code is generated here (letters and digits only), so it is safe inside the SQL text.
        var code = TestData.NewCode();
        var insert = $"INSERT INTO trace.Farm (Code, Name, Region) VALUES (N'{code}', N'Test farm', N'Region A');";
        await TestDatabase.ExecuteAsync(ConnectionString, insert);

        var exception = await Assert.ThrowsAsync<SqlException>(
            () => TestDatabase.ExecuteAsync(ConnectionString, insert));

        Assert.Equal(2627, exception.Number);
        Assert.Contains("UQ_Farm_Code", exception.Message);

        var error = SqlErrorTranslator.Translate(exception.Number, exception.Message);
        Assert.Equal(409, error.Status);
        Assert.Equal((int?)50200, error.ErrorCode);
    }

    // A NULL name reaches the procedure through Data (which sends null as SQL NULL).
    [Fact]
    public async Task A_null_name_raises_the_not_null_error()
    {
        var db = new TraceabilityDb(ConnectionString);

        var exception = await Assert.ThrowsAsync<SqlException>(
            () => db.CreateFarmAsync(TestData.NewCode(), null, "Region A"));

        Assert.Equal(515, exception.Number);

        var error = SqlErrorTranslator.Translate(exception.Number, exception.Message);
        Assert.Equal(400, error.Status);
        Assert.Null(error.ErrorCode);
    }
}
