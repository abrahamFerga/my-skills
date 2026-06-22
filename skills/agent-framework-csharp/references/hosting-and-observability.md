# Hosting, DI, and Observability

How to move from a console sample to a production-ready hosted agent: DI registration, ASP.NET Core / Azure Functions hosting, durable agents, OpenTelemetry, retries, token budgeting, and session persistence.

## DI registration — three shapes

There are three ways to register an `AIAgent` in DI, depending on how much framework involvement you want.

### Shape A: Manual `ChatClientAgent` construction (most flexible)

```csharp
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.AI.OpenAI;
using Azure.Identity;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);

// Agent options as a singleton
builder.Services.AddSingleton(new ChatClientAgentOptions
{
    Name = "MyAgent",
    ChatOptions = new() { Instructions = "You are helpful." }
});

// Chat client — keyed so multiple providers can coexist
builder.Services.AddKeyedChatClient("AzureOpenAI", sp =>
    new AzureOpenAIClient(
        new Uri(Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT")!),
        new DefaultAzureCredential())
    .GetChatClient(Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT_NAME")!)
    .AsIChatClient());

// Agent built from DI
builder.Services.AddSingleton<AIAgent>(sp => new ChatClientAgent(
    chatClient: sp.GetRequiredKeyedService<IChatClient>("AzureOpenAI"),
    options: sp.GetRequiredService<ChatClientAgentOptions>()));

builder.Services.AddHostedService<MyService>();
await builder.Build().RunAsync();
```

Consume:
```csharp
internal sealed class MyService(AIAgent agent, IHostApplicationLifetime lifetime) : IHostedService
{
    private AgentSession? _session;
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        _session = await agent.CreateSessionAsync(cancellationToken);
        // ... loop, stream, etc.
    }
    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
```

### Shape B: `AddAIAgent` from `Microsoft.Agents.AI.Hosting`

```bash
dotnet add package Microsoft.Agents.AI.Hosting --prerelease
```

```csharp
using Microsoft.Agents.AI.Hosting;

builder.Services.AddChatClient(sp => /* IChatClient */);
builder.Services.AddAIAgent(
    name: "SearchAssistant",
    instructions: "You are a web-search expert.");
```

Resolve as a **keyed service** by name:

```csharp
public sealed class MyController(
    [FromKeyedServices("SearchAssistant")] AIAgent agent) { ... }
```

This shape:

- Pulls the `IChatClient` from DI automatically (use the `(name, instructions, chatClientServiceKey)` overload to bind a specific keyed chat client).
- Discovers any `AITool` registered as a keyed service with the same name and attaches them.
- Verifies that `agent.Name == name` and throws if not.

Register tools that should auto-bind to that agent:

```csharp
builder.Services.AddKeyedSingleton<AITool>("SearchAssistant",
    (sp, _) => AIFunctionFactory.Create(GetWeather));
```

### Shape C: Custom factory

When you need full control over construction (conditional middleware, custom decorators):

```csharp
builder.Services.AddAIAgent(
    name: "MyAgent",
    createAgentDelegate: (sp, key) =>
    {
        var chatClient = sp.GetRequiredService<IChatClient>();
        var agent = chatClient.AsAIAgent(name: key, instructions: "...");
        return agent
            .AsBuilder()
            .Use(MyLoggingMiddleware, null)
            .Build();
    });
```

> The factory **must** return an agent whose `Name` equals the registration key, or `AddAIAgent` throws.

## ASP.NET Core hosting

For a web-API-fronted agent:

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddChatClient(sp => /* IChatClient */);
builder.Services.AddAIAgent("ChatBot", "You are a helpful assistant.");

var app = builder.Build();

app.MapPost("/chat", async (
    [FromKeyedServices("ChatBot")] AIAgent agent,
    ChatRequest request,
    HttpContext http) =>
{
    AgentSession session = request.SessionId is not null
        ? await agent.DeserializeSessionAsync(LoadSession(request.SessionId))
        : await agent.CreateSessionAsync(http.RequestAborted);

    AgentResponse response = await agent.RunAsync(request.Message, session, http.RequestAborted);

    SaveSession(request.SessionId ?? Guid.NewGuid().ToString(),
        await agent.SerializeSessionAsync(session));

    return Results.Ok(response.Text);
});

