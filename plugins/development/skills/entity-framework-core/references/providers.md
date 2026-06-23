# Providers & DI Registration

Scope: per-provider setup and quirks (SQL Server/Azure SQL, SQLite, PostgreSQL via Npgsql, Cosmos, InMemory), the three DI registration shapes and their tradeoffs, `DbContextOptions`, connection resiliency, and how Aspire wires all of this for you. Connection strings always come from configuration/secrets — never hardcoded.

## Choosing the DI registration shape

| API | Lifetime | Use when | Caution |
|-----|----------|----------|---------|
| `AddDbContext<T>` | Scoped | Default for web apps — one context per request | — |
| `AddDbContextPool<T>` | Scoped (pooled) | High-throughput web APIs; reuses context instances to cut allocation/setup cost | Pooled instances are **reset & reused** — never store request state in `DbContext` fields; `OnConfiguring` runs once |
| `AddDbContextFactory<T>` + `IDbContextFactory<T>` | You own the instance | Blazor Server, background services, parallel work, anything needing multiple short-lived contexts in one scope | You must `await using` / dispose each created context |
| `AddPooledDbContextFactory<T>` | Pooled factory | Factory pattern + pooling benefits | Same reset caveat as pooling |

```csharp
// Standard
builder.Services.AddDbContext<ShopContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Shop")));

// Pooled (high throughput)
builder.Services.AddDbContextPool<ShopContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Shop")), poolSize: 256);

// Factory (Blazor / background / parallel)
builder.Services.AddDbContextFactory<ShopContext>(o =>
    o.UseSqlServer(builder.Configuration.GetConnectionString("Shop")));

// usage:
await using var db = await factory.CreateDbContextAsync();
```

> **Pooling tradeoff:** pooling reuses the context object (resetting EF-known state) to avoid per-request setup. It does **not** reset your own instance fields, and the same options instance is shared — don't capture per-request services in `OnConfiguring`. Size `poolSize` ≤ your DB's connection ceiling.

## DbContextOptions essentials

```csharp
o.UseSqlServer(cs, sql =>
{
    sql.EnableRetryOnFailure(maxRetryCount: 5, maxRetryDelay: TimeSpan.FromSeconds(10), errorNumbersToAdd: null);
    sql.CommandTimeout(30);
    sql.MigrationsAssembly("Shop.Migrations");
})
.UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)   // read-heavy default
.LogTo(Console.WriteLine, LogLevel.Warning);
// .EnableSensitiveDataLogging()  // DEV ONLY — logs parameter values
// .EnableDetailedErrors()        // DEV ONLY — slower, clearer materialization errors
```

Prefer configuring via DI (the lambda above) over overriding `OnConfiguring` so options come from the container.

## SQL Server / Azure SQL

`Microsoft.EntityFrameworkCore.SqlServer` (`10.0.9`).

```csharp
o.UseSqlServer(cs, sql => sql.EnableRetryOnFailure());
// EF10: opt into Azure SQL-specific behavior (e.g. defaults to native json type, retry tuning)
o.UseAzureSql(cs);
```

- **Connection resiliency**: always `EnableRetryOnFailure()` for cloud SQL — transient faults are normal. The default execution strategy retries known transient error numbers.
- **EF10**: with `UseAzureSql` or compatibility level ≥ 170 (SQL Server 2025), JSON columns default to the native `json` type, and the `vector` type / `VECTOR_DISTANCE` become available. See [ef-core-10.md](ef-core-10.md).
- **Manual transactions + retry**: wrap in the execution strategy (below).

## SQLite

`Microsoft.EntityFrameworkCore.Sqlite` (`10.0.9`). Great for local dev, edge/desktop apps, and **fast tests** (file or shared in-memory).

```csharp
o.UseSqlite("Data Source=shop.db");
```

Quirks: limited ALTER TABLE (EF rebuilds tables on some migrations), looser typing (type affinity), and no decimal ordering historically (EF10 adds `MIN`/`MAX`/`ORDER BY` over `decimal` on SQLite). For in-memory test usage and the connection-must-stay-open caveat, see [testing.md](testing.md).

