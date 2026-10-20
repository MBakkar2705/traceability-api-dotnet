using Traceability.Api.Validation;

namespace Traceability.UnitTests;

// U6: shape of a code. Only the shape is checked; an empty code is accepted here
// and refused by the stored procedure (error 50400).
public class CodeRulesTests
{
    [Theory]
    [InlineData("F001", 20)]
    [InlineData("LOT-2026-0001", 30)]
    [InlineData("site_01", 20)]
    [InlineData("A", 20)]
    [InlineData("a-B_9", 20)]
    [InlineData("", 20)]
    public void Valid_shapes_are_accepted(string code, int maxLength)
    {
        Assert.True(CodeRules.HasValidShape(code, maxLength));
    }

    [Theory]
    [InlineData("AB CD", 20)]
    [InlineData("\u00C9001", 20)]
    [InlineData("a/b", 20)]
    [InlineData("a.b", 20)]
    [InlineData("F-\u00E9", 20)]
    public void Forbidden_characters_are_refused(string code, int maxLength)
    {
        Assert.False(CodeRules.HasValidShape(code, maxLength));
    }

    [Fact]
    public void Length_limits_are_20_for_farms_and_stations_and_30_for_batches()
    {
        Assert.Equal(20, CodeRules.FarmMaxLength);
        Assert.Equal(20, CodeRules.StationMaxLength);
        Assert.Equal(30, CodeRules.BatchMaxLength);

        Assert.True(CodeRules.HasValidShape(new string('A', 20), CodeRules.FarmMaxLength));
        Assert.False(CodeRules.HasValidShape(new string('A', 21), CodeRules.FarmMaxLength));
        Assert.True(CodeRules.HasValidShape(new string('A', 30), CodeRules.BatchMaxLength));
        Assert.False(CodeRules.HasValidShape(new string('A', 31), CodeRules.BatchMaxLength));
    }
}
