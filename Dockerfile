# Lot 8: Docker image of the API (src/Traceability.Api).
# The build context is the repository root, because the API needs src/Traceability.Data.
# Two stages: "build" compiles with the SDK image; "final" holds only the runtime
# and the published API, which makes the image smaller.
# No secret is written here: the connection string is given when the container starts
# (environment variable ConnectionStrings__Default).

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy the project files first and restore the packages: Docker keeps this step in its
# cache as long as the package list does not change.
COPY src/Traceability.Api/Traceability.Api.csproj src/Traceability.Api/
COPY src/Traceability.Data/Traceability.Data.csproj src/Traceability.Data/
RUN dotnet restore src/Traceability.Api/Traceability.Api.csproj

# Then copy the code and publish the API.
COPY src/ src/
RUN dotnet publish src/Traceability.Api/Traceability.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .

# Do not run as an administrator: the .NET images provide the user "app".
USER app

# The .NET images listen on port 8080 by default (HTTP only; HTTPS is not set up here).
EXPOSE 8080
ENTRYPOINT ["dotnet", "Traceability.Api.dll"]
