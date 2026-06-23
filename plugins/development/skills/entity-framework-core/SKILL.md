---
name: entity-framework-core
description: >
  Build the data-access / persistence layer of .NET apps with Entity Framework
  Core 10 (EF10, .NET 10 LTS). Use for `DbContext` design and DI registration,
  modeling (relationships, owned/complex types, JSON columns, inheritance),
  migrations (`dotnet ef`, idempotent scripts, bundles), querying and
  performance (`AsNoTracking`, split/compiled queries,
  `ExecuteUpdate`/`ExecuteDelete`, fixing N+1), providers (SQL Server, SQLite,
  PostgreSQL, Cosmos), and data-layer testing. DO NOT USE FOR app/container
  orchestration and connection-string wiring (use ../aspire/SKILL.md — its
  client integrations register the `DbContext`) or deciding where the data layer
  sits in the architecture (use /architecture:dotnet-architecture).
license: MIT
---

# Entity Framework Core (EF Core 10)

Build the persistence layer of a .NET app with **EF Core 10** (EF10), the LTS release that ships with **.NET 10** (supported through Nov 2028). EF Core is an object-relational mapper: you define a `DbContext` and plain CLR entity classes, EF builds a *model*, tracks changes, translates LINQ to provider SQL, and round-trips results back into objects.

Reach for EF Core when you want a productive, type-safe, migration-driven data layer over a relational (or Cosmos) store. Drop to Dapper / raw ADO.NET only for surgical hot paths. This skill is EF Core-only — not EF6 "classic", not other ORMs.

## Scope

Covers the full surface: `DbContext` design and DI registration (`AddDbContext`, `AddDbContextPool`, `AddDbContextFactory`), modeling (fluent API vs annotations, relationships, owned entities, complex types, JSON columns, value converters, conventions, inheritance TPH/TPT/TPC), migrations (`dotnet ef`, idempotent scripts, bundles, design-time factories, CI vs startup application), querying and performance (projections, `AsNoTracking`, split queries, compiled queries, `ExecuteUpdate`/`ExecuteDelete`, the N+1 problem), connection resiliency, providers (SQL Server, SQLite, PostgreSQL, Cosmos, InMemory), EF10 deltas (named query filters, vector search, `LeftJoin`/`RightJoin`, non-expression `ExecuteUpdate` lambdas), and testing (SQLite-in-memory, Testcontainers, Respawn, Aspire).

USE FOR: scaffolding a `DbContext` + entities and wiring it into DI; designing the model and relationships; adding/applying/scripting migrations; fixing N+1, tracking, or cartesian-explosion perf problems; bulk `ExecuteUpdate`/`ExecuteDelete`; picking or configuring a provider; concurrency tokens; adopting EF10 features; writing data-layer tests.

DO NOT USE FOR: micro-optimized hot paths where every millisecond counts (use Dapper or raw ADO.NET); app/container orchestration and connection-string wiring (use [../aspire/SKILL.md](../aspire/SKILL.md) — its client integrations register the EF `DbContext`, connection string, health checks, and OTel for you); deciding where the data layer sits in a clean/onion architecture (use `/architecture:dotnet-architecture`); non-EF ORMs (NHibernate, LINQ to DB); Entity Framework 6.x / EF "classic" on .NET Framework (this skill is EF Core only).

## When to Use

- Scaffolding a new `DbContext` + entities and registering it in DI
- Designing the model: relationships, owned entities, **complex types**, JSON columns, value converters, conventions, inheritance mapping (TPH/TPT/TPC)
- Creating, applying, scripting, or bundling **migrations**; design-time factories; multiple `DbContext`s
- Querying: projections, eager/lazy/explicit loading, fixing the **N+1** problem, pagination, split vs single queries, compiled queries
- Bulk writes without change-tracking: `ExecuteUpdate`/`ExecuteDelete`
- Diagnosing perf: tracking overhead, cartesian explosion, client evaluation
- Concurrency tokens (`rowversion`/`[Timestamp]`), connection resiliency (`EnableRetryOnFailure`)
- Picking or configuring a provider (SQL Server / Azure SQL, SQLite, PostgreSQL, Cosmos, InMemory)
- Adopting EF10 features (named query filters, vector search, `LeftJoin`/`RightJoin`)
- Writing tests against the data layer

## Stop Signals

