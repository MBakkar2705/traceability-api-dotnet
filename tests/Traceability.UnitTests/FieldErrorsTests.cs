using Microsoft.AspNetCore.Mvc.ModelBinding;
using Traceability.Api.Validation;

namespace Traceability.UnitTests;

// U7: missing fields are detected by the API before any procedure call.
public class FieldErrorsTests
{
    [Fact]
    public void A_missing_value_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireValue("name", null);

        Assert.True(errors.HasErrors);
        Assert.Contains("name", errors.Errors.Keys);
    }

    [Theory]
    [InlineData("")]
    [InlineData("Farm Nord")]
    public void A_present_value_is_not_an_error(string value)
    {
        var errors = new FieldErrors();

        errors.RequireValue("name", value);

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void A_missing_code_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireCode("code", null, CodeRules.FarmMaxLength);

        Assert.True(errors.HasErrors);
        Assert.Contains("code", errors.Errors.Keys);
    }

    [Fact]
    public void An_empty_code_is_left_to_the_stored_procedure()
    {
        var errors = new FieldErrors();

        errors.RequireCode("code", "", CodeRules.FarmMaxLength);

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void A_code_with_a_forbidden_character_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireCode("code", "AB CD", CodeRules.FarmMaxLength);

        Assert.True(errors.HasErrors);
        Assert.Contains("code", errors.Errors.Keys);
    }

    [Fact]
    public void A_valid_code_is_not_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireCode("code", "F001", CodeRules.FarmMaxLength);

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void Several_fields_are_collected_separately()
    {
        var errors = new FieldErrors();

        errors.RequireCode("code", null, CodeRules.FarmMaxLength);
        errors.RequireValue("name", null);
        errors.RequireValue("region", "Region A");

        Assert.Equal(2, errors.Errors.Count);
        Assert.Contains("code", errors.Errors.Keys);
        Assert.Contains("name", errors.Errors.Keys);
    }

    // Numbers, dates and times: a missing field reads as null (RequireValue for value types).
    [Fact]
    public void A_missing_number_is_an_error()
    {
        var errors = new FieldErrors();
        decimal? quantityKg = null;

        errors.RequireValue("quantityKg", quantityKg);

        Assert.True(errors.HasErrors);
        Assert.Contains("quantityKg", errors.Errors.Keys);
    }

    [Fact]
    public void A_missing_date_or_time_is_an_error()
    {
        var errors = new FieldErrors();
        DateOnly? harvestDate = null;
        DateTime? occurredAt = null;

        errors.RequireValue("harvestDate", harvestDate);
        errors.RequireValue("occurredAt", occurredAt);

        Assert.Equal(2, errors.Errors.Count);
        Assert.Contains("harvestDate", errors.Errors.Keys);
        Assert.Contains("occurredAt", errors.Errors.Keys);
    }

    [Fact]
    public void A_zero_is_a_present_value_left_to_the_stored_procedure()
    {
        var errors = new FieldErrors();
        decimal? zero = 0m;

        errors.RequireValue("quantityKg", zero);

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void A_present_date_and_time_are_not_errors()
    {
        var errors = new FieldErrors();
        DateOnly? harvestDate = new DateOnly(2026, 10, 14);
        DateTime? occurredAt = new DateTime(2026, 10, 14, 6, 30, 0, DateTimeKind.Utc);

        errors.RequireValue("harvestDate", harvestDate);
        errors.RequireValue("occurredAt", occurredAt);

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void A_missing_number_gets_the_same_message_as_a_missing_text()
    {
        var errors = new FieldErrors();
        decimal? quantityKg = null;

        errors.RequireValue("name", (string?)null);
        errors.RequireValue("quantityKg", quantityKg);

        Assert.Equal(errors.Errors["name"], errors.Errors["quantityKg"]);
    }

    // A time must be explicitly UTC: "Z", or an offset. No indication is refused.
    [Fact]
    public void A_missing_time_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireUtcTime("occurredAt", null);

        Assert.True(errors.HasErrors);
        Assert.Contains("occurredAt", errors.Errors.Keys);
    }

    [Fact]
    public void A_time_without_indication_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireUtcTime("occurredAt", new DateTime(2026, 10, 14, 6, 0, 0, DateTimeKind.Unspecified));

        Assert.True(errors.HasErrors);
        Assert.Contains("occurredAt", errors.Errors.Keys);
    }

    [Fact]
    public void A_utc_time_is_not_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireUtcTime("occurredAt", new DateTime(2026, 10, 14, 6, 0, 0, DateTimeKind.Utc));

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void A_time_with_an_offset_is_not_an_error()
    {
        var errors = new FieldErrors();

        // System.Text.Json reads a time with an offset as a local time.
        errors.RequireUtcTime("occurredAt", new DateTime(2026, 10, 14, 8, 0, 0, DateTimeKind.Local));

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void Errors_are_copied_into_the_model_state()
    {
        var errors = new FieldErrors();
        errors.RequireValue("name", null);
        var modelState = new ModelStateDictionary();

        errors.ApplyTo(modelState);

        Assert.False(modelState.IsValid);
        Assert.Contains("name", modelState.Keys);
    }

    // Texts for columns of limited size: too long is refused, empty is left to the procedure.
    [Fact]
    public void A_missing_text_is_an_error_for_a_limited_column()
    {
        var errors = new FieldErrors();

        errors.RequireText("name", null, FieldLimits.NameMaxLength);

        Assert.True(errors.HasErrors);
        Assert.Contains("name", errors.Errors.Keys);
    }

    [Fact]
    public void A_text_at_the_limit_is_not_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireText("name", new string('N', FieldLimits.NameMaxLength), FieldLimits.NameMaxLength);

        Assert.False(errors.HasErrors);
    }

    [Fact]
    public void A_text_over_the_limit_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireText("name", new string('N', FieldLimits.NameMaxLength + 1), FieldLimits.NameMaxLength);

        Assert.True(errors.HasErrors);
        Assert.Contains("name", errors.Errors.Keys);
    }

    [Fact]
    public void An_empty_text_is_left_to_the_stored_procedure_for_a_limited_column()
    {
        var errors = new FieldErrors();

        errors.RequireText("name", "", FieldLimits.NameMaxLength);

        Assert.False(errors.HasErrors);
    }

    // Quantities for DECIMAL(10,2): 8 digits before the decimal point, 2 after. Zero and negative
    // values are left to the stored procedure (50401).
    [Fact]
    public void A_missing_quantity_is_an_error()
    {
        var errors = new FieldErrors();

        errors.RequireQuantity("quantityKg", null);

        Assert.True(errors.HasErrors);
        Assert.Contains("quantityKg", errors.Errors.Keys);
    }

    [Theory]
    [InlineData("500.555")]
    [InlineData("99999999.991")]
    [InlineData("100000000")]
    [InlineData("-100000000")]
    [InlineData("79228162514264337593543950335")]
    public void A_quantity_the_column_cannot_hold_is_an_error(string quantity)
    {
        var errors = new FieldErrors();

        errors.RequireQuantity("quantityKg", decimal.Parse(quantity, System.Globalization.CultureInfo.InvariantCulture));

        Assert.True(errors.HasErrors);
        Assert.Contains("quantityKg", errors.Errors.Keys);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("0.01")]
    [InlineData("500.5")]
    [InlineData("500.00")]
    [InlineData("99999999.99")]
    [InlineData("-5")]
    public void A_quantity_the_column_can_hold_is_not_an_error(string quantity)
    {
        var errors = new FieldErrors();

        errors.RequireQuantity("quantityKg", decimal.Parse(quantity, System.Globalization.CultureInfo.InvariantCulture));

        Assert.False(errors.HasErrors);
    }
}
