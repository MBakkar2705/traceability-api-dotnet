using Traceability.Api.Errors;

namespace Traceability.UnitTests;

// U1 to U5: translation of SQL errors into HTTP answers. The function is pure, so no
// database is needed. The messages used here are examples: the real SQL Server messages
// are observed by the integration tests.
public class SqlErrorTranslatorTests
{
    // U1: the 16 numbers raised by the procedures, grouped by family.
    [Theory]
    [InlineData(50100, 404)]
    [InlineData(50101, 404)]
    [InlineData(50102, 404)]
    [InlineData(50200, 409)]
    [InlineData(50201, 409)]
    [InlineData(50202, 409)]
    [InlineData(50203, 409)]
    [InlineData(50300, 422)]
    [InlineData(50301, 422)]
    [InlineData(50302, 422)]
    [InlineData(50303, 422)]
    [InlineData(50400, 400)]
    [InlineData(50401, 400)]
    [InlineData(50402, 400)]
    [InlineData(50403, 400)]
    [InlineData(50404, 400)]
    public void Procedure_errors_map_to_the_status_of_their_family(int number, int expectedStatus)
    {
        var error = SqlErrorTranslator.Translate(number, "message from the procedure");

        Assert.Equal(expectedStatus, error.Status);
        Assert.Equal((int?)number, error.ErrorCode);
        Assert.Equal("message from the procedure", error.Detail);
    }

    // U2: any other number is unexpected: 500, generic text, never the SQL text.
    [Theory]
    [InlineData(12345)]
    [InlineData(50000)]
    [InlineData(50500)]
    [InlineData(-2146893019)]
    public void Unknown_errors_give_500_without_the_sql_text(int number)
    {
        var error = SqlErrorTranslator.Translate(number, "secret SQL text");

        Assert.Equal(500, error.Status);
        Assert.Null(error.ErrorCode);
        Assert.Equal(SqlErrorTranslator.GenericDetail, error.Detail);
        Assert.DoesNotContain("secret", error.Detail);
    }

    // U3: unique-key error (2627), translated by the name of the constraint.
    [Theory]
    [InlineData("UQ_Farm_Code", 50200)]
    [InlineData("UQ_Station_Code", 50201)]
    [InlineData("UQ_Batch_BatchCode", 50202)]
    public void Unique_violation_maps_by_constraint_name(string constraint, int expectedErrorCode)
    {
        var message = $"Violation of UNIQUE KEY constraint '{constraint}'. Cannot insert duplicate key in object 'trace.Example'.";

        var error = SqlErrorTranslator.Translate(2627, message);

        Assert.Equal(409, error.Status);
        Assert.Equal((int?)expectedErrorCode, error.ErrorCode);
    }

    // U4: a unique-key error on a constraint we do not know is unexpected.
    [Fact]
    public void Unique_violation_on_an_unknown_constraint_gives_500()
    {
        var message = "Violation of UNIQUE KEY constraint 'UQ_Other_Thing'. Cannot insert duplicate key in object 'trace.Example'.";

        var error = SqlErrorTranslator.Translate(2627, message);

        Assert.Equal(500, error.Status);
        Assert.Null(error.ErrorCode);
        Assert.Equal(SqlErrorTranslator.GenericDetail, error.Detail);
    }

    // U5: NOT NULL error (515): 400, no errorCode, no SQL text.
    [Fact]
    public void Null_violation_gives_400_without_the_sql_text()
    {
        var error = SqlErrorTranslator.Translate(515, "Cannot insert the value NULL into column 'Name'.");

        Assert.Equal(400, error.Status);
        Assert.Null(error.ErrorCode);
        Assert.DoesNotContain("Cannot insert", error.Detail);
    }
}
