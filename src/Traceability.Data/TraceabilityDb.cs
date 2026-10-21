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

    /// <summary>
    /// Creates a batch and its first RECEPTION movement. Values are sent as given (null becomes
    /// SQL NULL, the procedure decides). occurredAtUtc must already be in UTC.
    /// </summary>
    public async Task CreateBatchAsync(
        string? batchCode, string? farmCode, string? variety, DateOnly? harvestDate,
        decimal? quantityKg, string? stationCode, DateTime? occurredAtUtc,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.CreateBatch",
            Text("@BatchCode", batchCode), Text("@FarmCode", farmCode), Text("@Variety", variety),
            Day("@HarvestDate", harvestDate), Kilograms("@QuantityKg", quantityKg),
            Text("@StationCode", stationCode), Moment("@OccurredAt", occurredAtUtc));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    /// <summary>
    /// Adds the next movement of a batch. occurredAtUtc must already be in UTC.
    /// </summary>
    public async Task AddMovementAsync(
        string? batchCode, string? stationCode, string? movementType,
        decimal? quantityKg, DateTime? occurredAtUtc,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.AddMovement",
            Text("@BatchCode", batchCode), Text("@StationCode", stationCode),
            Text("@MovementType", movementType), Kilograms("@QuantityKg", quantityKg),
            Moment("@OccurredAt", occurredAtUtc));
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<BatchDetailsRow> GetBatchAsync(
        string? batchCode, CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.GetBatch", Text("@BatchCode", batchCode));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        // First table: the batch.
        if (!await reader.ReadAsync(cancellationToken))
        {
            throw new InvalidOperationException("trace.GetBatch returned no batch row.");
        }

        var batch = ReadBatch(reader);

        // Second table: its movements, in MovementId order (empty if none).
        var movements = new List<MovementRow>();
        if (await reader.NextResultAsync(cancellationToken))
        {
            while (await reader.ReadAsync(cancellationToken))
            {
                movements.Add(ReadMovement(reader));
            }
        }

        return new BatchDetailsRow(batch, movements);
    }

    public async Task<PageRow<BatchRow>> ListBatchesAsync(
        string? status, string? farmCode, int pageNumber, int pageSize,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = CreateCommand(
            connection, "trace.ListBatches",
            Text("@Status", status), Text("@FarmCode", farmCode),
            Int("@PageNumber", pageNumber), Int("@PageSize", pageSize));
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);

        var items = new List<BatchRow>();
        while (await reader.ReadAsync(cancellationToken))
        {
            items.Add(ReadBatch(reader));
        }

        var totalCount = await ReadTotalCountAsync(reader, "trace.ListBatches", cancellationToken);
        return new PageRow<BatchRow>(items, totalCount);
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

    // DATE column: sent as a DateTime at midnight with the Date type, so SqlClient sends only the day.
    private static SqlParameter Day(string name, DateOnly? value) =>
        new(name, SqlDbType.Date)
        {
            Value = value is { } day ? (object)day.ToDateTime(TimeOnly.MinValue) : DBNull.Value,
        };

    // DECIMAL(10,2) column: precision and scale are set explicitly, not guessed from the value.
    private static SqlParameter Kilograms(string name, decimal? value) =>
        new(name, SqlDbType.Decimal)
        {
            Precision = 10,
            Scale = 2,
            Value = value is { } kg ? (object)kg : DBNull.Value,
        };

    // DATETIME2 column: the database stores UTC without saying so; the caller passes UTC.
    private static SqlParameter Moment(string name, DateTime? value) =>
        new(name, SqlDbType.DateTime2)
        {
            Value = value is { } moment ? (object)moment : DBNull.Value,
        };

    private static string GetString(SqlDataReader reader, string column) =>
        reader.GetString(reader.GetOrdinal(column));

    private static FarmRow ReadFarm(SqlDataReader reader) =>
        new(GetString(reader, "Code"), GetString(reader, "Name"), GetString(reader, "Region"));

    private static StationRow ReadStation(SqlDataReader reader) =>
        new(GetString(reader, "Code"), GetString(reader, "Name"));

    private static BatchRow ReadBatch(SqlDataReader reader) =>
        new(GetString(reader, "BatchCode"),
            GetString(reader, "FarmCode"),
            GetString(reader, "Variety"),
            DateOnly.FromDateTime(reader.GetDateTime(reader.GetOrdinal("HarvestDate"))),
            reader.GetDecimal(reader.GetOrdinal("QuantityKg")),
            GetString(reader, "Status"));

    // The database stores UTC without saying so: the value is marked as UTC here (decision A of lot 3c).
    private static MovementRow ReadMovement(SqlDataReader reader) =>
        new(reader.GetInt64(reader.GetOrdinal("MovementId")),
            GetString(reader, "MovementType"),
            GetString(reader, "StationCode"),
            reader.GetDecimal(reader.GetOrdinal("QuantityKg")),
            DateTime.SpecifyKind(reader.GetDateTime(reader.GetOrdinal("OccurredAt")), DateTimeKind.Utc));

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