- **Micro-optimized hot path, every µs matters** → Dapper or raw `ADO.NET`/`Microsoft.Data.SqlClient`. EF's tracking + materialization has overhead.
- **You just need orchestration + a connection string wired up** → the [`aspire`](../aspire/SKILL.md) skill. Aspire client integrations (`AddSqlServerDbContext`, `AddNpgsqlDbContext`, `AddCosmosDbContext`) register the `DbContext`, inject the connection string, and add health checks + OpenTelemetry.
- **Deciding which layer the data code belongs in** → the `/architecture:dotnet-architecture` skill (EF Core lives in the Infrastructure layer behind a repository / `DbContext` abstraction).
- **A non-EF ORM** (NHibernate, LINQ to DB, Marten) → out of scope.
- **EF6 / "EF classic" on .NET Framework** → this skill targets EF Core 10 on .NET 10 only.
- **Heavy reporting / set-based ETL** → consider raw SQL views + `FromSql`, or a dedicated tool; don't force LINQ.

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Provider | Yes | `SqlServer` (incl. Azure SQL), `Sqlite`, PostgreSQL (`Npgsql`), `Cosmos`, or `InMemory` (tests only). Default SQL Server if unspecified. |
| Target framework | Yes | `net10.0` (EF10 requires the .NET 10 SDK/runtime; will not run on .NET 9 or earlier, or .NET Framework). |
| Database / connection string | Yes | From env / `IConfiguration` / user-secrets / Key Vault — **never hardcoded**. Aspire injects it for you. |
| Modeling approach | Recommended | Fluent API (preferred for non-trivial models), data annotations, or scaffold-from-existing-DB. |
| Migration strategy | Recommended | How schema is applied: `dotnet ef database update` in dev; **idempotent script** or **migration bundle** in CI/CD. Avoid auto-migrate-at-startup in prod. |
| Tracking default | Optional | `QueryTrackingBehavior.NoTracking` is a good context-wide default for read-heavy services. |

## Version / package status (as of EF Core 10.0.x)

EF Core 10.0 was released Nov 2025; latest patch is **10.0.9** (June 2026). The first-party packages version in lockstep under `10.0.x` — pin the same minor across all of them (a given sub-package may sit one patch behind because it only re-releases when it changes; floating to `10.0.*` keeps them aligned). The PostgreSQL provider is third-party (Npgsql) on its **own** cadence: `10.0.2` (May 2026).

| Package | Version | Use when |
|---------|---------|----------|
| `Microsoft.EntityFrameworkCore` | `10.0.9` | Core (transitive via any provider) |
| `Microsoft.EntityFrameworkCore.Relational` | `10.0.9` | Pulled in by relational providers |
| `Microsoft.EntityFrameworkCore.SqlServer` | `10.0.9` | SQL Server + Azure SQL provider |
| `Microsoft.EntityFrameworkCore.Sqlite` | `10.0.9` | SQLite provider (and SQLite-in-memory tests) |
| `Microsoft.EntityFrameworkCore.Cosmos` | `10.0.9` | Azure Cosmos DB for NoSQL provider |
| `Microsoft.EntityFrameworkCore.InMemory` | `10.0.9` | **Tests only** — not a real DB (see pitfalls) |
| `Microsoft.EntityFrameworkCore.Design` | `10.0.9` | Design-time (migrations/scaffolding). `PrivateAssets="all"` |
| `Microsoft.EntityFrameworkCore.Tools` | `10.0.9` | PMC cmdlets (`Add-Migration`); optional if using `dotnet ef` |
| `Npgsql.EntityFrameworkCore.PostgreSQL` | `10.0.2` | PostgreSQL provider (third-party, separate cadence) |
| `dotnet-ef` (global tool) | `10.0.9` | CLI: `dotnet tool install --global dotnet-ef --version 10.0.9` |

> Provider packages bring `Microsoft.EntityFrameworkCore` and `.Relational` transitively — you usually only add the provider + `.Design`. Keep `dotnet-ef` and `.Design` on the same minor as the runtime packages.

## Core Mental Model

```
            your LINQ / SaveChanges()
                      |
                      v
+-----------------------------------------------+
|  DbContext                                     |
|   ├─ DbSet<T>            (query roots)         |
|   ├─ Model               (built once, cached)  |  ← OnModelCreating + conventions
|   ├─ Change Tracker      (snapshots, states)   |  ← Added/Modified/Deleted/Unchanged
|   └─ Database facade     (transactions, SQL)   |
+-----------------------------------------------+
                      |
                      v
+-----------------------------------------------+
|  Database Provider  (SqlServer / Npgsql / ...) |
|   ├─ LINQ → SQL translation                    |
|   ├─ type mapping & value converters           |
|   └─ migrations SQL generation                 |
+-----------------------------------------------+
                      |
                      v
              ADO.NET connection → SQL → DB
```

