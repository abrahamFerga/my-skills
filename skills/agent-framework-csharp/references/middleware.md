# Middleware

MAF has four interception layers. Pick the layer that matches the concern's scope.

| Layer | Wraps | Use for |
|-------|-------|---------|
| **Chat-client middleware** | `IChatClient.GetResponseAsync` | Per-LLM-call concerns: logging requests, retries, rate-limiting |
| **Agent middleware** | `AIAgent.RunAsync` | Per-agent-run concerns: PII redaction, guardrails, approval orchestration |
| **Function-invocation middleware** | `FunctionInvokingChatClient` invoking a tool | Per-tool concerns: result override, tool-call logging, sandbox |
| **`AIContextProvider`** | `RunAsync` request enrichment | Dynamic instructions, memory, RAG — see [memory.md](memory.md) |

All four can stack. Order matters — see "Composition order" at the end.

## Agent-level middleware

Signature: `Func<IEnumerable<ChatMessage>, AgentSession?, AgentRunOptions?, AIAgent, CancellationToken, Task<AgentResponse>>`.

```csharp
async Task<AgentResponse> PIIMiddleware(
    IEnumerable<ChatMessage> messages,
    AgentSession? session,
    AgentRunOptions? options,
    AIAgent innerAgent,
    CancellationToken cancellationToken)
{
    var redactedIn = messages.Select(m => new ChatMessage(m.Role, RedactPii(m.Text))).ToList();
    var response = await innerAgent.RunAsync(redactedIn, session, options, cancellationToken);
    response.Messages = response.Messages.Select(m => new ChatMessage(m.Role, RedactPii(m.Text))).ToList();
    return response;
}

AIAgent piiAgent = baseAgent
    .AsBuilder()
    .Use(PIIMiddleware, null)
    .Build();
```

For streaming, supply both delegates via `.Use(runFunc, runStreamingFunc)`.

## Function-invocation middleware

Signature: `Func<AIAgent, FunctionInvocationContext, Func<FunctionInvocationContext, CancellationToken, ValueTask<object?>>, CancellationToken, ValueTask<object?>>`.

```csharp
async ValueTask<object?> LogFunctionCalls(
    AIAgent agent,
    FunctionInvocationContext context,
    Func<FunctionInvocationContext, CancellationToken, ValueTask<object?>> next,
    CancellationToken cancellationToken)
{
    Console.WriteLine($"[{context.Function.Name}] start");
    var result = await next(context, cancellationToken);
    Console.WriteLine($"[{context.Function.Name}] end");
    return result;
}

AIAgent agent = baseAgent
    .AsBuilder()
    .Use(LogFunctionCalls)
    .Build();
```

You can **override the result** by returning a different value from the middleware. Useful for testing, sandboxing, or implementing approvals manually.

> Function-invocation middleware runs once **per tool call**, not once per agent run.

## Chat-client middleware

Runs on raw `IChatClient` calls — once per LLM round-trip (multiple times per `RunAsync` if tool-calling iterates).

```csharp
using Microsoft.Extensions.AI;

async Task<ChatResponse> LogChatClient(
    IEnumerable<ChatMessage> messages,
    ChatOptions? options,
    IChatClient inner,
    CancellationToken cancellationToken)
{
    Console.WriteLine("--> LLM");
    var response = await inner.GetResponseAsync(messages, options, cancellationToken);
    Console.WriteLine("<-- LLM");
    return response;
}

// Build the agent on top of a wrapped chat client:
AIAgent agent = chatClient
    .AsIChatClient()
    .AsBuilder()
    .Use(getResponseFunc: LogChatClient, getStreamingResponseFunc: null)
    .BuildAIAgent(instructions: "...", tools: [...]);
```

> `BuildAIAgent` is the agent-aware terminator on `ChatClientBuilder` — equivalent to `.Build().AsAIAgent(...)` but composes correctly with `FunctionInvokingChatClient`.

## Per-request middleware

Use `ChatClientAgentRunOptions.ChatClientFactory` to inject middleware for a single call:

```csharp
var options = new ChatClientAgentRunOptions(new ChatOptions
{
    Tools = [AIFunctionFactory.Create(GetWeather)]
})
{
    ChatClientFactory = chatClient => chatClient
        .AsBuilder()
        .Use(getResponseFunc: PerRequestChatMiddleware, getStreamingResponseFunc: null)
        .Build()
};

await agent.RunAsync("...", session, options);
```

