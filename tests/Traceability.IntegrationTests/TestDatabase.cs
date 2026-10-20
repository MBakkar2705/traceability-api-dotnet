using Microsoft.Data.SqlClient;

namespace Traceability.IntegrationTests;

/// <summary>
/// Safety and cleaning of the test database. Every destructive step first checks that
/// the connection really points to TraceabilityTest.
/// </summary>
public static class TestDatabase
{
    public const string Name = "TraceabilityTest";

    // In the order of the foreign keys: children first.
    public static readonly string[] Tables =
        ["trace.Movement", "trace.Batch", "trace.StationCapability", "trace.Station", "trace.Farm"];

    // The guard is also inside the SQL batch itself (50099 is in the range reserved for
    // script guards). With XACT_ABORT ON, the error ends the batch before any DELETE.
    private const string CleanSql = """
        SET XACT_ABORT ON;
        IF DB_NAME() <> N'TraceabilityTest'
        BEGIN
            THROW 50099, N'Refusing to clean a database that is not TraceabilityTest.', 1;
        END;
        BEGIN TRANSACTION;
        DELETE FROM trace.Movement;
        DELETE FROM trace.Batch;
        DELETE FROM trace.StationCapability;
        DELETE FROM trace.Station;
        DELETE FROM trace.Farm;
        COMMIT;
        """;

    public static async Task AssertIsTestDatabaseAsync(string connectionString)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand("SELECT DB_NAME()", connection);
        var name = (string?)await command.ExecuteScalarAsync();

        if (name != Name)
        {
            throw new InvalidOperationException(
                $"Refusing to continue: the connection points to '{name}', not to '{Name}'.");
        }
    }

    public static async Task CleanAsync(string connectionString)
    {
        await AssertIsTestDatabaseAsync(connectionString);

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand(CleanSql, connection);
        await command.ExecuteNonQueryAsync();
    }

    public static async Task ExecuteAsync(string connectionString, string sql)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync();
    }

    public static async Task<int> CountRowsAsync(string connectionString, string table)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        await using var command = new SqlCommand($"SELECT COUNT(*) FROM {table}", connection);
        return (int)(await command.ExecuteScalarAsync())!;
    }
}
