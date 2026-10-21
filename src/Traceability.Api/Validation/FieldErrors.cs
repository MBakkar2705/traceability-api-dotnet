using Microsoft.AspNetCore.Mvc.ModelBinding;

namespace Traceability.Api.Validation;

/// <summary>
/// Collects the shape errors of a request (missing field, bad code shape) so the
/// API can answer 400 before calling any stored procedure. Business rules are
/// not checked here: they stay in the procedures. The errors are then copied into
/// the ModelState of the controller, so the 400 has the same Problem Details form
/// (type, title, status, errors, traceId) as the 400 raised by ASP.NET Core itself.
/// </summary>
public sealed class FieldErrors
{
    private readonly Dictionary<string, List<string>> _errors = new();

    public bool HasErrors => _errors.Count > 0;

    public IReadOnlyDictionary<string, string[]> Errors =>
        _errors.ToDictionary(e => e.Key, e => e.Value.ToArray());

    public void RequireValue(string field, string? value)
    {
        if (value is null)
        {
            Add(field, "The field is required.");
        }
    }

    // For fields that are numbers, dates or times: a missing field reads as null.
    public void RequireValue<T>(string field, T? value)
        where T : struct
    {
        if (value is null)
        {
            Add(field, "The field is required.");
        }
    }

    // A time must say that it is UTC: with "Z", or with an offset (it is then converted to UTC).
    // A time with no indication is refused, so a local time is never read as UTC by mistake.
    public void RequireUtcTime(string field, DateTime? value)
    {
        if (value is null)
        {
            Add(field, "The field is required.");
            return;
        }

        if (value.Value.Kind == DateTimeKind.Unspecified)
        {
            Add(field, "The time must end with 'Z' (UTC) or carry an offset, for example 2026-10-14T06:00:00Z.");
        }
    }

    public void RequireCode(string field, string? value, int maxLength)
    {
        if (value is null)
        {
            Add(field, "The field is required.");
            return;
        }

        if (!CodeRules.HasValidShape(value, maxLength))
        {
            Add(field, $"Only letters A-Z, digits, '-' and '_' are allowed, up to {maxLength} characters.");
        }
    }

    // A text for a column of limited size (NVARCHAR(n)): a longer text would be cut in silence.
    // An empty text is accepted here: the stored procedure decides what to do with it.
    public void RequireText(string field, string? value, int maxLength)
    {
        if (value is null)
        {
            Add(field, "The field is required.");
        }
        else if (value.Length > maxLength)
        {
            Add(field, $"At most {maxLength} characters are allowed.");
        }
    }

    // A quantity for a DECIMAL(10,2) column: at most 8 digits before the decimal point and 2 after.
    // A more precise value would be rounded in silence and a bigger one would make SqlClient fail
    // (both observed in lot 3c). Zero and negative values are left to the stored procedure (50401).
    public void RequireQuantity(string field, decimal? value)
    {
        if (value is null)
        {
            Add(field, "The field is required.");
        }
        else if (Math.Abs(value.Value) > FieldLimits.QuantityMax)
        {
            Add(field, FormattableString.Invariant(
                $"The absolute value of the quantity is limited to {FieldLimits.QuantityMax}."));
        }
        else if (value.Value != decimal.Round(value.Value, FieldLimits.QuantityDecimals))
        {
            Add(field, $"At most {FieldLimits.QuantityDecimals} decimals are allowed.");
        }
    }

    public void ApplyTo(ModelStateDictionary modelState)
    {
        foreach (var (field, messages) in _errors)
        {
            foreach (var message in messages)
            {
                modelState.AddModelError(field, message);
            }
        }
    }

    private void Add(string field, string message)
    {
        if (!_errors.TryGetValue(field, out var messages))
        {
            messages = new List<string>();
            _errors[field] = messages;
        }

        messages.Add(message);
    }
}
