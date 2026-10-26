namespace Traceability.Api.Errors;

/// <summary>What the API answers for a SQL error: HTTP status, optional errorCode, detail text.</summary>
public sealed record ApiError(int Status, int? ErrorCode, string Detail);

/// <summary>
/// Turns a SQL Server error (number and message) into an HTTP answer.
/// Families of procedure errors: 501xx not found (404), 502xx already exists (409),
/// 503xx business rule violated (422), 504xx invalid value (400).
/// Anything else is unexpected: 500 with a generic text, never the SQL text.
/// </summary>
public static class SqlErrorTranslator
{
    public const string GenericDetail = "An unexpected error occurred.";

    private const int UniqueViolation = 2627;
    private const int NullViolation = 515;

    public static ApiError Translate(int number, string message)
    {
        if (number == UniqueViolation)
        {
            return TranslateUniqueViolation(message);
        }

        if (number == NullViolation)
        {
            return new ApiError(400, null, "A required value is missing.");
        }

        return number switch
        {
            >= 50100 and <= 50199 => new ApiError(404, number, message),
            >= 50200 and <= 50299 => new ApiError(400, number, message),
            >= 50300 and <= 50399 => new ApiError(422, number, message),
            >= 50400 and <= 50499 => new ApiError(400, number, message),
            _ => Unexpected(),
        };
    }

    public static ApiError Unexpected() => new(500, null, GenericDetail);

    // Two requests creating the same code at the same moment: SQL Server raises its
    // own unique-key error. The constraint name, read in the message, tells which code.
    private static ApiError TranslateUniqueViolation(string message)
    {
        if (message.Contains("UQ_Farm_Code", StringComparison.OrdinalIgnoreCase))
        {
            return new ApiError(409, 50200, "A farm with this code already exists.");
        }

        if (message.Contains("UQ_Station_Code", StringComparison.OrdinalIgnoreCase))
        {
            return new ApiError(409, 50201, "A station with this code already exists.");
        }

        if (message.Contains("UQ_Batch_BatchCode", StringComparison.OrdinalIgnoreCase))
        {
            return new ApiError(409, 50202, "A batch with this code already exists.");
        }

        return Unexpected();
    }
}
