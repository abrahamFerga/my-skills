# Memory: Context Providers, History, and Scopes

MAF has **three distinct memory mechanisms**. Pick the right one — they layer rather than substitute.

| Mechanism | Purpose | Storage |
|-----------|---------|---------|
| **`AIContextProvider`** | Inject extra instructions / messages / tools per run; can extract memories from messages and recall them later | Implementation choice (in-memory, vector store, Foundry, custom) |
| **`MessageAIContextProvider`** | Thinner abstraction for providers that only inject **messages** (no instructions or tools) | Implementation choice |
| **`ChatHistoryProvider`** | Persist & restore the full conversation message log (separate from selective memories) | Implementation choice (in-memory, Cosmos DB, custom) |

You can use multiple `AIContextProvider`s **plus** one `ChatHistoryProvider` on the same agent. They run in this order on each call:

1. `ChatHistoryProvider.ProvideChatHistoryAsync` — load prior messages
2. All `AIContextProvider.ProvideAIContextAsync` — inject instructions / messages / tools (run in registration order; later providers see earlier output)
3. The agent calls the LLM
4. `AIContextProvider.StoreAIContextAsync` for each provider — store extracted memories / state
5. `ChatHistoryProvider.StoreChatHistoryAsync` — persist the new turn

## `AIContextProvider` — base API

`AIContextProvider` is in `Microsoft.Agents.AI.Abstractions` (stable). Subclass it to write custom memory.

```csharp
public abstract class AIContextProvider
{
    public virtual IReadOnlyList<string> StateKeys => [GetType().Name];

    protected virtual ValueTask<AIContext> ProvideAIContextAsync(
        InvokingContext context, CancellationToken cancellationToken = default);

    protected virtual ValueTask StoreAIContextAsync(
        InvokedContext context, CancellationToken cancellationToken = default);

    public virtual object? GetService(Type serviceType, object? serviceKey = null);
}

public sealed class AIContext
{
    public string? Instructions { get; set; }
    public IEnumerable<ChatMessage>? Messages { get; set; }
    public IEnumerable<AITool>? Tools { get; set; }
}
```

**Security note:** Data returned from a context provider is merged into the prompt as-is. If the provider reads from a vector store, memory service, or external API, a compromised source can deliver adversarial content (indirect prompt injection). Validate, sanitize, and length-limit provider output.

## Custom memory: per-session example

The canonical pattern — extract structured facts during `StoreAIContextAsync` and inject them on the next `ProvideAIContextAsync`.

```csharp
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;

internal sealed class UserInfoMemory : AIContextProvider
{
    private readonly ProviderSessionState<UserInfo> _state;
    private readonly IChatClient _chatClient;

    public UserInfoMemory(IChatClient chatClient)
    {
        _state = new ProviderSessionState<UserInfo>(
            stateInitializer: _ => new UserInfo(),
            stateKey: GetType().Name);
        _chatClient = chatClient;
    }

    public override IReadOnlyList<string> StateKeys => [_state.StateKey];

    public UserInfo GetUserInfo(AgentSession session)
        => _state.GetOrInitializeState(session);

    protected override async ValueTask StoreAIContextAsync(
        InvokedContext context, CancellationToken cancellationToken = default)
    {
        var info = _state.GetOrInitializeState(context.Session);
        if (info.UserName is null && context.RequestMessages.Any(m => m.Role == ChatRole.User))
        {
            var result = await _chatClient.GetResponseAsync<UserInfo>(
                context.RequestMessages,
                new ChatOptions { Instructions = "Extract user's name and age if present, else null." },
                cancellationToken: cancellationToken);
            info.UserName ??= result.Result.UserName;
            info.UserAge ??= result.Result.UserAge;
        }
        _state.SaveState(context.Session, info);
    }

    protected override ValueTask<AIContext> ProvideAIContextAsync(
        InvokingContext context, CancellationToken cancellationToken = default)
    {
        var info = _state.GetOrInitializeState(context.Session);
        return new(new AIContext
        {
            Instructions = info.UserName is null
                ? "Politely ask the user their name."
                : $"The user's name is {info.UserName}, age {info.UserAge?.ToString() ?? "unknown"}."
        });
    }
}

public sealed class UserInfo { public string? UserName { get; set; } public int? UserAge { get; set; } }

// Wire it up:
AIAgent agent = chatClient.AsAIAgent(new ChatClientAgentOptions
{
    ChatOptions = new() { Instructions = "You are friendly." },
    AIContextProviders = [new UserInfoMemory(chatClient.AsIChatClient())]
});
```

