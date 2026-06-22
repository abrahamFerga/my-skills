# Aspire integrations reference (hosting vs client)

Scope: the two-package pattern for every common backing resource, plus the EF Core client integrations. **Hosting** packages (`Aspire.Hosting.*`) go in the AppHost and declare the resource. **Client** packages (`Aspire.*`) go in each consuming service and register the SDK type (DbContext, multiplexer, client) using the connection name from the AppHost.

## The pattern in one picture

```
AppHost (Aspire.Hosting.Redis)            Service (Aspire.StackExchange.Redis)
  builder.AddRedis("cache")        ───►     builder.AddRedisClient("cache")
                  └──── same connection name ────┘
```

Add the hosting package with `aspire add <name>` from the AppHost; add the client package to each service's `.csproj` manually (or via your IDE) and call its registration method in `Program.cs`.

## Hosting ↔ client table

| Resource | Hosting package (AppHost) | AppHost call | Client package (service) | Client registration | Registered type |
|----------|---------------------------|--------------|--------------------------|---------------------|-----------------|
| PostgreSQL (raw) | `Aspire.Hosting.PostgreSQL` | `AddPostgres("pg").AddDatabase("appdb")` | `Aspire.Npgsql` | `AddNpgsqlDataSource("appdb")` | `NpgsqlDataSource` |
| PostgreSQL (EF Core) | `Aspire.Hosting.PostgreSQL` | `AddPostgres("pg").AddDatabase("appdb")` | `Aspire.Npgsql.EntityFrameworkCore.PostgreSQL` | `AddNpgsqlDbContext<T>("appdb")` | `DbContext` subclass |
| Redis | `Aspire.Hosting.Redis` | `AddRedis("cache")` | `Aspire.StackExchange.Redis` | `AddRedisClient("cache")` | `IConnectionMultiplexer` |
| Redis (distributed cache) | `Aspire.Hosting.Redis` | `AddRedis("cache")` | `Aspire.StackExchange.Redis.DistributedCaching` | `AddRedisDistributedCache("cache")` | `IDistributedCache` |
| Redis (output cache) | `Aspire.Hosting.Redis` | `AddRedis("cache")` | `Aspire.StackExchange.Redis.OutputCaching` | `AddRedisOutputCache("cache")` | output-cache store |
| SQL Server (raw) | `Aspire.Hosting.SqlServer` | `AddSqlServer("sql").AddDatabase("appdb")` | `Aspire.Microsoft.Data.SqlClient` | `AddSqlServerClient("appdb")` | `SqlConnection` |
| SQL Server (EF Core) | `Aspire.Hosting.SqlServer` | `AddSqlServer("sql").AddDatabase("appdb")` | `Aspire.Microsoft.EntityFrameworkCore.SqlServer` | `AddSqlServerDbContext<T>("appdb")` | `DbContext` subclass |
| RabbitMQ | `Aspire.Hosting.RabbitMQ` | `AddRabbitMQ("rabbit")` | `Aspire.RabbitMQ.Client` | `AddRabbitMQClient("rabbit")` | `IConnection` |
| Azure Service Bus | `Aspire.Hosting.Azure.ServiceBus` | `AddAzureServiceBus("sb")` | `Aspire.Azure.Messaging.ServiceBus` | `AddAzureServiceBusClient("sb")` | `ServiceBusClient` |
| Azure Storage (blobs) | `Aspire.Hosting.Azure.Storage` | `AddAzureStorage("storage").AddBlobs("blobs")` | `Aspire.Azure.Storage.Blobs` | `AddAzureBlobClient("blobs")` | `BlobServiceClient` |
| Azure Storage (queues) | `Aspire.Hosting.Azure.Storage` | `AddAzureStorage("storage").AddQueues("queues")` | `Aspire.Azure.Storage.Queues` | `AddAzureQueueClient("queues")` | `QueueServiceClient` |
| Azure Key Vault | `Aspire.Hosting.Azure.KeyVault` | `AddAzureKeyVault("kv")` | `Aspire.Azure.Security.KeyVault` | `AddAzureKeyVaultSecrets("kv")` | `SecretClient` |
| Azure Cosmos DB (raw) | `Aspire.Hosting.Azure.CosmosDB` | `AddAzureCosmosDB("cosmos").AddDatabase("appdb")` | `Aspire.Microsoft.Azure.Cosmos` | `AddAzureCosmosClient("cosmos")` | `CosmosClient` |
| Azure Cosmos DB (EF Core) | `Aspire.Hosting.Azure.CosmosDB` | `AddAzureCosmosDB("cosmos").AddDatabase("appdb")` | `Aspire.Microsoft.EntityFrameworkCore.Cosmos` | `AddCosmosDbContext<T>("appdb")` | `DbContext` subclass |
| MongoDB | `Aspire.Hosting.MongoDB` | `AddMongoDB("mongo").AddDatabase("appdb")` | `Aspire.MongoDB.Driver` | `AddMongoDBClient("appdb")` | `IMongoClient` |