A `DbContext` is a **short-lived unit of work**: one per request/operation, **not thread-safe**, never a singleton. The change tracker holds snapshots so `SaveChanges()` can compute the right `INSERT/UPDATE/DELETE`. `AsNoTracking()` skips that bookkeeping for read-only queries.

| Concept | What it is |
|---------|-----------|
| Entity type | A CLR class mapped to a table/container; has a key + identity |
| Owned type | A child object that shares the owner's table (or a JSON column); no key of its own. EF10: prefer **complex types** for new code |
| Complex type | Value-semantics object mapped to columns or a JSON column; no identity, comparable by value. EF10 adds optional + JSON + struct support |
| Key | PK (`Id`/`<Type>Id` by convention) or composite via `HasKey` |
| Navigation | A reference/collection property representing a relationship |
| Migration | A versioned C# diff of the model applied to the DB schema |
| Tracking | Whether EF snapshots returned entities for change detection |

## Workflow

### Step 1: Scaffold the project and add packages

```bash
dotnet new webapi -n Shop.Api && cd Shop.Api
dotnet add package Microsoft.EntityFrameworkCore.SqlServer --version 10.0.9
dotnet add package Microsoft.EntityFrameworkCore.Design --version 10.0.9   # design-time only

# Design-time CLI (once per machine; keep on the same minor as the runtime)
dotnet tool install --global dotnet-ef --version 10.0.9
```

Mark `.Design` as a private dev dependency so it doesn't flow to consumers:

```xml
<PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="10.0.9">
  <PrivateAssets>all</PrivateAssets>
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
</PackageReference>
```

### Step 2: Define the `DbContext` and entities

```csharp
public class Blog
{
    public int Id { get; set; }                    // PK by convention (Id / BlogId)
    public required string Name { get; set; }
    public List<Post> Posts { get; set; } = [];    // collection navigation
}

public class Post
{
    public int Id { get; set; }
    public required string Title { get; set; }
    public int BlogId { get; set; }                // FK by convention
    public Blog Blog { get; set; } = null!;        // reference navigation
}

public class ShopContext(DbContextOptions<ShopContext> options) : DbContext(options)
{
    public DbSet<Blog> Blogs => Set<Blog>();
    public DbSet<Post> Posts => Set<Post>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(ShopContext).Assembly);
    }
}
```

> Prefer the primary-constructor `DbContextOptions<T>` shape over overriding `OnConfiguring` — it lets DI own configuration. Keep entity config in `IEntityTypeConfiguration<T>` classes, not a giant `OnModelCreating`. See [references/modeling.md](references/modeling.md).

### Step 3: Register in DI (no hardcoded connection string)

```csharp
builder.Services.AddDbContext<ShopContext>(options =>
    options.UseSqlServer(
        builder.Configuration.GetConnectionString("Shop"),
        sql => sql.EnableRetryOnFailure()));        // connection resiliency
```

Connection string comes from `appsettings.json` → env vars → user-secrets (`dotnet user-secrets set ConnectionStrings:Shop "..."`) → Key Vault in prod. **Never** commit it.

DI shape choices (full matrix in [references/providers.md](references/providers.md)):

| API | When |
|-----|------|
| `AddDbContext<T>` | Default. Scoped lifetime, one per request. |
| `AddDbContextPool<T>` | High-throughput web apps — reuses context instances (resets state). Don't store request state in fields. |
| `AddDbContextFactory<T>` / `IDbContextFactory<T>` | Blazor, background/parallel work, or anywhere you need to control context lifetime explicitly. |

> Using Aspire? Let its client integration register all this instead — see [`aspire`](../aspire/SKILL.md).

### Step 4: Configure the model (fluent API)

```csharp
public class BlogConfiguration : IEntityTypeConfiguration<Blog>
{
    public void Configure(EntityTypeBuilder<Blog> b)
    {
        b.Property(x => x.Name).HasMaxLength(200).IsRequired();
        b.HasIndex(x => x.Name);
        b.HasMany(x => x.Posts).WithOne(p => p.Blog)
            .HasForeignKey(p => p.BlogId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
```

Owned types, complex types, JSON columns, value converters, inheritance → [references/modeling.md](references/modeling.md).

### Step 5: Add and apply a migration

```bash
dotnet ef migrations add InitialCreate
dotnet ef database update              # DEV ONLY — applies to the local DB
```

Inspect the generated migration before committing. For production you do **not** run `database update` against the live DB from a dev box — see Step 7 and [references/migrations.md](references/migrations.md).

