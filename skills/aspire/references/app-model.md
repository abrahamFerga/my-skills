# Aspire C# app model reference

Scope: the AppHost program in depth — project shape, resource types, references and waiting, parameters/secrets, endpoints, replicas, persistent containers, and how ServiceDefaults plugs in. C# AppHost is the supported default; the TypeScript AppHost (13.2+) mirrors this model but is **preview**.

## AppHost project shape

The AppHost is a normal project that uses a special MSBuild SDK. The 13.x `.csproj`:

```xml
<Project Sdk="Aspire.AppHost.Sdk/13.4.0">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <IsAspireHost>true</IsAspireHost>
    <UserSecretsId>aspire-apphost-...</UserSecretsId>
  </PropertyGroup>

  <ItemGroup>
    <!-- Aspire.Hosting.AppHost is implicit via the SDK; add only integrations -->
    <PackageReference Include="Aspire.Hosting.PostgreSQL" Version="13.4.0" />
    <PackageReference Include="Aspire.Hosting.Redis" Version="13.4.0" />
  </ItemGroup>

  <ItemGroup>
    <!-- Each service you orchestrate; IsAspireProjectResource generates Projects.* -->
    <ProjectReference Include="..\MyApp.Api\MyApp.Api.csproj" IsAspireProjectResource="true" />
    <ProjectReference Include="..\MyApp.Web\MyApp.Web.csproj" IsAspireProjectResource="true" />
  </ItemGroup>
</Project>
```

`Aspire.AppHost.Sdk` brings in the app-model APIs and implicitly references `Aspire.Hosting.AppHost`. Each `IsAspireProjectResource="true"` reference generates a strongly-typed `Projects.<ProjectName>` class you pass to `AddProject<T>`.

**Single-file AppHost (13.0+):** you can skip the `.csproj` entirely and define the whole model in one `.cs` file using directives:

```csharp
#:sdk Aspire.AppHost.Sdk@13.4.0
#:package Aspire.Hosting.PostgreSQL@13.4.0

var builder = DistributedApplication.CreateBuilder(args);
// ... resources ...
builder.Build().Run();
```

## The builder and resources

```csharp
var builder = DistributedApplication.CreateBuilder(args);
```

`builder` is `IDistributedApplicationBuilder`. Every `Add*` call returns an `IResourceBuilder<TResource>` you fluently configure. Resource categories:

| Category | Examples |
|----------|----------|
| Backing services (containers locally) | `AddPostgres`, `AddRedis`, `AddSqlServer`, `AddRabbitMQ`, `AddMongoDB`, `AddKafka` |
| Azure resources | `AddAzureServiceBus`, `AddAzureStorage`, `AddAzureKeyVault`, `AddAzureCosmosDB` (see [azure.md](azure.md)) |
| Your .NET services | `AddProject<Projects.Api>("api")` |
| Raw containers | `AddContainer("name", "image:tag")` |
| Executables / polyglot | `AddExecutable(...)`, `AddPythonApp` / `AddUvicornApp`, `AddJavaScriptApp` |
| Parameters | `AddParameter("name")`, `AddConnectionString("name")` |

Child resources: a server resource often exposes children — `AddPostgres("pg").AddDatabase("appdb")` adds a database *inside* the Postgres server. The child name (`"appdb"`) is the connection name clients use.

## References and waiting

```csharp
var db    = builder.AddPostgres("pg").AddDatabase("appdb");
var cache = builder.AddRedis("cache");

var api = builder.AddProject<Projects.Api>("api")
    .WithReference(db)        // injects ConnectionStrings__appdb
    .WithReference(cache)     // injects ConnectionStrings__cache
    .WaitFor(db)             // don't start api until db is healthy
    .WaitFor(cache);

builder.AddProject<Projects.Web>("web")
    .WithReference(api);      // injects services__api__https__0 = https://api ...
```