app.Run();
```

For SSE streaming, return `IAsyncEnumerable<string>` from `agent.RunStreamingAsync(...)`. For richer streaming with tool calls / state / reasoning, expose the agent via **AGUI** (see [remote-agents.md](remote-agents.md)) — `app.MapAGUI(...)` does the SSE protocol for you.

## Azure Functions (durable agents)

`Microsoft.Agents.AI.Hosting.AzureFunctions` plus `ConfigureDurableAgents` auto-generates HTTP endpoints for invoking your agent. State persists in the underlying durable storage.

```bash
dotnet add package Microsoft.Agents.AI.Hosting.AzureFunctions --prerelease
```

```csharp
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Hosting.AzureFunctions;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Hosting;

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsAIAgent(instructions: "You are helpful.", name: "HostedAgent");

using IHost app = FunctionsApplication
    .CreateBuilder(args)
    .ConfigureFunctionsWebApplication()
    .ConfigureDurableAgents(options => options.AddAIAgent(agent, timeToLive: TimeSpan.FromHours(1)))
    .Build();

app.Run();
```

Generated endpoints include `POST /api/agents/HostedAgent/run` and durable session create/resume APIs. For multi-agent orchestration with durable replay (the workflow can pause for hours and resume), use `Microsoft.Agents.AI.DurableTask` orchestrations.

## OpenTelemetry

The agent pipeline emits OTel spans for every run, every tool call, and every chat-client request. Wire it once at startup.

```bash
dotnet add package OpenTelemetry
dotnet add package OpenTelemetry.Exporter.Console
dotnet add package Azure.Monitor.OpenTelemetry.Exporter
```

```csharp
using OpenTelemetry;
using OpenTelemetry.Trace;
using Azure.Monitor.OpenTelemetry.Exporter;

string sourceName = Guid.NewGuid().ToString("N");
var tracerProviderBuilder = Sdk.CreateTracerProviderBuilder()
    .AddSource(sourceName)
    .AddSource("Microsoft.Agents.AI.*")        // agent runs, sessions
    .AddSource("Microsoft.Agents.AI.Workflows.*")  // workflows
    .AddSource("Microsoft.Extensions.AI.*")    // chat client + function invocation
    .AddConsoleExporter();

if (!string.IsNullOrWhiteSpace(appInsightsConnString))
{
    tracerProviderBuilder.AddAzureMonitorTraceExporter(o => o.ConnectionString = appInsightsConnString);
}

using var tracerProvider = tracerProviderBuilder.Build();

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsAIAgent(instructions: "...", name: "Joker")
    .AsBuilder()
    .UseOpenTelemetry(sourceName: sourceName)
    .Build();
```

### What gets traced

- `AIAgent.RunAsync` / `RunStreamingAsync` — one span per run
- Each LLM call within the run (one span per chat-client invocation)
- Each tool invocation (function name, duration, success/failure)
- Workflow executors — each as its own span when workflows are OT-enabled (`.WithOpenTelemetry(...)`)

### Logging rules

- **Never log `message.Content`, tool results, or `response.Text`.** They may contain PII, secrets, or model-generated content. Log metadata only.
- Disable content capture on OTel exporters in production (otherwise prompts and responses end up in your APM verbatim). The `EnableSensitiveData` flag on `UseOpenTelemetry` / `WithOpenTelemetry` defaults to off — keep it off in prod.
- Log `response.Usage?.TotalTokenCount` and aggregate per session for cost monitoring.
- Use **structured logging** (`logger.LogInformation("Agent step: {Role}, {Length}", role, length)`) — never string concatenation.

## Token budgeting

Count tokens client-side **before** sending each request with `Microsoft.ML.Tokenizers`:

```bash
dotnet add package Microsoft.ML.Tokenizers
```

```csharp
using Microsoft.ML.Tokenizers;

var tokenizer = TiktokenTokenizer.CreateForModel("gpt-4o-2024-08-06");
int promptTokens = tokenizer.CountTokens(prompt);
if (sessionUsedTokens + promptTokens > sessionBudget)
{
    throw new InvalidOperationException("Session token budget exceeded.");
}
```

Combine with `ChatOptions.MaxOutputTokens` to bound completion size, and `UseChatReduction` middleware to summarize old history when the session grows.

## Resilience and retries

Use `Microsoft.Extensions.Http.Resilience` on the HttpClient powering the provider SDK:

```bash
dotnet add package Microsoft.Extensions.Http.Resilience
```

```csharp
builder.Services
    .AddHttpClient("OpenAI")
    .AddStandardResilienceHandler();    // retries, timeouts, circuit breaker
