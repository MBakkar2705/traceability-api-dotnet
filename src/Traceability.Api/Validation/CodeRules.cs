namespace Traceability.Api.Validation;

/// <summary>
/// Shape of a code (farm, station, batch): letters A-Z without accent, digits,
/// '-' and '_', up to a maximum length. The API checks the shape only: an empty
/// code is accepted here and refused by the stored procedure (error 50400).
/// </summary>
public static class CodeRules
{
    public const int FarmMaxLength = 20;
    public const int StationMaxLength = 20;
    public const int BatchMaxLength = 30;

    public static bool HasValidShape(string code, int maxLength)
    {
        if (code.Length > maxLength)
        {
            return false;
        }

        foreach (var c in code)
        {
            if (!char.IsAsciiLetterOrDigit(c) && c != '-' && c != '_')
            {
                return false;
            }
        }

        return true;
    }
}
