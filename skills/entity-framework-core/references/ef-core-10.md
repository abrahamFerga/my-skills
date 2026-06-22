# What Changed in EF Core 10 (and How to Use It)

Scope: the authoritative list of EF10 deltas with working code, plus upgrade notes. EF Core 10.0 shipped **November 2025** as an **LTS** release (supported to Nov 10, 2028). It **requires the .NET 10 SDK to build and the .NET 10 runtime to run** — it will not run on .NET 9 or earlier, nor on .NET Framework. Latest patch as of this writing: **10.0.9** (June 2026).

## Named query filters (multiple filters per entity, selectively disabled)

Pre-EF10, an entity could have only **one** global query filter, so combining soft-delete + multitenancy meant cramming both into one predicate and disabling them was all-or-nothing. EF10 lets you **name** filters and manage each independently.

```csharp
modelBuilder.Entity<Blog>()
    .HasQueryFilter("SoftDeletionFilter", b => !b.IsDeleted)
    .HasQueryFilter("TenantFilter", b => b.TenantId == tenantId);
```

Disable only one filter for a specific query:

```csharp
// keeps the tenant filter, drops only soft-delete
var allIncludingDeleted = await context.Blogs
    .IgnoreQueryFilters(["SoftDeletionFilter"])
    .ToListAsync();
```

`IgnoreQueryFilters()` with no argument still disables all filters. Unnamed `HasQueryFilter(...)` remains valid for the single-filter case.

## Vector search (Azure SQL / SQL Server 2025) — now GA

EF10 fully supports the SQL Server `vector` data type and `VECTOR_DISTANCE()` for embedding similarity search (semantic search, RAG). Requires **Azure SQL Database** or **SQL Server 2025**.

```csharp
public class Blog
{
    public int Id { get; set; }
    public required string Name { get; set; }

    [Column(TypeName = "vector(1536)")]            // dimensionality of your embedding model
    public SqlVector<float> Embedding { get; set; }
}
```

Insert via normal `SaveChanges`, populating the property from an `IEmbeddingGenerator`:

```csharp
var embedding = await embeddingGenerator.GenerateVectorAsync("Some text to be vectorized");
context.Blogs.Add(new Blog { Name = "Some blog", Embedding = new SqlVector<float>(embedding) });
await context.SaveChangesAsync();
```

Query by similarity with `EF.Functions.VectorDistance`:

```csharp
var sqlVector = new SqlVector<float>(await embeddingGenerator.GenerateVectorAsync(userQuery));
var topSimilar = await context.Blogs
    .OrderBy(b => EF.Functions.VectorDistance("cosine", b.Embedding, sqlVector))   // "cosine" | "euclidean" | "dot"
    .Take(3)
    .ToListAsync();
```

