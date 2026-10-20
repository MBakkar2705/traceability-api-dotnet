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
