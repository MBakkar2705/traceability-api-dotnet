namespace Traceability.Api.Authentication;

/// <summary>
/// The three roles of the API and the three authorization policies built on them (lot 10b, and
/// lot 12a for the supervisor). A policy is a rule that a route asks for with
/// [Authorize(Policy = ...)].
/// </summary>
public static class Policies
{
    /// <summary>Role that may read: list and view farms, stations and batches.</summary>
    public const string ReaderRole = "reader";

    /// <summary>Role that may write: create farms, stations, batches and movements.</summary>
    public const string WriterRole = "writer";

    /// <summary>
    /// Role that corrects movements (lot 12a): replace or cancel a movement. A supervisor also
    /// reads, but does not enter movements: entering and correcting are two different jobs.
    /// </summary>
    public const string SupervisorRole = "supervisor";

    /// <summary>
    /// Reading routes (GET). A writer and a supervisor are accepted too, because the token of a
    /// writer does not contain the role reader (observed in lot 10a).
    /// </summary>
    public const string CanRead = "CanRead";

    /// <summary>Writing routes (POST): the role writer only.</summary>
    public const string CanWrite = "CanWrite";

    /// <summary>Correction routes (lot 12a): the role supervisor only.</summary>
    public const string CanCorrect = "CanCorrect";
}