### Step 6: Query (and avoid the obvious traps)

```csharp
// Read-only projection — no tracking, only the columns you need
var summaries = await db.Blogs
    .AsNoTracking()
    .Where(b => b.Name.StartsWith("a"))
    .OrderBy(b => b.Name)
    .Select(b => new BlogSummary(b.Id, b.Name, b.Posts.Count))  // translated, no N+1
    .Skip(page * size).Take(size)
    .ToListAsync();

// Eager-load related data in ONE round trip; AsSplitQuery avoids cartesian explosion
var blogs = await db.Blogs
    .Include(b => b.Posts)
    .AsSplitQuery()
    .ToListAsync();

// Bulk update with NO change-tracking, NO round-trip of entities (EF7+; EF10 widens it)
await db.Posts.Where(p => p.BlogId == id)
    .ExecuteUpdateAsync(s => s.SetProperty(p => p.Title, p => p.Title + " (archived)"));
```

Projections, compiled queries, tracking modes, `ExecuteUpdate`/`ExecuteDelete`, the N+1 problem → [references/querying-performance.md](references/querying-performance.md).

### Step 7: Production guardrails

1. **Apply migrations as a deliberate deploy step**, not at app startup. Generate an **idempotent script** (`dotnet ef migrations script --idempotent`) for a DBA, or a **migration bundle** (`dotnet ef migrations bundle`) to run in CI/CD. Auto-migrate-at-startup races across instances, needs schema-altering DB rights at runtime, and has no rollback — see [references/migrations.md](references/migrations.md).
2. **Connection resiliency**: `EnableRetryOnFailure()` (and wrap manual transactions in the execution strategy).
3. **Concurrency control**: a `rowversion`/`[Timestamp]` token on mutable aggregates so concurrent writes throw `DbUpdateConcurrencyException` instead of silently overwriting.
4. **Read paths are `NoTracking`** (per-query or context default).
5. **Secrets** from configuration providers only.
6. **Pool sizing / max-pool** tuned to DB connection limits.
7. **No client evaluation** of filters — confirm `Where` clauses translate (EF throws on un-translatable top-level predicates, but watch projections).

### Step 8: Verify

```bash
dotnet build -warnaserror
dotnet ef migrations script --idempotent -o /tmp/check.sql   # confirm schema diff is sane
dotnet test                                                   # data-layer tests (see testing.md)
```

## Validation

- [ ] Targets `net10.0`; EF packages pinned to `10.0.x` (Npgsql to `10.0.2`)
- [ ] `Microsoft.EntityFrameworkCore.Design` referenced with `PrivateAssets="all"`
- [ ] `DbContext` registered via `AddDbContext`/`AddDbContextPool`/`AddDbContextFactory` — never `new`'d per request manually, never a singleton
- [ ] Connection string from configuration/secrets — nothing hardcoded
- [ ] `EnableRetryOnFailure()` set for SQL Server / Azure SQL / PostgreSQL
- [ ] Read-only queries use `AsNoTracking` (or context-wide `NoTracking` default)
- [ ] Related data eager-loaded with `Include` (+ `AsSplitQuery` where collections cause cartesian explosion) — no N+1
- [ ] Lazy loading **not** enabled by default (it hides N+1)
- [ ] Migrations reviewed before commit; applied via script/bundle in CI — not at startup in prod
- [ ] Mutable aggregates carry a concurrency token (`rowversion`)
- [ ] Tests run against SQLite-file/Testcontainers for relational behavior, **not** the InMemory provider for correctness

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| **N+1 queries** — a loop touching a navigation fires one query per row | `Include` the navigation, or project the needed shape in a single `Select`. See [querying-performance.md](references/querying-performance.md). |
| Tracking on read-only queries wastes memory/CPU | `AsNoTracking()` per query, or `QueryTrackingBehavior.NoTracking` context-wide; use `AsNoTrackingWithIdentityResolution` when the graph has duplicates. |
| **Lazy loading** enabled → silent N+1 and serialization loops | Don't enable proxies by default; load explicitly with `Include`/`Load`. |
| **Cartesian explosion** from multiple `Include` collections | `AsSplitQuery()` (or `UseQuerySplittingBehavior(SplitQuery)` globally). Mind ordering — EF10 fixed split-query ordering consistency. |
| **Auto-migrate at startup** in prod | Idempotent script for a DBA, or a migration bundle as a discrete pipeline step. Startup migration races multi-instance deploys and needs DDL rights at runtime. |
| Client evaluation silently runs C# in memory | Keep `Where`/`OrderBy` translatable; EF throws on un-translatable top-level predicates — don't suppress by forcing `AsEnumerable()` early. |
| Using `Microsoft.EntityFrameworkCore.InMemory` to "test the DB" | It's not relational (no FK/constraints/SQL/transactions semantics). Use SQLite-in-memory or Testcontainers. See [testing.md](references/testing.md). |
| `Update()`/`Attach()` on a whole graph marks everything `Modified` | Track only what changed, or use `ExecuteUpdate` for set-based writes. |
| Sharing one `DbContext` across threads / making it a singleton | Scoped lifetime; `IDbContextFactory<T>` for parallel/background work. Not thread-safe. |
| `SaveChanges` per row in a loop | Batch: add all, then one `SaveChanges`; or `ExecuteUpdate`/`ExecuteDelete` for bulk. |
| Manual transaction silently bypasses retry strategy | Wrap in `context.Database.CreateExecutionStrategy().ExecuteAsync(...)`. |
| Pooled context leaks state via instance fields | Don't store request data in `DbContext` fields; pooling resets only EF-known state. |

