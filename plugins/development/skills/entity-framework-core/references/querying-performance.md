# Querying & Performance

Scope: writing efficient EF Core 10 queries and diagnosing slow ones — projections, loading strategies, the N+1 problem, single vs split queries, tracking modes, compiled queries, pagination, bulk `ExecuteUpdate`/`ExecuteDelete`, raw SQL, and how to see the generated SQL. The golden rule: **fetch only the rows and columns you need, in as few round trips as possible, without tracking what you won't change.**

## Projections — select only what you need

Don't materialize whole entities to read two fields. Project into a DTO/record; EF emits a narrower `SELECT` and skips tracking.

```csharp
var rows = await db.Posts
    .Where(p => p.BlogId == id)
    .Select(p => new PostListItem(p.Id, p.Title, p.Blog.Name, p.Comments.Count))  // joins/aggregates translated
    .ToListAsync();
```

A projection that doesn't return a full entity is **automatically non-tracking**. Prefer projections for all read/display paths.

## Tracking modes

| Mode | Behavior | Use for |
|------|----------|---------|
| Tracking (default) | Snapshots entities for change detection | Anything you'll `SaveChanges()` |
| `AsNoTracking()` | No snapshots, faster, less memory | Read-only queries returning entities |
| `AsNoTrackingWithIdentityResolution()` | No tracking but de-dupes identical instances | Read-only graphs with repeated entities (avoids duplicate object instances) |

Set a context-wide default for read-heavy services:

```csharp
options.UseSqlServer(cs).UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
// then opt back in per-query when you need to save: db.Blogs.AsTracking()...
```

## Loading related data

### Eager loading (`Include`) — the default answer to N+1

```csharp
var blogs = await db.Blogs
    .Include(b => b.Posts).ThenInclude(p => p.Comments)
    .Include(b => b.Owner)
    .ToListAsync();

// Filtered include (EF5+): only load some children
var blogs2 = await db.Blogs
    .Include(b => b.Posts.Where(p => !p.IsDraft).OrderByDescending(p => p.CreatedAt).Take(5))
    .ToListAsync();
```

### Explicit loading

```csharp
var blog = await db.Blogs.FindAsync(id);
await db.Entry(blog!).Collection(b => b.Posts).LoadAsync();
await db.Entry(blog!).Reference(b => b.Owner).LoadAsync();
```

### Lazy loading — avoid by default

Lazy loading (proxies) silently triggers a query whenever a navigation is touched → hidden N+1, and serialization loops. Don't enable it project-wide. Load explicitly with `Include`/`Load`.

## The N+1 problem

The classic anti-pattern: one query for the list, then one more **per item** for a navigation.

```csharp
// ❌ N+1: 1 query for blogs + 1 per blog for Posts.Count (or, with lazy loading, per access)
var blogs = await db.Blogs.ToListAsync();
foreach (var b in blogs)
    Console.WriteLine($"{b.Name}: {b.Posts.Count}");   // each Posts access = a query

// ✅ project the count into the query — single round trip
var rows = await db.Blogs
    .Select(b => new { b.Name, PostCount = b.Posts.Count })
    .ToListAsync();

// ✅ or eager-load if you need the entities
var blogs2 = await db.Blogs.Include(b => b.Posts).ToListAsync();
```

Detect N+1 by logging SQL (below) and watching for the same query shape firing repeatedly.

## Single vs split queries (cartesian explosion)

`Include`-ing **multiple collections** in one SQL query produces a cartesian product — rows multiply (Posts × Comments × Tags), inflating data transfer dramatically. `AsSplitQuery()` issues one SQL query per collection instead.

```csharp
var blogs = await db.Blogs
    .Include(b => b.Posts)
    .Include(b => b.Contributors)
    .AsSplitQuery()                 // separate query per collection — no explosion
    .ToListAsync();
```

```csharp
// Or make split the default and opt single per query with AsSingleQuery()
options.UseSqlServer(cs, o => o.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery));
```

Tradeoff: split queries run multiple round trips and, without a transaction, can see data change between them. **EF10 fixed split-query ordering consistency** so child queries order identically to the parent (prevents subtle wrong-data bugs) — see [ef-core-10.md](ef-core-10.md). Use single query for one collection + many references; split when you `Include` several collections.

## Pagination

```csharp
// Offset pagination — simple, but slow for deep pages (DB scans + skips)
var page = await db.Posts.OrderBy(p => p.Id)
    .Skip(pageIndex * pageSize).Take(pageSize).ToListAsync();

// Keyset (seek) pagination — scales to deep pages; pass the last-seen key
var page2 = await db.Posts.OrderBy(p => p.Id)
    .Where(p => p.Id > lastSeenId).Take(pageSize).ToListAsync();
```

Always `OrderBy` a unique/stable key before paginating, or results are non-deterministic.

## Bulk updates/deletes — `ExecuteUpdate` / `ExecuteDelete`

