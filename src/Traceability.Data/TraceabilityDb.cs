using System.Data;
using Microsoft.Data.SqlClient;

namespace Traceability.Data;

/// <summary>
/// Calls the stored procedures of the trace schema with ADO.NET (ADR 0005).
/// Business rules stay in the procedures (ADR 0001): this class only sends the
/// parameters and reads the result tables. SQL errors are not caught here: the
/// caller reads SqlException.Number and SqlException.Message.
/// </summary>
public sealed class TraceabilityDb
{
    private readonly string _connectionString;

    public TraceabilityDb(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        _connectionString = connectionString;
    }

    public async Task<FarmRow> CreateFarmAsync(
        string? code, string? name, string? region, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.CreateFarm",
            Text("@Code", code), Text("@Name", name), Text("@Region", region));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("trace.CreateFarm returned no row.");
        }

        return ReadFarm(reader);
    }

    public async Task<PageRow<FarmRow>> ListFarmsAsync(
        int pageNumber, int pageSize, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.ListFarms",
            Int("@PageNumber", pageNumber), Int("@PageSize", pageSize));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var items = new List<FarmRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            items.Add(ReadFarm(reader));
        }

        var totalCount = await ReadTotalCountAsync(reader, "trace.ListFarms", cancellationToken);
        return new PageRow<FarmRow>(items, totalCount);
    }

    public async Task<StationRow> CreateStationAsync(
        string? code, string? name, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.CreateStation",
            Text("@Code", code), Text("@Name", name));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("trace.CreateStation returned no row.");
        }

        return ReadStation(reader);
    }

    public async Task<PageRow<StationRow>> ListStationsAsync(
        int pageNumber, int pageSize, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.ListStations",
            Int("@PageNumber", pageNumber), Int("@PageSize", pageSize));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var items = new List<StationRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            items.Add(ReadStation(reader));
        }

        var totalCount = await ReadTotalCountAsync(reader, "trace.ListStations", cancellationToken);
        return new PageRow<StationRow>(items, totalCount);
    }

    public async Task<StationDetailsRow> GetStationAsync(
        string? stationCode, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.GetStation", Text("@StationCode", stationCode));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        // First table: the station.
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("trace.GetStation returned no station row.");
        }

        var code = GetString(reader, "Code");
        var name = GetString(reader, "Name");

        // Second table: its capabilities, in life-cycle order (empty if none).
        var capabilities = new List<string>();
        if (await reader.NextResultAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                capabilities.Add(GetString(reader, "MovementType"));
            }
        }

        return new StationDetailsRow(code, name, capabilities);
    }

    public async Task AddStationCapabilityAsync(
        string? stationCode, string? movementType, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.AddStationCapability",
            Text("@StationCode", stationCode), Text("@MovementType", movementType));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    private async Task<SqlConnection> OpenAsync(CancellationToken cancellationToken)
    {
        var connection = new SqlConnection(_connectionString);
        try
        {
            await connection.OpenAsync(cancellationToken);
            return connection;
        }
        catch
        {
            await connection.DisposeAsync();
            throw;
        }
    }

    private static SqlCommand CreateCommand(
        SqlConnection connection, string procedure, params SqlParameter[] parameters)
    {
        var command = connection.CreateCommand();
        command.CommandType = CommandType.StoredProcedure;
        command.CommandText = procedure;
        command.Parameters.AddRange(parameters);
        return command;
    }

    // A null C# value is sent as SQL NULL: the procedures decide what to do with it.
    private static SqlParameter Text(string name, string? value) =>
        new(name, SqlDbType.NVarChar) { Value = (object?)value ?? DBNull.Value };

    private static SqlParameter Int(string name, int value) =>
        new(name, SqlDbType.Int) { Value = value };

    private static string GetString(SqlDataReader reader, string column) =>
        reader.GetString(reader.GetOrdinal(column));

    private static FarmRow ReadFarm(SqlDataReader reader) =>
        new(GetString(reader, "Code"), GetString(reader, "Name"), GetString(reader, "Region"));

    private static StationRow ReadStation(SqlDataReader reader) =>
        new(GetString(reader, "Code"), GetString(reader, "Name"));

    private static async Task<int> ReadTotalCountAsync(
        SqlDataReader reader, string procedure, CancellationToken cancellationToken)
    {
        if (!await reader.NextResultAsync(cancellationToken) || !await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException($"{procedure} did not return the TotalCount table.");
        }

        return reader.GetInt32(reader.GetOrdinal("TotalCount"));
    }
}