For per-request agent-level middleware, build a temporary wrapper via `.AsBuilder().Use(...).Build()` for that one call.

## Practical recipes

### PII redaction

Outer-layer agent middleware (see signature above). Redact on both input and response messages so neither prompts nor tool outputs leak PII.

### Guardrails (content blocking)

```csharp
async Task<AgentResponse> Guardrail(IEnumerable<ChatMessage> messages, AgentSession? session,
    AgentRunOptions? options, AIAgent innerAgent, CancellationToken cancellationToken)
{
    var filtered = messages.Select(m => new ChatMessage(m.Role, BlockSensitiveTerms(m.Text))).ToList();
    var response = await innerAgent.RunAsync(filtered, session, options, cancellationToken);
    response.Messages = response.Messages.Select(m => new ChatMessage(m.Role, BlockSensitiveTerms(m.Text))).ToList();
    return response;
}
```

### Cost / retry / circuit-breaking

Chat-client layer. Wrap with `Microsoft.Extensions.Http.Resilience` on the underlying `HttpClient`, or build a retry decorator at the `IChatClient` level:

```csharp
IChatClient resilientClient = chatClient
    .AsIChatClient()
    .AsBuilder()
    .Use(async (messages, opts, inner, ct) =>
    {
        for (int attempt = 0; attempt < 3; attempt++)
        {
            try { return await inner.GetResponseAsync(messages, opts, ct); }
            catch (Exception ex) when (IsTransient(ex) && attempt < 2)
            {
                await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)), ct);
            }
        }
        return await inner.GetResponseAsync(messages, opts, ct);
    }, null)
    .Build();
```

Prefer `Microsoft.Extensions.Http.Resilience` policies over hand-rolled retries — they preserve cancellation and telemetry. See [hosting-and-observability.md](hosting-and-observability.md).

### Approvals (without `ApprovalRequiredAIFunction`)

When you want to gate side-effecting tool calls based on **runtime** logic (not just a static "this tool always needs approval"), write function-invocation middleware:

```csharp
async ValueTask<object?> ConditionalApproval(
    AIAgent agent,
    FunctionInvocationContext context,
    Func<FunctionInvocationContext, CancellationToken, ValueTask<object?>> next,
    CancellationToken cancellationToken)
{
    if (RequiresApproval(context.Function.Name, context.Arguments) &&
        !await PromptForApprovalAsync(context.Function.Name, context.Arguments))
    {
        return $"Call to {context.Function.Name} was rejected by the user.";
    }
    return await next(context, cancellationToken);
}
```

For declared-as-approved tools, prefer `ApprovalRequiredAIFunction` (see [tools.md](tools.md)).

## Composition order

The pipelines build outermost-in. Calls flow through the chain in registration order:

```
Request →
  Agent middleware 1 (e.g., guardrail) →
    Agent middleware 2 (e.g., PII) →
      ChatClientAgent.RunAsync →
        AIContextProvider.ProvideAIContextAsync →
          Chat-client middleware 1 (e.g., logging) →
            Chat-client middleware 2 (e.g., retry) →
              FunctionInvokingChatClient →
                Function-invocation middleware (per tool call) →
                  Leaf IChatClient → Provider API
```

Ordering rules:

- **Outer agent middleware** sees raw user input and final assistant output. Put guardrails and PII redaction outermost so nothing escapes them.
- **Retry / resilience** belongs **innermost** (closest to the leaf chat client) so retries see the same shaped request each time.
- **Function-invocation middleware** runs once per tool call, not once per agent run — log accordingly.
- **Context providers** run *inside* the agent but *before* the chat client — they shape what the LLM sees.

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Middleware mutates `messages` in place | The collection may be a snapshot — always project to a new list before returning |
| Logging raw `message.Content` | May contain PII, secrets, user prompts — log metadata only (role, length, count, tool name) |
| Function middleware not invoked | Function middleware applies on the **agent** pipeline. Build with `.AsBuilder().Use(funcMiddleware)` on the agent, not on the chat client. |
| Per-request middleware leaks to subsequent calls | Use `ChatClientAgentRunOptions.ChatClientFactory` for one-off injection — don't mutate the agent itself |
| Hand-rolled retry loop swallows cancellation | Use `Microsoft.Extensions.Http.Resilience` or wrap properly with `CancellationToken` propagation in every catch |
| Streaming middleware misses agent middleware semantics | Provide both `runFunc` and `runStreamingFunc` to `.Use(...)`, or accept the streaming overload's signature explicitly |