> **Cosmos vector search** uses *different* APIs: configure with `IsVectorProperty` / `IsVectorIndex` (renamed from EF9's experimental names) and query with `EF.Functions.VectorDistance` — now GA. Cosmos can generate containers with vector properties on owned *reference* entities; vectors on owned *collections* still must be created by other means but can be queried.

## SQL Server 2025 native `json` data type

SQL Server 2025 / Azure SQL add a real `json` column type (previously JSON lived in `nvarchar`). With `UseAzureSql` or compatibility level ≥ 170, EF10 **defaults JSON-mapped data to the native `json` type**, which is more efficient and enables the `modify()` function for in-place updates.

```csharp
modelBuilder.Entity<Blog>().ComplexProperty(b => b.Details, b => b.ToJson());
// Tags (string[]) and Details both land in `json` columns on SQL Server 2025
```

Querying inner properties translates to `JSON_VALUE(... RETURNING <type>)`:

```csharp
var hot = await context.Blogs.Where(b => b.Details.Viewers > 3).ToListAsync();
```

> **Migration impact:** existing JSON-in-`nvarchar` columns are **automatically converted to `json`** by the first migration after upgrading. Opt out by explicitly setting the column type to `nvarchar(max)` or using a compatibility level < 170.

## Complex type improvements (prefer complex types over owned entities)

EF10 makes complex types the recommended way to model value objects (table splitting or JSON). New in EF10:

- **Optional complex types**: `public Address? BillingAddress { get; set; }` (the type must still have ≥ 1 required property).
- **Map complex types to JSON**: `b.ComplexProperty(c => c.ShippingAddress, c => c.ToJson())` — and JSON-mapped complex types may contain **collections**.
- **Struct support**: complex types can be `struct`s (no collections of structs yet).
- **`ExecuteUpdate` into complex/JSON properties** (see below).

Why prefer complex types over owned entities for value objects: complex types have **value semantics** (no hidden identity), so you can assign one to another (`customer.BillingAddress = customer.ShippingAddress` works), compare by content in LINQ, and bulk-update them. Owned entities, being entities, fail all three. Migrate existing owned-for-value-object usage to complex types. See [modeling.md](modeling.md).

## `LeftJoin` and `RightJoin` LINQ operators

.NET 10 adds first-class `LeftJoin`/`RightJoin` LINQ methods; EF10 recognizes and translates them to `LEFT JOIN` / `RIGHT JOIN`. This replaces the old `SelectMany` + `GroupJoin` + `DefaultIfEmpty` incantation.

```csharp
var query = context.Students.LeftJoin(
    context.Departments,
    student => student.DepartmentID,
    department => department.ID,
    (student, department) => new
    {
        student.FirstName,
        student.LastName,
        Department = department.Name ?? "[NONE]"   // department null when unmatched
    });
```

`RightJoin` is analogous (keeps all of the second collection). Note: C# **query syntax** (`from ... select`) doesn't yet express left/right joins — use method syntax.

## `ExecuteUpdateAsync` accepts a regular (non-expression) lambda

Previously the setters argument was an `Expression<Func<...>>`, so building updates conditionally required hand-constructing expression trees. EF10 accepts a **normal lambda body**, so you can use ordinary control flow:

```csharp
await context.Blogs.ExecuteUpdateAsync(s =>
{
    s.SetProperty(b => b.Views, 8);
    if (nameChanged)
    {
        s.SetProperty(b => b.Name, "foo");   // ordinary `if`, no Expression.Lambda gymnastics
    }
});
```

## `ExecuteUpdate` over relational JSON columns

EF10 lets `ExecuteUpdateAsync` reference JSON columns and properties inside them — efficient bulk updates of document-modeled data. **Requires complex types mapped with `ToJson()`** (does not work with owned-entity JSON).

```csharp
modelBuilder.Entity<Blog>().ComplexProperty(b => b.Details, bd => bd.ToJson());

await context.Blogs.ExecuteUpdateAsync(s =>
    s.SetProperty(b => b.Details.Views, b => b.Details.Views + 1));
// SQL Server 2025: UPDATE ... SET [Details].modify('$.Views', JSON_VALUE(...) + 1)
```

## Improved parameterized-collection translation (default change)

`Where(b => ids.Contains(b.Id))` historically either inlined constants (plan-cache bloat) or used a single JSON-array parameter via `OPENJSON` (hid cardinality from the planner). **EF10's new default** translates each element to its **own scalar parameter** and pads the list to a bucketed length, balancing plan reuse against cardinality info:

```sql
WHERE [b].[Id] IN (@ids1, @ids2, @ids3 /*, padded to a bucket size */)
```

You can still control the strategy globally or per query:

```csharp
// global
o.UseSqlServer(cs, sql => sql.UseParameterizedCollectionMode(ParameterTranslationMode.Constant));
// per query: force inlining for this one
context.Users.Where(u => EF.Constant(ids).Contains(u.Role));
// per query: force a single parameter
context.Users.Where(u => EF.Parameter(ids).Contains(u.Role));
```

## More consistent ordering for split queries

Split queries previously could omit the key from a subquery's `ORDER BY`, risking non-deterministic / mismatched data across the separate queries. EF10 makes the ordering consistent across parent and child queries — a correctness fix, no API change. (Background in [querying-performance.md](querying-performance.md).)

## Cosmos: full-text & hybrid search, model evolution

- **Full-text search**: enable on a property and use the new functions.

  ```csharp
  b.Property(x => x.Contents).EnableFullTextSearch();
  b.HasIndex(x => x.Contents).IsFullTextIndex();
  // query:
  var hits = await context.Blogs.Where(x => EF.Functions.FullTextContains(x.Contents, "cosmos")).ToListAsync();
  ```
  Also: `FullTextContainsAll`, `FullTextContainsAny`, `FullTextScore`.
- **Hybrid search**: combine vector + full-text relevance with `EF.Functions.Rrf` (Reciprocal Rank Fusion):

  ```csharp
  await context.Blogs.OrderBy(x => EF.Functions.Rrf(
      EF.Functions.FullTextScore(x.Contents, "database"),
      EF.Functions.VectorDistance(x.Vector, myVector)))
      .Take(10).ToListAsync();
  ```
- **Model evolution**: adding a new *required* property no longer throws when materializing older documents that lack it — EF supplies a default.
- Cosmos query execution now uses the **execution strategy** (retries).

## Security improvements

- **Inlined constants redacted from logs by default**: values inlined into SQL (e.g. via `EF.Constant`) now log as `?` unless `EnableSensitiveDataLogging()` is set — prevents PII leaking into logs.
- **Raw-SQL concatenation analyzer**: a new analyzer warns when you concatenate into `FromSqlRaw`/`ExecuteSqlRaw`, flagging potential SQL injection. Suppress only when the input is trusted/sanitized; prefer interpolated `FromSql`/`ExecuteSql`.

## Other notable changes

- **Custom default-constraint names** on SQL Server: `HasDefaultValueSql("GETDATE()", "DF_Post_CreatedDate")`, or auto-name them all via `modelBuilder.UseNamedDefaultConstraints()` (next migration renames every default constraint).
- **Migrations no longer span all migrations in one transaction** — EF10 reverts the EF9 behavior; each migration applies in its own transaction (fixes operations that can't run inside a user transaction).
- **SQLite**: `AUTOINCREMENT` can be disabled and is supported for value-converted properties; `MIN`/`MAX`/`ORDER BY` over `decimal` now work.
- **New translations**: `DateOnly.ToDateTime()`, `DateOnly.DayNumber` (+ subtraction), `Microsecond`/`Nanosecond` date parts, `COALESCE`→`ISNULL` on SQL Server, some `char`-argument string functions.
- **Optimizations**: consecutive `LIMIT`s, `Count` on `ICollection<T>`, `MIN`/`MAX` over `DISTINCT`; simpler parameter names (`@city` instead of `@__city_0`).

## Upgrading from EF8/EF9 — checklist

1. **Move to `net10.0`** and install the .NET 10 SDK — EF10 will not run on older runtimes.
2. Bump all `Microsoft.EntityFrameworkCore.*` packages (and `dotnet-ef`) to `10.0.x`; bump Npgsql to `10.0.x`.
3. Read the [breaking changes](https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/breaking-changes) page — notably the SQLite `DateTime`/`DateTimeOffset`/UTC behavior fix, and the **JSON-`nvarchar`→`json` auto-conversion** migration on SQL Server 2025.
4. After upgrading, **add a migration and inspect it** before applying — package bumps can introduce model diffs (default-constraint naming, JSON type changes).
5. Consider migrating owned-entity value objects to **complex types**.
6. Re-check logs: inlined-constant redaction changes what appears; the raw-SQL analyzer may surface new warnings.

## More info

- [What's New in EF Core 10](https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/whatsnew)
- [Breaking changes in EF Core 10](https://learn.microsoft.com/ef/core/what-is-new/ef-core-10.0/breaking-changes)
- [SQL Server vector search](https://learn.microsoft.com/ef/core/providers/sql-server/vector-search)
- [Cosmos full-text search](https://learn.microsoft.com/ef/core/providers/cosmos/full-text-search)
- [Global query filters](https://learn.microsoft.com/ef/core/querying/filters)