Set-based writes that run as a **single SQL statement**, with **no entity materialization and no change tracking**. EF7+; EF10 broadens them (non-expression lambda bodies, JSON/complex-type targets) — see [ef-core-10.md](ef-core-10.md).

```csharp
// One UPDATE statement, no entities loaded
await db.Posts.Where(p => p.CreatedAt < cutoff)
    .ExecuteUpdateAsync(s => s
        .SetProperty(p => p.IsArchived, true)
        .SetProperty(p => p.Title, p => p.Title + " (archived)"));

// One DELETE statement
await db.Posts.Where(p => p.IsSpam).ExecuteDeleteAsync();
```

Caveats: they bypass the change tracker (already-tracked entities go stale — re-query or use a fresh context), don't fire `SaveChanges` interceptors/auditing, and don't run validation. Perfect for bulk maintenance; not a replacement for tracked aggregate updates that need domain logic.

## Compiled queries

For very hot queries, pre-compile to skip LINQ-expression translation each call:

```csharp
private static readonly Func<ShopContext, int, Task<Blog?>> _byId =
    EF.CompileAsyncQuery((ShopContext ctx, int id) =>
        ctx.Blogs.FirstOrDefault(b => b.Id == id));

var blog = await _byId(db, 42);
```

Measure first — EF already caches query plans internally; compiled queries help only on genuinely hot paths.

## Raw SQL when LINQ can't express it

```csharp
// Parameterized & composable; tracked entities back
var blogs = await db.Blogs
    .FromSql($"SELECT * FROM Blogs WHERE Rating > {minRating}")   // FormattableString → safe params
    .Where(b => b.IsActive)                                       // still composable in LINQ
    .ToListAsync();

// Scalar / non-entity
await db.Database.ExecuteSqlAsync($"EXEC RefreshStats {tenantId}");
```

Use `FromSql` (interpolated, auto-parameterized) — **never** `FromSqlRaw` with string concatenation of user input. EF10 ships an analyzer that warns on concatenation inside raw-SQL calls (see [ef-core-10.md](ef-core-10.md)).

## Batching writes

`SaveChanges` already batches multiple INSERT/UPDATE/DELETE into few round trips. The anti-pattern is calling `SaveChanges` **inside** a loop:

```csharp
// ❌ one round trip per row
foreach (var p in posts) { db.Add(p); await db.SaveChangesAsync(); }

// ✅ add all, save once (EF batches)
db.AddRange(posts);
await db.SaveChangesAsync();
```

## Async, cancellation, and streaming

Use the `...Async` methods on real DB providers and pass `CancellationToken`. For large result sets, stream instead of buffering:

```csharp
await foreach (var post in db.Posts.AsAsyncEnumerable().WithCancellation(ct))
    Process(post);     // no full ToListAsync() buffer
```

## Client evaluation

EF translates `Where`/`OrderBy`/aggregates to SQL. If a top-level predicate can't translate, EF **throws** (it won't silently pull the table into memory) — fix the expression or push it to the DB. Watch projections: the final `Select` may legitimately run a bit of C# client-side, but a `.Where(b => MyCustomMethod(b))` won't translate. Don't "fix" it with an early `AsEnumerable()` that drags the whole table client-side.

## Seeing the generated SQL

```csharp
// Log SQL during dev (sensitive data only in non-prod!)
options.UseSqlServer(cs)
    .LogTo(Console.WriteLine, LogLevel.Information)
    .EnableSensitiveDataLogging();      // shows parameter values — DEV ONLY

// Or inspect a single query without executing
var sql = db.Blogs.Where(b => b.Rating > 4).ToQueryString();
```

EF10 redacts inlined constants in logs by default (`?` placeholders) unless `EnableSensitiveDataLogging` is on — see [ef-core-10.md](ef-core-10.md).

## Quick perf checklist

- [ ] Read paths: `AsNoTracking` or project to a DTO
- [ ] No `foreach` touching a lazy/un-included navigation (N+1)
- [ ] Multiple collection `Include`s → `AsSplitQuery`
- [ ] Pagination has a stable `OrderBy`; deep pages use keyset
- [ ] Bulk maintenance via `ExecuteUpdate`/`ExecuteDelete`, not load-then-loop
- [ ] No `SaveChanges` inside loops
- [ ] Verified the SQL with `ToQueryString()`/`LogTo`

## More info

- [Efficient querying](https://learn.microsoft.com/ef/core/performance/efficient-querying)
- [Loading related data](https://learn.microsoft.com/ef/core/querying/related-data/)
- [Single vs. split queries](https://learn.microsoft.com/ef/core/querying/single-split-queries)
- [ExecuteUpdate / ExecuteDelete](https://learn.microsoft.com/ef/core/saving/execute-insert-update-delete)
- [Tracking vs. no-tracking](https://learn.microsoft.com/ef/core/querying/tracking)
