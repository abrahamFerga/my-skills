# Modeling

Scope: how EF Core 10 builds the model — fluent API vs annotations, relationships, keys/indexes, owned vs complex types, JSON columns, value converters, conventions, and inheritance mapping. The model is built once on first use and cached, so this all runs in `OnModelCreating` (or convention/annotation equivalents).

## Fluent API vs data annotations

Both configure the same model. Pick a primary style and stay consistent.

| | Data annotations | Fluent API |
|--|------------------|-----------|
| Lives | On the entity class | In `OnModelCreating` / `IEntityTypeConfiguration<T>` |
| Power | Subset | Full surface (everything) |
| Coupling | Couples model class to EF | Keeps entities POCO-clean |
| Use for | Quick `[Required]`, `[MaxLength]`, `[Key]` | Relationships, indexes, converters, owned/complex/JSON, inheritance |

Rule of thumb: annotations for trivial single-property constraints if you like them; **fluent API for anything structural**. Fluent always wins on conflict.

### Split config into per-entity classes

Don't grow a 500-line `OnModelCreating`. Use one `IEntityTypeConfiguration<T>` per aggregate and discover them:

```csharp
public class BlogConfiguration : IEntityTypeConfiguration<Blog>
{
    public void Configure(EntityTypeBuilder<Blog> b)
    {
        b.ToTable("Blogs");
        b.HasKey(x => x.Id);
        b.Property(x => x.Name).HasMaxLength(200).IsRequired();
        b.Property(x => x.Rating).HasPrecision(5, 2);
        b.HasIndex(x => x.Name).IsUnique();
    }
}

protected override void OnModelCreating(ModelBuilder modelBuilder)
    => modelBuilder.ApplyConfigurationsFromAssembly(typeof(ShopContext).Assembly);
```

## Keys and indexes

```csharp
b.HasKey(x => x.Id);                                   // single PK (Id/<Type>Id by convention)
b.HasKey(x => new { x.TenantId, x.Code });             // composite key
b.HasAlternateKey(x => x.Email);                       // unique alternate key (target of FKs)
b.Property(x => x.Id).ValueGeneratedNever();           // app-assigned key (e.g. GUIDv7)
b.HasIndex(x => x.Slug).IsUnique();
b.HasIndex(x => new { x.TenantId, x.CreatedAt });      // composite index
b.HasIndex(x => x.Status).HasFilter("[Status] <> 0");  // filtered index (SQL Server)
b.HasIndex(x => x.Email).IncludeProperties(x => x.Name); // covering index
```

For `Guid` keys prefer sequential GUIDs (`Guid.CreateVersion7()` on .NET 9+) to avoid index fragmentation.

## Relationships

EF infers relationships from navigations + FK conventions; configure explicitly when it matters (delete behavior, FK property, required/optional).

### One-to-many

```csharp
b.HasMany(blog => blog.Posts)
 .WithOne(post => post.Blog)
 .HasForeignKey(post => post.BlogId)
 .OnDelete(DeleteBehavior.Cascade);     // Cascade | Restrict | SetNull | NoAction
```

A **nullable** FK (`int? BlogId`) makes the relationship optional; non-nullable makes it required (and forces a cascade-ish default). Choose `DeleteBehavior` deliberately — `Cascade` deletes children, `Restrict` blocks the delete, `SetNull` orphans them.

### One-to-one

```csharp
b.HasOne(u => u.Profile)
 .WithOne(p => p.User)
 .HasForeignKey<Profile>(p => p.UserId);  // FK must be specified — which side is dependent
```

### Many-to-many

EF auto-creates the join table (skip navigations). Configure it only to add payload columns or rename:

```csharp
b.HasMany(p => p.Tags).WithMany(t => t.Posts)
 .UsingEntity<PostTag>(                       // explicit join entity for payload
     j => j.HasOne(pt => pt.Tag).WithMany().HasForeignKey(pt => pt.TagId),
     j => j.HasOne(pt => pt.Post).WithMany().HasForeignKey(pt => pt.PostId),
     j => j.Property(pt => pt.AddedOn).HasDefaultValueSql("GETUTCDATE()"));
```

## Owned vs complex types — choose complex types for new code

Both let a child object map into the owner's table (table splitting) or a JSON column. They differ in semantics:

| | Owned entity (`OwnsOne`/`OwnsMany`) | Complex type (`ComplexProperty`) |
|--|-------------------------------------|----------------------------------|
| Identity | Yes (hidden key, reference semantics) | **No** — value semantics |
| Share instance across owners | ✗ (throws — same entity referenced twice) | ✓ (copies properties) |
| Compare in LINQ | By identity (surprising) | By value (expected) |
| `ExecuteUpdate` | ✗ | ✓ (EF10) |
| Collections | `OwnsMany` | Only when mapped to JSON (EF10); not via table splitting |
| Structs | ✗ | ✓ (EF10) |

**EF10 guidance:** prefer complex types for value objects (Address, Money). Migrate existing owned-for-value-object usage to complex types. Owned entities still make sense when you genuinely need a collection mapped via table splitting and can't use JSON.

### Complex type — table splitting (columns in the owner table)

```csharp
modelBuilder.Entity<Customer>(b =>
{
    b.ComplexProperty(c => c.ShippingAddress);     // → ShippingAddress_City, _Street, ...
    b.ComplexProperty(c => c.BillingAddress);
});
```

