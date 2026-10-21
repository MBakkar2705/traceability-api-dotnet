namespace Traceability.Api.Validation;

/// <summary>
/// Sizes of the columns that receive free text or a quantity. The API refuses (400) a value the
/// column cannot hold: otherwise the value is cut, rounded or makes SqlClient fail (observed in
/// lot 3c). The codes have their own limits in CodeRules.
/// </summary>
public static class FieldLimits
{
    // NVARCHAR(100): the names of farms and stations, the region of a farm.
    public const int NameMaxLength = 100;
    public const int RegionMaxLength = 100;

    // NVARCHAR(50): the variety of a batch.
    public const int VarietyMaxLength = 50;

    // NVARCHAR(20): the movement type and the status filter.
    public const int MovementTypeMaxLength = 20;
    public const int StatusMaxLength = 20;

    // DECIMAL(10,2): 8 digits before the decimal point, 2 after.
    public const decimal QuantityMax = 99_999_999.99m;
    public const int QuantityDecimals = 2;
}