```

For chat-client-level retry, decorate the chat client:

```csharp
builder.Services.AddChatClient(sp =>
    new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
        .GetChatClient(deploymentName)
        .AsIChatClient()
        .AsBuilder()
        .UseLogging()
        .Build());     // add a retry decorator inside as needed
```

Don't hand-roll `try/catch` retry loops — they swallow cancellation tokens and lose telemetry context.

## Persisting sessions across requests

Sessions serialize to JSON. Store the JSON in any persistent store keyed by user/conversation id.

```csharp
// Save
JsonElement state = await agent.SerializeSessionAsync(session);
await sessionStore.SetAsync(conversationId, state.GetRawText());

// Load
string raw = await sessionStore.GetAsync(conversationId);
AgentSession session = await agent.DeserializeSessionAsync(
    JsonDocument.Parse(raw).RootElement);
```

Persist after every successful `RunAsync` to survive process restarts. For server-managed history (Azure OpenAI Responses with `store: true`), the session's `ConversationId` is enough — you don't need to serialize the message body. For Cosmos-backed persistence built into the framework, use `CosmosChatHistoryProvider` (see [memory.md](memory.md)).

## Multi-tenant / multi-user setups

- Register **one chat client** keyed by tenant / provider.
- Register **one agent** per logical role (`AddAIAgent("Assistant", ...)`, `AddAIAgent("Reviewer", ...)`).
- Scope `AgentSession`s per (user, agent) pair.
- Use `[FromKeyedServices("AgentName")]` in controllers/handlers to inject the right one.

For per-user state in `AIContextProvider`s, read the user identity from `HttpContext` / `ClaimsPrincipal` in the provider factory and partition the storage by user id — see [memory.md](memory.md).

## Production checklist

- [ ] Agent registered in DI — not constructed per-request
- [ ] `IChatClient` is keyed if multiple providers are in use
- [ ] `ManagedIdentityCredential` (not `DefaultAzureCredential`) in production Azure
- [ ] API keys / endpoints loaded from env vars / Key Vault — never hardcoded
- [ ] Model id is a dated version (`gpt-4o-2024-08-06`), not a floating alias
- [ ] `ChatOptions.Temperature` and `MaxOutputTokens` set explicitly
- [ ] OpenTelemetry source registered and exported; `EnableSensitiveData` is off
- [ ] Standard resilience handler on the provider's HttpClient
- [ ] Token budget enforced per session
- [ ] Sessions serialized and persisted between requests
- [ ] Side-effecting tools wrapped in `ApprovalRequiredAIFunction`
- [ ] Tool descriptions audited — no vague `[Description("does stuff")]`
- [ ] Logs do **not** include raw message contents
- [ ] Workflows have `MaximumIterationCount` / hop caps
- [ ] Health check exposes a liveness endpoint that does **not** call the LLM

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Singleton agent depending on per-request services (e.g., scoped `HttpContext`) | Resolve the dependency inside a per-request middleware / context provider, not in the agent constructor |
| Agent re-created on every HTTP request | Use `AddAIAgent` (singleton by default). Constructing in the request handler discards state and warms the SDK each call. |
| Concurrent calls share an `AgentSession` | Sessions are per-conversation. Concurrent requests from the same user need separate sessions or serialized turns. |
| OTel produces no spans | The `sourceName` passed to `UseOpenTelemetry` must match an `AddSource` on the tracer provider |
| App Insights / OTel exports raw prompts | Set `EnableSensitiveData = false` on `UseOpenTelemetry` / `WithOpenTelemetry`; otherwise prompts and responses are stored verbatim |
| `AddAIAgent` throws on resolution | Factory's agent name didn't match the registration key, or no `IChatClient` is registered |
| Azure Functions agent loses state between invocations | Verify `ConfigureDurableAgents` is wired and a backing storage (Azure Storage / Cosmos) is configured |
| Memory grows unbounded | Long sessions accumulate messages — add `UseChatReduction` middleware or cap session length |
| Hand-rolled retry loop swallows cancellation | Use `AddStandardResilienceHandler` or a properly cancellation-aware decorator |