- `WithReference(resource)` wires the dependency's connection info into the consumer's configuration. For a service, it also registers a **service-discovery** endpoint so the consumer can call it by name (`https://api`).
- `WaitFor(resource)` gates the consumer's startup until the dependency reports healthy. Use it for anything the service touches on boot. `WaitForCompletion(resource)` waits for a resource that *exits* (e.g. a migration/seed job).
- Never hardcode a peer's URL — referencing by name is what lets `WithReplicas` and deployment relocation work.

## Parameters and secrets

Externalize every secret. `AddParameter` creates a parameter resource; `secret: true` marks it sensitive (masked in the dashboard, sourced from user-secrets/env).

```csharp
var dbPassword = builder.AddParameter("db-password", secret: true);
var pg = builder.AddPostgres("pg", password: dbPassword);

// Plain (non-secret) parameter:
var region = builder.AddParameter("region");

// Reference an externally-managed connection string:
var legacy = builder.AddConnectionString("legacy-db");
```

Supply values locally with user-secrets (keyed `Parameters:<name>`), or in CI with env vars (`Parameters__db-password=...`):

```bash
cd MyApp.AppHost
dotnet user-secrets set "Parameters:db-password" "S3cr3t!"
```

## Environment variables and endpoints

```csharp
var api = builder.AddProject<Projects.Api>("api")
    .WithEnvironment("FEATURE_FLAGS", "beta")
    .WithEnvironment("DB_PASSWORD", dbPassword)        // forward a parameter
    .WithHttpEndpoint(name: "admin", port: 5005)       // extra named endpoint
    .WithExternalHttpEndpoints();                      // expose publicly when deployed
```

- `WithExternalHttpEndpoints()` marks the service's HTTP endpoints as externally reachable in deployment (otherwise they're internal-only).
- `WithEndpoint`/`WithHttpEndpoint`/`WithHttpsEndpoint` declare extra endpoints; reference a specific one with `GetEndpoint("admin")`.

## Replicas

```csharp
builder.AddProject<Projects.Worker>("worker").WithReplicas(3);
```

Runs N instances. Because consumers call by service name, the discovery layer load-balances across replicas — which also surfaces any place you accidentally hardcoded a single URL.

## Container lifetime and data persistence

By default containers are recreated each `aspire run`. To keep them (and their data) across runs:

```csharp
var pg = builder.AddPostgres("pg")
    .WithLifetime(ContainerLifetime.Persistent)   // reuse the same container instance
    .WithDataVolume("pg-data");                    // persist the data directory

builder.AddRedis("cache").WithDataVolume();         // anonymous volume
```

`ContainerLifetime.Persistent` keeps the container running between AppHost runs (faster startup, retained state); pair it with `WithDataVolume`/`WithBindMount` so data survives a container recreate.

## How ServiceDefaults plugs in

ServiceDefaults is a small shared project every service references; it centralizes cross-cutting setup so the AppHost stays focused on topology. In each service's `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();   // OTel + health checks + service discovery + HTTP resilience
// register client integrations + your services
var app = builder.Build();
app.MapDefaultEndpoints();      // /health (ready) and /alive (live)
app.MapGet("/", () => "ok");
app.Run();
```

`AddServiceDefaults()` (full implementation in [../assets/ServiceDefaults.cs](../assets/ServiceDefaults.cs)) does four things:

1. **OpenTelemetry** — logging, metrics (ASP.NET Core, HttpClient, runtime), and tracing, exported via OTLP to the dashboard (`OTEL_EXPORTER_OTLP_ENDPOINT`, injected by the AppHost).
2. **Health checks** — a default liveness check; `MapDefaultEndpoints` exposes `/health` (all checks, used for readiness) and `/alive` (liveness-tagged only).
3. **Service discovery** — resolves `https://<name>` references injected by `WithReference`.
4. **HTTP resilience** — a Polly-backed pipeline (timeouts, retries, circuit breaker) applied to all `HttpClient`s, plus the service-discovery handler.

This is why a service can do `new HttpClient().GetAsync("https://api/...")` (via `IHttpClientFactory`) and have it resolve, retry, and trace automatically.

For the client-side registration calls (`AddNpgsqlDbContext`, `AddRedisClient`, etc.) that consume these resources, see [integrations.md](integrations.md).