> Method/package names occasionally shift across 13.x patches and the `Add*Client` overloads vary (some take the connection name, some a configure callback). When a name doesn't resolve, `aspire add <resource>` and the [integrations gallery](https://aspire.dev/integrations/gallery/) show the exact current call for that version. Pin all `Aspire.*` packages to the same minor as the rest of the family (13.4.x).

## EF Core client integrations

The `Aspire.*.EntityFrameworkCore.*` packages register a pooled `DbContext` whose connection string comes from the matching AppHost resource. They add connection retries, a health check, and OpenTelemetry — on top of normal EF Core.

```csharp
// PostgreSQL — Aspire.Npgsql.EntityFrameworkCore.PostgreSQL
builder.AddNpgsqlDbContext<AppDbContext>("appdb");

// SQL Server — Aspire.Microsoft.EntityFrameworkCore.SqlServer
builder.AddSqlServerDbContext<AppDbContext>("appdb");

// Cosmos DB — Aspire.Microsoft.EntityFrameworkCore.Cosmos
builder.AddCosmosDbContext<AppDbContext>("appdb", "appdb");
```

The `"appdb"` argument must equal the connection name from `AddDatabase("appdb")` in the AppHost. To tweak EF Core behavior (e.g. enable retries, configure the context), pass the `configureDbContextOptions` callback overload.

For everything about the `DbContext` itself — entities, relationships, migrations, queries, and Aspire-hosted migration commands (`Aspire.Hosting.EntityFrameworkCore`, 13.3+) — defer to [../../entity-framework-core/SKILL.md](../../entity-framework-core/SKILL.md). Aspire's job stops at handing EF Core a working, instrumented connection.

## Local development behavior

- Non-Azure resources (Postgres, Redis, SQL Server, RabbitMQ, Mongo) run as **containers** locally with auto-generated credentials; the AppHost injects the connection string so clients need no manual config.
- Azure resources can run against an **emulator** locally via `RunAsEmulator()` (Cosmos, Storage, Service Bus emulator) or be **provisioned**/connected for real — see [azure.md](azure.md).
- Health checks contributed by client integrations feed the dashboard and `MapDefaultEndpoints()` readiness gating.

## Adding an integration end to end

```bash
# 1. AppHost: add the hosting package + resource
cd MyApp.AppHost
aspire add redis              # adds Aspire.Hosting.Redis
```

```csharp
// 2. AppHost: declare and reference
var cache = builder.AddRedis("cache");
builder.AddProject<Projects.Api>("api").WithReference(cache).WaitFor(cache);
```

```xml
<!-- 3. Service .csproj: add the client package -->
<PackageReference Include="Aspire.StackExchange.Redis" Version="13.4.0" />
```

```csharp
// 4. Service Program.cs: register the client (name matches the AppHost)
builder.AddServiceDefaults();
builder.AddRedisClient("cache");
```
