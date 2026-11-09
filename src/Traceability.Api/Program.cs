using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.OpenApi;
using Traceability.Api.Authentication;
using Traceability.Api.Errors;
using Traceability.Data;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
// OpenAPI document: declares the "Bearer" security scheme, so that Swagger UI (Development only)
// shows the Authorize button and sends the token that is pasted there (lot 10b). The routes are
// protected by the policies below, not by this declaration.
builder.Services.AddOpenApi(options =>
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes = new Dictionary<string, IOpenApiSecurityScheme>
        {
            ["Bearer"] = new OpenApiSecurityScheme
            {
                Type = SecuritySchemeType.Http,
                Scheme = "bearer",
                BearerFormat = "JWT",
                In = ParameterLocation.Header,
            },
        };

        var operations = document.Paths.Values
            .Where(path => path.Operations is not null)
            .SelectMany(path => path.Operations!);

        foreach (var operation in operations)
        {
            operation.Value.Security ??= [];
            operation.Value.Security.Add(new OpenApiSecurityRequirement
            {
                [new OpenApiSecuritySchemeReference("Bearer", document)] = [],
            });
        }

        return Task.CompletedTask;
    }));

// Errors: Problem Details answers; SQL errors are translated by SqlExceptionHandler.
builder.Services.AddProblemDetails();
builder.Services.AddExceptionHandler<SqlExceptionHandler>();

// CORS: lets the web interface (the Vite development server) read the answers of the API.
// Development only. GET for reading (lot 4a), POST and the Content-Type header for writing
// with a JSON body (lot 4b), the Authorization header for the access token of the signed-in
// user (lot 10c). An origin is scheme + host + port, written without a trailing slash.
const string WebUiCorsPolicy = "WebUi";

if (builder.Environment.IsDevelopment())
{
    builder.Services.AddCors(options =>
        options.AddPolicy(WebUiCorsPolicy, policy => policy
            .WithOrigins("http://localhost:5173")
            .WithMethods("GET", "POST")
            .WithHeaders("Content-Type", "Authorization")));
}

// Authentication (lot 10b): the API accepts a JWT access token issued by Keycloak. Its signature,
// issuer, expiry and audience are checked; the public keys are read from the configuration that
// Keycloak publishes, so the API needs no secret. The settings come from the environment
// variables Authentication__Authority (the address of the realm) and Authentication__Audience
// (the name the token must be meant for), never from a file of the repository. They are read
// when the options are first needed, so that the integration tests, which replace this scheme
// by a test scheme, need neither.
static string RequiredSetting(IConfiguration configuration, string key)
{
    var value = configuration[key];
    if (string.IsNullOrWhiteSpace(value))
    {
        throw new InvalidOperationException(
            $"The setting '{key}' is not set. Define the environment variable {key.Replace(":", "__")}.");
    }

    return value;
}

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();

builder.Services
    .AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
    .Configure<IConfiguration, IHostEnvironment>((options, configuration, environment) =>
    {
        options.Authority = RequiredSetting(configuration, "Authentication:Authority");
        options.Audience = RequiredSetting(configuration, "Authentication:Audience");

        // Keycloak runs in plain HTTP on the development machine; everywhere else the
        // configuration of the issuer must be read over HTTPS.
        options.RequireHttpsMetadata = !environment.IsDevelopment();

        options.Events = new JwtBearerEvents
        {
            // The roles are in the token under realm_access.roles (observed in lot 10a).
            OnTokenValidated = context =>
            {
                if (context.Principal?.Identity is ClaimsIdentity identity)
                {
                    KeycloakRoles.AddRoleClaims(identity);
                }

                return Task.CompletedTask;
            },
        };
    });

// Reading routes: reader or writer. Writing routes: writer.
builder.Services.AddAuthorizationBuilder()
    .AddPolicy(Policies.CanRead, policy => policy
        .RequireAuthenticatedUser()
        .RequireRole(Policies.ReaderRole, Policies.WriterRole))
    .AddPolicy(Policies.CanWrite, policy => policy
        .RequireAuthenticatedUser()
        .RequireRole(Policies.WriterRole));

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

if (app.Environment.IsDevelopment())
{
    app.UseCors(WebUiCorsPolicy);
}

app.UseAuthentication();

app.UseAuthorization();

app.MapControllers();

app.Run();

// Makes the entry point visible to the integration tests (WebApplicationFactory).
public partial class Program { }