## `ProviderSessionState<T>` — session-scoped state with serialization

Stores per-session state in the agent's `AgentSession.StateBag`. State is JSON-serialized and round-trips through `SerializeSessionAsync` / `DeserializeSessionAsync` — survives process restarts.

```csharp
public class ProviderSessionState<TState> where TState : class
{
    public ProviderSessionState(
        Func<AgentSession?, TState> stateInitializer,
        string stateKey,
        JsonSerializerOptions? jsonSerializerOptions = null);

    public string StateKey { get; }
    public TState GetOrInitializeState(AgentSession? session);
    public void SaveState(AgentSession? session, TState state);
}
```

Scope:
- **Per-session by default.** Each `AgentSession` has independent state.
- **Cross-session / user-scoped:** make the `stateInitializer` read a user id from outside the session (request context, auth claims, etc.) and load shared state from a backing store.

## `MessageAIContextProvider` — simpler shape

When the provider only needs to inject **messages** (no instructions or tools), `MessageAIContextProvider` is the thinner base. Wire via `UseAIContextProviders(...)` on `AIAgentBuilder` and it applies even to non-`ChatClientAgent` agents.

```csharp
internal sealed class DateTimeContextProvider : MessageAIContextProvider
{
    protected override ValueTask<IEnumerable<ChatMessage>> ProvideMessagesAsync(
        InvokingContext context, CancellationToken cancellationToken = default)
        => new([new ChatMessage(ChatRole.User,
            $"For reference, the current date and time is: {DateTimeOffset.Now}")]);
}

AIAgent agent = baseAgent
    .AsBuilder()
    .UseAIContextProviders(new DateTimeContextProvider())
    .Build();
```

Multiple providers compose; each receives the output of the previous.

## `FoundryMemoryProvider` — Azure AI Foundry memory store

Microsoft-managed, vector-search-backed memory. Lives in `Microsoft.Agents.AI.Foundry` (stable).

```csharp
using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Foundry;

DefaultAzureCredential credential = new();
AIProjectClient projectClient = new(new Uri(foundryEndpoint), credential);

FoundryMemoryProvider memoryProvider = new(
    projectClient,
    memoryStoreName,
    stateInitializer: _ => new(new FoundryMemoryProviderScope("sample-user-123")));

ChatClientAgent agent = projectClient.AsAIAgent(new ChatClientAgentOptions
{
    Name = "TravelAssistant",
    ChatOptions = new() { ModelId = deploymentName, Instructions = "..." },
    AIContextProviders = [memoryProvider]
});

// One-time setup
await memoryProvider.EnsureMemoryStoreCreatedAsync(
    deploymentName,
    embeddingModelName,
    description: "Travel-assistant memories");

// Per-conversation cleanup (optional)
await memoryProvider.EnsureStoredMemoriesDeletedAsync(session);

// IMPORTANT: extraction is async — poll for completion before querying derived facts
await memoryProvider.WhenUpdatesCompletedAsync();
```

**Foundry-specific gotcha:** Memory extraction is asynchronous on the service. After turns that introduce new facts, call `await memoryProvider.WhenUpdatesCompletedAsync()` before relying on the next turn to recall them. The sample (`AgentWithMemory_Step04_MemoryUsingFoundry`) shows the polling pattern.

**Scope:** `FoundryMemoryProviderScope(string)` is a single string-keyed scope. Use a user id, tenant id, or a synthetic session-scoped id depending on whether you want cross-session recall.

## Persisted chat history — `ChatHistoryProvider`

`ChatHistoryProvider` (in `Microsoft.Agents.AI`) is for **full conversation persistence**. Use it when:

- The underlying LLM service doesn't store history (most non-Responses-API providers)
- You need to replay full message logs across processes
- You want a queryable record of conversations

```csharp
public abstract class ChatHistoryProvider
{
    public virtual IReadOnlyList<string> StateKeys => [GetType().Name];

    protected virtual ValueTask<IEnumerable<ChatMessage>> ProvideChatHistoryAsync(
        InvokingContext context, CancellationToken cancellationToken = default);

    protected virtual ValueTask StoreChatHistoryAsync(
        InvokedContext context, CancellationToken cancellationToken = default);
}
```

Wire via `ChatClientAgentOptions.ChatHistoryProvider`.

### Cosmos DB chat history