## Reference Files

- [references/modeling.md](references/modeling.md) — Fluent API vs annotations, `IEntityTypeConfiguration<T>`, relationships (1:1/1:N/N:N), required/optional, keys & composite keys, indexes, owned entities, **complex types** (incl. EF10 optional/JSON/struct), JSON columns (`ToJson`), value converters, comparers, pre-convention model config, inheritance (TPH/TPT/TPC). **Load when:** designing or changing the entity model.
- [references/migrations.md](references/migrations.md) — `dotnet ef migrations add/remove/list`, `database update`, `migrations script --idempotent`, **migration bundles**, `IDesignTimeDbContextFactory<T>`, multiple `DbContext`s, applying migrations in CI vs at startup (and why startup is risky), data/seed migrations, custom SQL ops. **Load when:** creating, applying, scripting, or deploying schema changes.
- [references/querying-performance.md](references/querying-performance.md) — Projections, eager/lazy/explicit loading, the N+1 problem, `Include`/`ThenInclude`/filtered includes, single vs split queries, tracking modes, compiled queries, pagination (offset vs keyset), `ExecuteUpdate`/`ExecuteDelete`, `FromSql`, batching, diagnostics. **Load when:** writing queries or chasing a perf problem.
- [references/providers.md](references/providers.md) — Per-provider setup and quirks for SQL Server/Azure SQL, SQLite, PostgreSQL (Npgsql), Cosmos, InMemory; `AddDbContext` vs `AddDbContextPool` vs `AddDbContextFactory` tradeoffs; `DbContextOptions`; `EnableRetryOnFailure`; Aspire-managed registration. **Load when:** choosing/configuring a provider or DI registration shape.
- [references/ef-core-10.md](references/ef-core-10.md) — Authoritative "what changed in EF10 and how to use it": named query filters, vector search (`SqlVector<float>`, `VectorDistance`, `IsVectorProperty`/`IsVectorIndex`), SQL Server 2025 `json` type, complex-type improvements, `LeftJoin`/`RightJoin`, non-expression `ExecuteUpdate` lambdas, `ExecuteUpdate` over JSON, parameterized-collection translation, Cosmos full-text/hybrid search, security (log redaction, raw-SQL analyzer), breaking changes + upgrade. **Load when:** adopting EF10 features or upgrading from EF9/EF8.
- [references/testing.md](references/testing.md) — SQLite-in-memory vs SQLite-file vs real-DB-via-Testcontainers vs `Respawn` reset; what the InMemory provider can/can't test; transactions & rollback per test; concurrency tokens (`[Timestamp]`/`rowversion`/`IsConcurrencyToken`); EF Core in Aspire integration tests. **Load when:** writing tests that touch the data layer.

## More Info

- [EF Core documentation](https://learn.microsoft.com/ef/core/) — official docs
- [What's New in EF Core 10](https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/whatsnew) — feature reference for this release
- [Breaking changes in EF Core 10](https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/breaking-changes) — read before upgrading
- [dotnet/efcore](https://github.com/dotnet/efcore) — source, issues, milestones
- [Npgsql EF Core provider](https://www.npgsql.org/efcore/) — PostgreSQL provider docs (separate release cadence)
- [`aspire`](../aspire/SKILL.md) — client integrations that wire EF `DbContext` + connection strings + health checks/OTel
- `/architecture:dotnet-architecture` — where EF Core sits in the Infrastructure layer
