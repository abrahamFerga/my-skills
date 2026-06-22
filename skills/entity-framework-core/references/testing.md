# Testing the Data Layer

Scope: how to test EF Core 10 code at the right fidelity — SQLite-in-memory vs SQLite-file vs a real DB via Testcontainers vs resetting state with `Respawn` — plus transactions/rollback per test, concurrency tokens, and EF Core inside Aspire integration tests. The core principle: **test against behavior as close to production as the test's purpose requires.** The InMemory provider is the lowest fidelity and should rarely be your correctness test.

## Pick the right fidelity

| Tool | Fidelity | Tests what | Use for |
|------|----------|-----------|---------|
| `InMemory` provider | Lowest — not relational | Pure logic only; no SQL/FK/constraints/transactions | Domain/service logic that asserts return values, not DB side effects. **Microsoft discourages it for general testing.** |
| **SQLite in-memory** | Medium — real relational engine | FK enforcement, unique indexes, cascades, LINQ-translation failures, transactions | Repository / data-access tests where you don't need provider-specific SQL |
| **SQLite file** | Medium | Same as above, persisted between connections | When you want the DB to survive multiple connections without a held-open connection |
| **Testcontainers (real DB image)** | Highest | Exactly your production provider's SQL, types, constraints, migrations | The accurate option for SQL Server / PostgreSQL behavior; integration tests |
| **Respawn** | (reset helper, not a DB) | — | Fast reset of a real DB between tests instead of recreating it |

## SQLite in-memory — keep the connection open

The classic gotcha: a SQLite in-memory database lives only as long as its connection is open. If you pass a *connection string*, EF opens/closes a connection per `DbContext`, and **each context gets a fresh empty DB** — writes from one context are invisible to the next. Fix: open **one** `SqliteConnection` yourself, keep it open for the fixture lifetime, and hand that **connection object** to every context.

```csharp
public sealed class SqliteFixture : IAsyncDisposable
{
    private readonly SqliteConnection _connection;
    private readonly DbContextOptions<ShopContext> _options;

    public SqliteFixture()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();                                   // MUST stay open
        _options = new DbContextOptionsBuilder<ShopContext>()
            .UseSqlite(_connection)                           // pass the OPEN connection, not a string
            .Options;

        using var ctx = CreateContext();
        ctx.Database.EnsureCreated();                         // build schema from the model (no migrations)
    }

    public ShopContext CreateContext() => new(_options);
    public async ValueTask DisposeAsync() => await _connection.DisposeAsync();
}
```

```csharp
public class BlogRepositoryTests(SqliteFixture fixture) : IClassFixture<SqliteFixture>
{
    [Fact]
    public async Task Unique_name_violation_throws()
    {
        await using var ctx = fixture.CreateContext();
        ctx.Blogs.Add(new Blog { Name = "dup" });
        ctx.Blogs.Add(new Blog { Name = "dup" });
        await Assert.ThrowsAsync<DbUpdateException>(() => ctx.SaveChangesAsync());  // SQLite enforces the unique index
    }
}
```

> `EnsureCreated()` builds the schema directly from the model — fast, but it **does not run migrations**, so it won't catch migration bugs or custom migration SQL. To test migrations themselves, run `context.Database.Migrate()` against a real DB (Testcontainers).

### SQLite limits to remember

SQLite is not a perfect SQL Server / PostgreSQL stand-in: different SQL dialect, type affinity, limited `ALTER TABLE`, no `decimal` precision the same way. A test that passes on SQLite can still behave differently on the production provider. For provider-specific behavior, use Testcontainers.

## Testcontainers — real database in a disposable container

Highest fidelity: spin up the actual provider image, run migrations, test real SQL. The only accurate way to test SQL Server / PostgreSQL specifics.

```csharp
// Packages: Testcontainers.MsSql (or Testcontainers.PostgreSql), Microsoft.EntityFrameworkCore.SqlServer
public sealed class SqlServerFixture : IAsyncLifetime
{
    private readonly MsSqlContainer _container = new MsSqlBuilder().Build();
    public string ConnectionString => _container.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        await using var ctx = CreateContext();
        await ctx.Database.MigrateAsync();        // run REAL migrations against a REAL engine
    }

    public ShopContext CreateContext() =>
        new(new DbContextOptionsBuilder<ShopContext>().UseSqlServer(ConnectionString).Options);

    public Task DisposeAsync() => _container.DisposeAsync().AsTask();
}
```

Share one container across a test class/collection (startup is slow), and reset data between tests rather than recreating the container.

## Respawn — fast reset between tests

Recreating schema per test is slow. `Respawn` deletes data (respecting FK order) without dropping tables, so each test starts clean against the same migrated DB.