## PostgreSQL (Npgsql — third-party, separate cadence)

`Npgsql.EntityFrameworkCore.PostgreSQL` (`10.0.2`, May 2026). This is **not** a Microsoft package and versions independently of EF Core; pair `10.0.x` Npgsql with `10.0.x` EF Core.

```csharp
o.UseNpgsql(builder.Configuration.GetConnectionString("Shop"),
    npg => npg.EnableRetryOnFailure());
```

Strengths: rich PostgreSQL type mapping (arrays, `jsonb`, ranges, `hstore`, `cube`, full-text `tsvector`, network types), `xmin` concurrency token, generated columns. The `10.0` line adds JSON-mapped complex types, PostgreSQL 18 virtual generated columns, and full `cube` support. Use `jsonb` (not `json`) for queryable JSON.

## Azure Cosmos DB for NoSQL

`Microsoft.EntityFrameworkCore.Cosmos` (`10.0.9`). Document database — different semantics from relational (partition keys, RU cost, no migrations, eventual consistency).

```csharp
o.UseCosmos(
    accountEndpoint: builder.Configuration["Cosmos:Endpoint"]!,
    tokenCredential: new DefaultAzureCredential(),     // prefer AAD over keys
    databaseName: "shop");
```

- Model with **partition keys** (`HasPartitionKey`) — central to performance and cost.
- No migrations; containers are created/used at runtime.
- **EF10 Cosmos**: vector search exits preview (`IsVectorProperty`/`IsVectorIndex`), full-text search (`EnableFullTextSearch`, `EF.Functions.FullTextContains`), hybrid search via `EF.Functions.Rrf`, retrying via `ExecutionStrategy`, and smoother model evolution (default values for new required properties). See [ef-core-10.md](ef-core-10.md).

## InMemory — tests only, with caveats

`Microsoft.EntityFrameworkCore.InMemory` (`10.0.9`). **Not a relational database.** No SQL, no FK/unique/check constraints, no transactions semantics, no provider type mapping. It will pass tests that a real DB would fail (and vice versa).

```csharp
o.UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString());  // isolate per test
```

Use it only for trivial logic that doesn't depend on relational behavior. For real correctness, use **SQLite-in-memory** or **Testcontainers** — see [testing.md](testing.md). Microsoft officially recommends against InMemory for general testing.

## Connection resiliency + manual transactions

When you need an explicit transaction *and* retries, you must run it inside the execution strategy (a retry can replay the whole block):

```csharp
var strategy = db.Database.CreateExecutionStrategy();
await strategy.ExecuteAsync(async () =>
{
    await using var tx = await db.Database.BeginTransactionAsync();
    db.Add(new Order { /* ... */ });
    await db.SaveChangesAsync();
    await SomeOtherWork(db);
    await tx.CommitAsync();
});
```

Forgetting this throws: "The configured execution strategy does not support user-initiated transactions."

## Aspire-managed registration (preferred when using Aspire)

If the app is part of a .NET Aspire solution, **don't** hand-wire `AddDbContext` + connection strings. Use the client integration in the service project:

```csharp
// SQL Server
builder.AddSqlServerDbContext<ShopContext>("shop");
// PostgreSQL
builder.AddNpgsqlDbContext<ShopContext>("shop");
// Cosmos
builder.AddCosmosDbContext<ShopContext>("shop", "shopdb");
```

These read the connection string from Aspire's service discovery, register the `DbContext`, and add health checks + OpenTelemetry automatically. The connection string is defined once in the AppHost. See the [`aspire`](../../aspire/SKILL.md) skill for the AppHost side and migration/seeding patterns under Aspire.

## More info

- [Database providers](https://learn.microsoft.com/ef/core/providers/)
- [Connection resiliency](https://learn.microsoft.com/ef/core/miscellaneous/connection-resiliency)
- [DbContext lifetime, configuration, and initialization](https://learn.microsoft.com/ef/core/dbcontext-configuration/)
- [Npgsql EF Core provider](https://www.npgsql.org/efcore/)
- [Cosmos provider](https://learn.microsoft.com/ef/core/providers/cosmos/)