EF10 supports **optional** complex types (`Address? BillingAddress`) — but the type must have at least one required property.

```csharp
public struct Address                              // EF10: structs allowed (no collections of structs)
{
    public required string Street { get; set; }
    public required string City { get; set; }
    public required string ZipCode { get; set; }
}
```

### Complex type — JSON column

```csharp
modelBuilder.Entity<Customer>(b =>
{
    b.ComplexProperty(c => c.ShippingAddress, c => c.ToJson());   // → single JSON column
    b.ComplexProperty(c => c.BillingAddress, c => c.ToJson());
});
```

JSON-mapped complex types **can** contain collections, support LINQ over their inner properties, and (EF10) `ExecuteUpdate` into them. On SQL Server 2025 / Azure SQL these land in the native `json` type. See [ef-core-10.md](ef-core-10.md).

## JSON columns (owned-to-JSON, legacy form)

Pre-EF10 the JSON pattern used owned entities. It still works:

```csharp
modelBuilder.Entity<Order>().OwnsOne(o => o.Metadata, b => b.ToJson());
modelBuilder.Entity<Order>().OwnsMany(o => o.Lines, b => b.ToJson());  // collection in JSON
```

Query into JSON like normal properties; EF translates to `JSON_VALUE`/`OPENJSON` (provider-dependent):

```csharp
var hot = await db.Orders.Where(o => o.Metadata.Priority > 5).ToListAsync();
```

For new value-object modeling, prefer the **complex type** `ToJson()` form above.

## Value converters

Convert a CLR property to a different store type. Built-ins cover enums-as-strings, etc.; custom converters are a class or inline lambda pair.

```csharp
// Enum stored as its string name
b.Property(o => o.Status).HasConversion<string>().HasMaxLength(32);

// Custom: comma-joined list <-> string, with a value comparer for change tracking
var converter = new ValueConverter<List<string>, string>(
    v => string.Join(',', v),
    v => v.Split(',', StringSplitOptions.RemoveEmptyEntries).ToList());

var comparer = new ValueComparer<List<string>>(
    (a, c) => a!.SequenceEqual(c!),
    v => v.Aggregate(0, (h, s) => HashCode.Combine(h, s.GetHashCode())),
    v => v.ToList());

b.Property(e => e.Tags).HasConversion(converter, comparer);
```

> A **value comparer** is required for mutable reference-type converted properties (collections, arrays) so the change tracker detects mutations. Without it, edits may not be saved.

Strongly-typed IDs are a common converter use:

```csharp
public readonly record struct BlogId(int Value);
b.Property(x => x.Id).HasConversion(id => id.Value, v => new BlogId(v));
```

## Conventions and pre-convention model configuration

Set model-wide defaults in `ConfigureConventions` instead of repeating on every property:

```csharp
protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder)
{
    // Every string defaults to varchar(256) unless overridden
    configurationBuilder.Properties<string>().HaveMaxLength(256);

    // Apply a converter to every property of a type, everywhere
    configurationBuilder.Properties<DateOnly>().HaveConversion<DateOnlyConverter>();

    // Bulk-map a value object type
    configurationBuilder.ComplexProperties<Address>();
}
```

You can also write custom `IConvention` implementations for advanced model-building rules (e.g. apply a global filter or naming policy to all entities).

## Inheritance mapping (TPH / TPT / TPC)

| Strategy | Layout | Default? | Tradeoff |
|----------|--------|----------|----------|
| **TPH** Table-per-hierarchy | One table, a **discriminator** column, nullable subtype columns | Yes | Fastest queries, no joins; nullable columns for subtype props |
| **TPT** Table-per-type | Base table + one table per subtype, joined by PK | No | Normalized; queries join across tables (slower) |
| **TPC** Table-per-concrete-type | One table per concrete leaf, no base table | No | No joins, no nulls; duplicated columns, `UNION` for base queries |

```csharp
// TPH (default) — customize the discriminator
modelBuilder.Entity<Payment>()
    .HasDiscriminator<string>("PaymentType")
    .HasValue<CardPayment>("card")
    .HasValue<CashPayment>("cash");

// TPT
modelBuilder.Entity<CardPayment>().ToTable("CardPayments");
modelBuilder.Entity<CashPayment>().ToTable("CashPayments");

// TPC
modelBuilder.Entity<Payment>().UseTpcMappingStrategy();
```

Default to **TPH** unless you have a strong normalization or storage reason. TPC reads well for polymorphic queries when subtypes rarely change.

## Query filters (global filters)

Applied automatically to every query of an entity type — soft delete, multitenancy.

```csharp
modelBuilder.Entity<Blog>().HasQueryFilter(b => !b.IsDeleted);
```

EF10 adds **named** filters so you can have several and disable them individually — see [ef-core-10.md](ef-core-10.md). Disable for a single query with `IgnoreQueryFilters()`.

## More info

- [Creating and configuring a model](https://learn.microsoft.com/ef/core/modeling/)
- [Complex types](https://learn.microsoft.com/ef/core/modeling/complex-types)
- [Owned entity types](https://learn.microsoft.com/ef/core/modeling/owned-entities)
- [Value conversions](https://learn.microsoft.com/ef/core/modeling/value-conversions)
- [Inheritance](https://learn.microsoft.com/ef/core/modeling/inheritance)
