namespace Traceability.Api.Authentication;

/// <summary>
/// The two roles of the API and the two authorization policies built on them (lot 10b).
/// A policy is a rule that a route asks for with [Authorize(Policy = ...)].
/// </summary>
public static class Policies
{
    /// <summary>Role that may read: list and view farms, stations and batches.</summary>
    public const string ReaderRole = "reader";

    /// <summary>Role that may write: create farms, stations, batches and movements.</summary>
    public const string WriterRole = "writer";

    /// <summary>
    /// Reading routes (GET). A writer is accepted too, because the token of a writer does not
    /// contain the role reader (observed in lot 10a).
    /// </summary>
    public const string CanRead = "CanRead";

    /// <summary>Writing routes (POST): the role writer only.</summary>
    public const string CanWrite = "CanWrite";
}
