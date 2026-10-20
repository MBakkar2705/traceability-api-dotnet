using Traceability.Api.Errors;
using Traceability.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// Errors: Problem Details answers; SQL errors are translated by SqlExceptionHandler.
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<SqlExceptionHandler>();

// The connection string comes from the environment variable ConnectionStrings__Default
// (ASP.NET Core reads it as the key ConnectionStrings:Default). It is never written in a
// file of the repository. It is read when TraceabilityDb is first needed, so that the
// integration tests can replace it with the test database.
builder.Services.AddSingleton(serviceProvider =>
{
    var connectionString = serviceProvider
        .GetRequiredService<IConfiguration>()
        .GetConnectionString("Default");

    if (string.IsNullOrWhiteSpace(connectionString))
    {
        throw new InvalidOperationException(
            "The connection string 'Default' is not set. Define the environment variable ConnectionStrings__Default.");
    }

    return new TraceabilityDb(connectionString);
});

var app = builder.Build();

app.UseExceptionHandler();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();

    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "v1");
    });
}

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();

app.Run();

// Makes the entry point visible to the integration tests (WebApplicationFactory).
public partial class Program { }