```csharp
private Respawner _respawner = null!;

public async Task InitializeAsync()
{
    await using var conn = new SqlConnection(fixture.ConnectionString);
    await conn.OpenAsync();
    _respawner = await Respawner.CreateAsync(conn, new RespawnerOptions
    {
        DbAdapter = DbAdapter.SqlServer,
        TablesToIgnore = ["__EFMigrationsHistory"]   // never wipe migration history
    });
}

// before/after each test:
public async Task ResetAsync()
{
    await using var conn = new SqlConnection(fixture.ConnectionString);
    await conn.OpenAsync();
    await _respawner.ResetAsync(conn);
}
```

## Transaction-per-test (alternative isolation)

Instead of resetting, wrap each test in a transaction and roll back. Caveat: this won't catch issues that surface only on commit, and breaks if the code under test manages its own transactions.

```csharp
await using var ctx = fixture.CreateContext();
await using var tx = await ctx.Database.BeginTransactionAsync();
// ... arrange + act + assert ...
await tx.RollbackAsync();    // nothing persists; next test starts clean
```

## Testing concurrency tokens

Optimistic concurrency uses a token that changes on every write; a stale write throws `DbUpdateConcurrencyException`. Configure it, then test the conflict.

```csharp
// Modeling — pick ONE style:
public byte[] RowVersion { get; set; } = [];                  // SQL Server rowversion
// [Timestamp] public byte[] RowVersion { get; set; }         // annotation equivalent
// fluent: b.Property(x => x.RowVersion).IsRowVersion();
// generic token: b.Property(x => x.Version).IsConcurrencyToken();   // app-managed int/Guid
```

> `[Timestamp]` / `IsRowVersion()` maps to SQL Server `rowversion` (DB-generated, auto-incremented on update). SQLite has no `rowversion`; for SQLite use an app-managed `IsConcurrencyToken()` integer/GUID you bump yourself. PostgreSQL can use the system `xmin` column (`UseXminAsConcurrencyToken()`). This is why concurrency tests often need a real-DB (Testcontainers) run.

```csharp
[Fact]
public async Task Concurrent_update_throws()
{
    await using var ctx1 = fixture.CreateContext();
    await using var ctx2 = fixture.CreateContext();

    var a = await ctx1.Blogs.SingleAsync(b => b.Id == id);
    var b = await ctx2.Blogs.SingleAsync(x => x.Id == id);   // same row, both have the token value

    a.Name = "from ctx1";
    await ctx1.SaveChangesAsync();                            // bumps the token

    b.Name = "from ctx2";
    await Assert.ThrowsAsync<DbUpdateConcurrencyException>(() => ctx2.SaveChangesAsync());
}
```

Handle the exception in production by reloading (`entry.Reload()`) or merging, then retrying.

## EF Core through Aspire integration tests

If the app runs under .NET Aspire, integration-test it end-to-end with `Aspire.Hosting.Testing`: the test host starts the real dependencies (a containerized SQL Server / PostgreSQL the AppHost declares) and your service wired exactly as in production — including the EF `DbContext` registered by the Aspire client integration.

```csharp
// Package: Aspire.Hosting.Testing
var appHost = await DistributedApplicationTestingBuilder.CreateAsync<Projects.Shop_AppHost>();
await using var app = await appHost.BuildAsync();
await app.StartAsync();

var http = app.CreateHttpClient("api");
await app.ResourceNotifications.WaitForResourceHealthyAsync("api");

var response = await http.GetAsync("/blogs");          // hits the API, which hits the real DB via EF
response.EnsureSuccessStatusCode();
```

This validates the whole chain — connection-string injection, migrations/seeding, health checks — that unit-level EF tests can't. See the [`aspire`](../../aspire/SKILL.md) skill for AppHost test setup, applying migrations under Aspire, and waiting on resource health.

## Choosing — quick guidance

- Pure business logic, no DB behavior asserted → InMemory (or just mock the repository).
- Repository / query / constraint behavior, provider-agnostic → **SQLite in-memory** (open connection held).
- Provider-specific SQL, migrations, concurrency tokens, real types → **Testcontainers** with your production image; reset with **Respawn**.
- Full app wiring under Aspire → **Aspire.Hosting.Testing**.

## More info

- [Testing without your production database](https://learn.microsoft.com/ef/core/testing/testing-without-the-database)
- [Testing against a real database](https://learn.microsoft.com/ef/core/testing/testing-with-the-database)
- [Handling concurrency conflicts](https://learn.microsoft.com/ef/core/saving/concurrency)
- [Respawn](https://github.com/jbogard/Respawn) · [Testcontainers for .NET](https://dotnet.testcontainers.org/)
