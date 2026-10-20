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
}
