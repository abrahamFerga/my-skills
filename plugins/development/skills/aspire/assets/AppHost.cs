// Representative Aspire 13.x AppHost (single-file C# app model).
// The AppHost .csproj uses Sdk="Aspire.AppHost.Sdk/13.4.x" and references each
// service project as an Aspire project resource so the strongly-typed
// `Projects.*` classes are generated at build time.
//
// This sample wires: a Postgres database, a Redis cache, an Azure Service Bus
// (emulated locally, provisioned in Azure), an API project, and a web frontend,
// then declares an Azure App Service compute environment for deployment.

var builder = DistributedApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Parameters / secrets — externalized to user-secrets (dev) or env vars (CI).
// Never hardcode credentials in the app model.
// ---------------------------------------------------------------------------
var dbPassword = builder.AddParameter("db-password", secret: true);

// ---------------------------------------------------------------------------
// Backing resources. Locally these run as containers; in Azure they map to the
// provisioned service (see references/azure.md).
// ---------------------------------------------------------------------------
var postgres = builder.AddPostgres("postgres", password: dbPassword)
    .WithLifetime(ContainerLifetime.Persistent) // reuse the container across `aspire run`
    .WithDataVolume();                           // persist data between runs
var appDb = postgres.AddDatabase("appdb");

var cache = builder.AddRedis("cache");

// Azure resource: runs on the local emulator for `aspire run`, provisions a real
// namespace on `aspire deploy`.
var serviceBus = builder.AddAzureServiceBus("messaging")
    .RunAsEmulator();
var ordersQueue = serviceBus.AddServiceBusQueue("orders");

// ---------------------------------------------------------------------------
// Services. WithReference injects connection strings / service-discovery URLs;
// WaitFor gates startup until the dependency reports healthy.
// ---------------------------------------------------------------------------
var api = builder.AddProject<Projects.Api>("api")
    .WithReference(appDb).WaitFor(appDb)
    .WithReference(cache).WaitFor(cache)
    .WithReference(ordersQueue).WaitFor(serviceBus);

builder.AddProject<Projects.Web>("web")
    .WithReference(api)                 // service discovery: "https://api" resolves
    .WithExternalHttpEndpoints()        // expose to the outside world
    .WithReplicas(2)
    .WaitFor(api);

// ---------------------------------------------------------------------------
// Compute environment — only needed for `aspire publish` / `aspire deploy`.
// Pick exactly one target. App Service is the default in the sibling
// dotnet-architecture skill; swap the line to retarget.
// ---------------------------------------------------------------------------
if (builder.ExecutionContext.IsPublishMode)
{
    builder.AddAzureAppServiceEnvironment("appsvc");
    // Alternatives:
    //   builder.AddAzureContainerAppEnvironment("aca");
    //   builder.AddKubernetesEnvironment("k8s");
    //   builder.AddDockerComposeEnvironment("compose");
}

builder.Build().Run();