`Microsoft.Agents.AI.CosmosNoSql` (prerelease) provides `CosmosChatHistoryProvider` — Cosmos-backed persistence with TTL, partitioning, and transactional batches.

```bash
dotnet add package Microsoft.Agents.AI.CosmosNoSql --prerelease
```

```csharp
using Microsoft.Agents.AI.CosmosNoSql;

var cosmosProvider = new CosmosChatHistoryProvider(/* Cosmos client + container + options */);

AIAgent agent = chatClient.AsAIAgent(new ChatClientAgentOptions
{
    ChatOptions = new() { Instructions = "..." },
    ChatHistoryProvider = cosmosProvider
});
```

Configuration supports:
- Partition by `ConversationId` (simple) or `(TenantId, UserId, ConversationId)` (hierarchical)
- TTL-based auto-expiry
- Max-messages cap on retrieval

## Cross-session memory patterns

To make a user remember things across **all** their sessions, scope state by user id rather than by session.

### Pattern 1: Foundry with user-scoped scope

```csharp
new FoundryMemoryProvider(
    projectClient,
    memoryStoreName,
    stateInitializer: session => new(new FoundryMemoryProviderScope(
        GetUserIdFromAuthContext())))
```

All sessions sharing the same user id share the memory store partition.

### Pattern 2: Custom `AIContextProvider` with external store

In your provider's constructor / initializer, read the user id and load their shared state from a database. Each session still gets its own `ProviderSessionState`, but the *content* is loaded from / saved to a per-user backing store.

### Pattern 3: `ChatHistoryProvider` per conversation, memory provider per user

```csharp
AIAgent agent = chatClient.AsAIAgent(new ChatClientAgentOptions
{
    ChatHistoryProvider = new CosmosChatHistoryProvider(...),     // per-conversation persistence
    AIContextProviders = [new FoundryMemoryProvider(...)]         // per-user memory
});
```

The history provider persists message bodies; the memory provider extracts and recalls salient facts.

## Bounded chat history (compaction)

For very long conversations, cap the in-prompt history. Use `Microsoft.Extensions.AI.ChatReduction` (or the `UseChatReduction` middleware extension if available in your version):

```csharp
AIAgent agent = chatClient
    .AsIChatClient()
    .AsBuilder()
    .UseChatReduction(new SummarizingChatReducer(targetTokenCount: 1000))
    .BuildAIAgent(instructions: "...");
```

This summarizes old messages once the running token count exceeds the target. See `samples/02-agents/Agents/Agent_Step13_ChatReduction/` for canonical usage.

## Decision tree

```
Need conversation messages persisted across processes?
├── Yes → ChatHistoryProvider (CosmosChatHistoryProvider for production)
└── No → use AgentSession.SerializeSessionAsync into your own store

Need the agent to remember salient facts across conversations?
├── Yes, on Foundry → FoundryMemoryProvider
├── Yes, custom logic → AIContextProvider + ProviderSessionState<T> + external store
└── No → just rely on per-session state in StateBag

Long conversations blowing the context window?
└── Add UseChatReduction with a summarizing reducer
```

## Packages avoided

| Package | Don't use because |
|---------|-------------------|
| `Microsoft.Agents.AI.Mem0` | Owner-unlisted on NuGet; not currently maintained as a stable surface. Use `FoundryMemoryProvider` or a custom `AIContextProvider`. |
| `Microsoft.Agents.AI.FoundryMemory` | Superseded — `FoundryMemoryProvider` is now in `Microsoft.Agents.AI.Foundry`. |
| `Microsoft.Agents.AI.AzureAI.Persistent` | Marked `[Obsolete]` in source — points to Foundry. Don't use for new work. |

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Provider state lost after deserialization | Implement `StateKeys` and use `ProviderSessionState<T>` so state round-trips through `SerializeSessionAsync` |
| Foundry memory queries return nothing | Memory extraction is async — call `await memoryProvider.WhenUpdatesCompletedAsync()` before relying on it |
| Multiple `MessageAIContextProvider`s inject conflicting content | They run sequentially; later providers see earlier output. Keep them composable and idempotent. |
| RAG provider returns adversarial content | Validate / sanitize / length-limit before merging into context |
| Conversation tokens balloon | Add `UseChatReduction` middleware |
| User reports the agent "forgot" them across sessions | Scope state by user id, not session id, in the provider's stateInitializer |
| `ChatHistoryProvider` and `AIContextProvider` storing duplicate messages | They serve different purposes — history is the raw log, context is selective recall. Don't conflate them. |
