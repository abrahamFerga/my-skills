# Migrations

Scope: managing schema with EF Core 10 migrations — the `dotnet ef` CLI, design-time factories, multiple `DbContext`s, and (most importantly) **how to apply migrations in production** without shooting yourself in the foot. A migration is a versioned, generated C# diff of your model plus the SQL to apply/revert it, tracked in a `__EFMigrationsHistory` table.

## CLI setup

```bash
dotnet tool install --global dotnet-ef --version 10.0.9   # or: dotnet tool update --global dotnet-ef
dotnet tool restore                                       # if pinned in .config/dotnet-tools.json (preferred for teams)
```

`dotnet ef` needs `Microsoft.EntityFrameworkCore.Design` referenced in the startup project. Keep the tool, `.Design`, and the runtime packages on the same `10.0.x` minor.

## Core commands

```bash
# Add a migration (run from the project dir; -s points at the startup project if separate)
dotnet ef migrations add AddPostRating

# Apply pending migrations to the target DB (DEV)
dotnet ef database update

# Roll back to a named migration (down-migrations) — locally only
dotnet ef database update AddPostRating
dotnet ef database update 0            # revert everything

# Remove the LAST migration (only if NOT yet applied/shared)
dotnet ef migrations remove

# List migrations and their applied state
dotnet ef migrations list

# Multi-project: model in Data, host in Api
dotnet ef migrations add Init -p src/Shop.Data -s src/Shop.Api
```

> Never edit or `remove` a migration that has been applied to a shared/prod DB. To undo it there, add a **new** migration that reverses the change.

## Design-time factory (when the host can't be built at design time)

`dotnet ef` tries to instantiate your app's host to get the `DbContext`. If that fails (no parameterless options, special bootstrapping, Aspire AppHost, etc.), supply an `IDesignTimeDbContextFactory<T>`:

```csharp
public class ShopContextFactory : IDesignTimeDbContextFactory<ShopContext>
{
    public ShopContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<ShopContext>()
            // design-time only: a local/dummy connection string is fine; EF reads the MODEL, not data
            .UseSqlServer("Server=localhost;Database=Shop_Design;Trusted_Connection=True;TrustServerCertificate=True")
            .Options;
        return new ShopContext(options);
    }
}
```

This factory is used **only** by the CLI to build migrations — it does not affect runtime. The connection string here can be a local/scratch DB; migration generation only needs the model.

## Producing deployment artifacts

### Idempotent SQL script (review-friendly, DBA-friendly)

Generates SQL that checks `__EFMigrationsHistory` and applies only what's missing — safe to run repeatedly and against a DB at any migration state.

```bash
dotnet ef migrations script --idempotent -o migrate.sql
# range form: from one migration up to another
dotnet ef migrations script AddPostRating AddTags --idempotent -o delta.sql
```

Use when a DBA must review/run changes, or in regulated environments. Always prefer `--idempotent` over the default (non-idempotent) script for CI.

### Migration bundle (self-contained executable, best for CI/CD)

A single executable that applies pending migrations. No SDK, no source, no `dotnet ef` on the deploy agent.

```bash
dotnet ef migrations bundle --self-contained -r linux-x64 -o efbundle
# then, in the pipeline (connection string via env/arg — never baked in):
./efbundle --connection "$DB_CONNECTION_STRING"
```

`--self-contained` bundles the runtime too. Drop it for a framework-dependent (smaller) bundle when the agent has the .NET 10 runtime. Bundles are the recommended default for pipeline-driven deploys.

## Applying migrations: CI/deploy step vs at startup

This is the single most consequential decision in this file.

| Approach | Use it? | Why |
|----------|---------|-----|
| **Idempotent script run by deploy/DBA** | ✅ Preferred for controlled/regulated envs | Reviewable, reversible plan, no runtime DDL rights |
| **Migration bundle as a pipeline step** | ✅ Preferred for CI/CD | Self-contained, runs once before app rollout, fails the deploy loudly |
| **`context.Database.Migrate()` at app startup** | ⚠️ Only dev/prototypes/single-instance | See risks below |
| **`EnsureCreated()`** | ❌ Never with migrations | Creates schema without history; incompatible with `Migrate()`. Tests only. |

### Why auto-migrate-at-startup is risky in production

- **Race conditions**: rolling deploys / multiple replicas all call `Migrate()` at once — concurrent DDL, deadlocks, partial application.
- **Runtime privileges**: the app's DB login needs schema-altering rights at all times (larger attack surface) rather than only during a controlled deploy.
- **No review / no plan**: schema changes happen implicitly on boot with no DBA gate and no easy rollback.
- **Coupling startup to DB availability**: a slow/locked migration blocks the app from starting and can crash-loop.
- **Hard to fail safely**: a bad migration takes the app down rather than failing an isolated pipeline step.

If you must migrate at startup (a single-instance internal app), gate it behind a leader-election/lock and an explicit env flag, and never in a multi-replica deployment.

```csharp
// Acceptable only for dev / single-instance, behind a flag:
if (app.Environment.IsDevelopment())
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<ShopContext>().Database.MigrateAsync();
}
```

## Multiple DbContexts

Disambiguate every command with `--context`:

```bash
dotnet ef migrations add Init --context ShopContext   --output-dir Migrations/Shop
dotnet ef migrations add Init --context AuditContext  --output-dir Migrations/Audit
dotnet ef database update    --context AuditContext
```

Keep each context's migrations in its own folder/assembly. Configure the migrations assembly if it differs from the context:

```csharp
options.UseSqlServer(cs, sql => sql.MigrationsAssembly("Shop.Migrations"));
```

## Seeding data

Two options:

- **Model seeding** (`HasData`) — for static reference data the migration knows at design time. EF emits `INSERT`s into the migration and keeps them in sync.

  ```csharp
  modelBuilder.Entity<Country>().HasData(
      new Country { Id = 1, Code = "US" },
      new Country { Id = 2, Code = "GB" });
  ```

- **`UseSeeding` / `UseAsyncSeeding`** (EF Core 9+) — runtime seeding hooks invoked by `EnsureCreated`/`Migrate` for data that needs services or isn't statically known. Prefer this for non-trivial seed logic; `HasData` for small fixed lookups.

## Customizing migration SQL

Edit the generated `Up`/`Down` for things EF can't infer (raw SQL, data backfills, index hints):

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.AddColumn<string>("Slug", "Blogs", nullable: true);
    migrationBuilder.Sql("UPDATE Blogs SET Slug = LOWER(REPLACE(Name, ' ', '-'));");
    migrationBuilder.AlterColumn<string>("Slug", "Blogs", nullable: false);
}
```

For zero-downtime schema changes, split into expand → migrate-data → contract across multiple deploys.

## EF10 note: per-migration transactions

EF9 wrapped *all* migrations applied in one call inside a single transaction; EF10 **reverts** that — each migration applies in its own transaction again (fixes scenarios where statements can't run inside a user transaction, e.g. certain SQL Server operations). See [ef-core-10.md](ef-core-10.md).

## More info

- [Applying migrations](https://learn.microsoft.com/ef/core/managing-schemas/migrations/applying)
- [Migration bundles (DevOps-friendly)](https://devblogs.microsoft.com/dotnet/introducing-devops-friendly-ef-core-migration-bundles/)
- [Design-time DbContext creation](https://learn.microsoft.com/ef/core/cli/dbcontext-creation)
- [Using a separate migrations project](https://learn.microsoft.com/ef/core/managing-schemas/migrations/projects)
