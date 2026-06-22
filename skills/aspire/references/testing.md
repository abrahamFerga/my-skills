# Aspire — integration testing

Scope: spinning up the real resource graph in tests with `Aspire.Hosting.Testing`
and `DistributedApplicationTestingBuilder`. For the app model itself see
[app-model.md](app-model.md).

## What it gives you

`Aspire.Hosting.Testing` lets a test start your **actual AppHost** — projects plus
containerized backing resources — wait for them to become healthy, and then call
them over real HTTP. It's end-to-end integration testing of the orchestrated
system, not unit testing.

> A container runtime (Docker/Podman) must be available on the test machine/CI
> runner, since the backing resources run as containers.

## Setup

Test project references:

```xml
<PackageReference Include="Aspire.Hosting.Testing" Version="13.4.*" />
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
<PackageReference Include="xunit.v3" Version="1.*" />
<PackageReference Include="xunit.runner.visualstudio" Version="3.*" />
```

The test project also needs an `<IsAspireProjectResource>` reference (or a normal
project reference) to the **AppHost** so `Projects.AppHost` is generated.

## The basic test

```csharp
public class ApiTests
{
    [Fact]
    public async Task Health_endpoint_returns_ok()
    {
        var appHost = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.AppHost>();

        // Add test-only resilience so transient startup races don't flake.
        appHost.Services.ConfigureHttpClientDefaults(http =>
            http.AddStandardResilienceHandler());

        await using var app = await appHost.BuildAsync();
        await app.StartAsync();

        // Wait until the resource is actually serving — not just started.
        await app.ResourceNotificationService
            .WaitForResourceAsync("api", KnownResourceStates.Running)
            .WaitAsync(TimeSpan.FromSeconds(60));

        var http = app.CreateHttpClient("api");
        var response = await http.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }
}
```

`CreateHttpClient("api")` resolves the resource's endpoint and pre-wires service
discovery, so you address services by their app-model name.

## Waiting on resources

| Helper | Use |
|--------|-----|
| `WaitForResourceAsync(name, KnownResourceStates.Running)` | Resource process/container is up. |
| `WaitForResourceHealthyAsync(name)` | Resource passed its health checks (preferred for DB-backed APIs). |
| `.WaitAsync(timeout)` | Always bound the wait so a hung resource fails fast instead of stalling CI. |

## Sharing one app across many tests

Starting the full graph per test is slow. Use an `IAsyncLifetime` fixture so the
app starts once for the class/collection:

```csharp
public sealed class AppFixture : IAsyncLifetime
{
    public DistributedApplication App { get; private set; } = default!;

    public async ValueTask InitializeAsync()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.AppHost>();
        App = await builder.BuildAsync();
        await App.StartAsync();
        await App.ResourceNotificationService
            .WaitForResourceHealthyAsync("api")
            .WaitAsync(TimeSpan.FromSeconds(120));
    }

    public async ValueTask DisposeAsync() => await App.DisposeAsync();
}

public class OrdersTests(AppFixture fixture) : IClassFixture<AppFixture>
{
    [Fact]
    public async Task Can_create_order()
    {
        var client = fixture.App.CreateHttpClient("api");
        var resp = await client.PostAsJsonAsync("/orders", new { sku = "ABC", qty = 2 });
        resp.EnsureSuccessStatusCode();
    }
}
```

## Tuning the app under test

```csharp
var builder = await DistributedApplicationTestingBuilder.CreateAsync<Projects.AppHost>(
    args: ["--no-dashboard"]);   // skip the dashboard in CI

// Override config / connection values for the test run:
builder.Configuration["Parameters:db-password"] = "test-only-password";
```

You can also resolve a connection string from a started app to talk to the database
directly (e.g. to seed data) via
`await app.GetConnectionStringAsync("appdb")`.

## Database seeding

Two common approaches:

- **Through the API** — exercise real endpoints to create the data you assert on
  (highest fidelity).
- **Direct provider access** — pull the connection string with
  `GetConnectionStringAsync(...)` and seed with EF Core / a raw client before the
  assertion. For EF Core seeding/migration-in-tests patterns see
  [the EF Core testing reference](../../entity-framework-core/references/testing.md).

## CI notes

- The runner needs Docker; on GitHub-hosted Linux runners it's preinstalled.
- First run pulls images — cache them or accept the cold-start cost; bound every
  `WaitFor*` with a timeout so a missing image fails the job instead of hanging.
- Run these as a separate, slower test stage from fast unit tests.

## Pitfalls

| Pitfall | Fix |
|---------|-----|
| Test calls the API before it's ready | `WaitForResourceHealthyAsync` (not just `Running`) with a timeout. |
| Flaky first request | Add `AddStandardResilienceHandler()` to the test HTTP client. |
| Full graph restarts every test → slow | Share one app via an `IClassFixture`/collection fixture. |
| No container runtime on the runner | Use a runner with Docker, or skip Aspire integration tests there. |
| Dashboard noise/port conflicts in CI | Pass `--no-dashboard`. |
