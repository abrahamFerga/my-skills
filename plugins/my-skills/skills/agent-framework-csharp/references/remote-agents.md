# Remote Agents: A2A and AGUI

Two HTTP-based protocols for exposing and consuming MAF agents over the network. They solve different problems and have different audiences.

| Protocol | Audience | Transport | When to use |
|----------|----------|-----------|-------------|
| **A2A** (Agent-to-Agent) | Other agents | HTTP+JSON or JSON-RPC over HTTP, with a discovery `AgentCard` | One agent needs to **call** another agent as a capability — agent composition, multi-team systems, agent marketplaces |
| **AGUI** (Agent-User Interaction) | End users via a UI | HTTP POST + Server-Sent Events streaming | A web/mobile/desktop client needs to **stream** an agent's responses to a human user with tool calls, state, and reasoning |

You can host both on the same `AIAgent` — they're not exclusive.

## A2A

A2A is an open protocol (spec at https://a2a-protocol.org/). MAF integrates it via `A2A` and `A2A.AspNetCore` SDK packages, with MAF-specific extensions in `Microsoft.Agents.AI.A2A` and `Microsoft.Agents.AI.Hosting.A2A.AspNetCore`.

```bash
dotnet add package Microsoft.Agents.AI.A2A --prerelease                       # client side
dotnet add package Microsoft.Agents.AI.Hosting.A2A.AspNetCore --prerelease    # server side
```

### Expose an agent as an A2A server

```csharp
using A2A;
using A2A.AspNetCore;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Hosting.A2A;
using Microsoft.Agents.AI.Hosting.A2A.AspNetCore;
using Microsoft.AspNetCore.Builder;

AIAgent invoiceAgent = new OpenAIClient(apiKey)
    .GetChatClient(model)
    .AsAIAgent(
        instructions: "Handle invoice queries for Contoso.",
        name: "InvoiceAgent",
        tools: [/* domain tools */]);

AgentCard card = new()
{
    Name = "InvoiceAgent",
    Description = "Handles requests relating to invoices.",
    Version = "1.0.0",
    DefaultInputModes = ["text"],
    DefaultOutputModes = ["text"],
    Capabilities = new AgentCapabilities { Streaming = false, PushNotifications = false },
    Skills = [
        new AgentSkill
        {
            Id = "id_invoice_agent",
            Name = "InvoiceQuery",
            Description = "Handles requests relating to invoices.",
            Tags = ["invoice"],
            Examples = ["List the latest invoices for Contoso."]
        }
    ],
    SupportedInterfaces = new List<AgentInterface>
    {
        new() { Url = "http://localhost:5000", ProtocolBinding = ProtocolBindingNames.JsonRpc,   ProtocolVersion = "1.0" },
        new() { Url = "http://localhost:5000", ProtocolBinding = ProtocolBindingNames.HttpJson,  ProtocolVersion = "1.0" }
    }
};

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient();
builder.AddA2AServer(invoiceAgent);              // register the server in DI

var app = builder.Build();
app.MapA2AHttpJson(invoiceAgent, "/");           // HTTP+JSON endpoint
app.MapA2AJsonRpc(invoiceAgent, "/");            // JSON-RPC endpoint (same path)
app.MapWellKnownAgentCard(card);                 // /.well-known/agent-card.json for discovery

await app.RunAsync();
```

Key endpoints:
- `POST /` (or your chosen path) — HTTP+JSON / JSON-RPC routes
- `GET /.well-known/agent-card.json` — agent discovery

A2A doesn't define authentication; layer standard ASP.NET Core auth (JWT, OAuth, mTLS) on the routes as you would for any HTTP API.

> The **`AgentSkill` from the A2A SDK is different** from MAF's `AgentSkill` / `AgentSkillsProvider`. The A2A `AgentSkill` is metadata in the agent card; the MAF `AgentSkill` is the runtime capability bundle (see [agent-skills.md](agent-skills.md)). They share a name but live in different namespaces.

### Multi-agent on one host

`AddA2AServer` registers a keyed singleton by `agent.Name`. Register multiple agents on the same host with distinct ports or paths:

```csharp
builder.AddA2AServer(invoiceAgent);
builder.AddA2AServer(policyAgent);
builder.AddA2AServer(logisticsAgent);

app.MapA2AJsonRpc(invoiceAgent,   "/invoice");
app.MapA2AJsonRpc(policyAgent,    "/policy");
app.MapA2AJsonRpc(logisticsAgent, "/logistics");
```

Or run one per port — see `samples/05-end-to-end/A2AClientServer/` for the canonical multi-port layout.

### Consume a remote A2A agent

```csharp
using A2A;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.A2A;

A2ACardResolver resolver = new(new Uri("http://localhost:5000"));
AIAgent remoteAgent = await resolver.GetAIAgentAsync();

AgentResponse response = await remoteAgent.RunAsync("What's the status of invoice #12345?");
Console.WriteLine(response.Text);
```

`A2ACardResolver` fetches `/.well-known/agent-card.json` from the URL, builds an `IA2AClient`, and exposes it as an `AIAgent`. From the caller's perspective it's just an agent — `RunAsync` / `RunStreamingAsync` work normally.

### Expose A2A skills as function tools

A common pattern: a "router" agent that uses remote A2A agents as tools (one tool per skill in the remote agent's card).

```csharp
A2ACardResolver resolver = new(new Uri(a2aHost));
AgentCard card = await resolver.GetAgentCardAsync();
AIAgent remoteAgent = card.AsAIAgent();

IEnumerable<AIFunction> tools = card.Skills.Select(skill =>
{
    AIFunctionFactoryOptions options = new()
    {
        Name = FunctionNameSanitizer.Sanitize(skill.Name),
        Description = $$"""
            {
              "description": "{{skill.Description}}",
              "tags": "[{{string.Join(", ", skill.Tags ?? [])}}]",
              "examples": "[{{string.Join(", ", skill.Examples ?? [])}}]"
            }
            """
    };

    return AIFunctionFactory.Create(
        async (string input, CancellationToken ct) =>
            (await remoteAgent.RunAsync(input, cancellationToken: ct)).Text,
        options);
});

AIAgent router = chatClient.AsAIAgent(
    instructions: "Route queries to the right specialist.",
    tools: [.. tools]);
```

See `samples/02-agents/A2A/A2AAgent_AsFunctionTools/Program.cs` for the verbatim pattern.

### A2A vs MCP

| | MCP | A2A |
|--|-----|-----|
| Caller | An LLM (model) | An agent |
| Granularity | Tool / resource / prompt | Skill (composite of tools) |
| Discovery | List from server | `AgentCard` at well-known URI |
| Schema | JSON Schema per tool | Skill metadata (tags, examples, input/output modes) — no required schema |
| Streaming | Limited | First-class |
| Long-running tasks | No | Task continuation tokens |

Use **MCP** to expose tools to an LLM. Use **A2A** to expose **agents** to other agents. They aren't substitutes.

## AGUI

AGUI (Agent-User Interaction) is the streaming protocol designed for **human-facing UIs** — web chat, mobile apps, desktop clients. It uses HTTP POST + Server-Sent Events with rich event types (text deltas, tool calls, state snapshots, reasoning traces).

```bash
dotnet add package Microsoft.Agents.AI.AGUI --prerelease                       # client (and shared types)
dotnet add package Microsoft.Agents.AI.Hosting.AGUI.AspNetCore --prerelease    # server hosting
```

### Expose an agent as an AGUI server

```csharp
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Hosting.AGUI.AspNetCore;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);
builder.Services.AddHttpClient().AddLogging();
builder.Services.AddAGUI();

WebApplication app = builder.Build();

string endpoint = builder.Configuration["AZURE_OPENAI_ENDPOINT"]!;
string deploymentName = builder.Configuration["AZURE_OPENAI_DEPLOYMENT_NAME"]!;

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsAIAgent(name: "AGUIAssistant", instructions: "You are a helpful assistant.");

app.MapAGUI("/", agent);
await app.RunAsync();
```

`POST /` receives a `RunAgentInput` and streams `BaseEvent` SSE messages.

### Request shape (`RunAgentInput`)

```json
{
  "threadId": "thread_abc123",
  "runId": "run_xyz789",
  "state": {},
  "messages": [
    { "id": "msg_001", "role": "user", "content": "Find Italian restaurants in Seattle" }
  ],
  "tools": [
    { "name": "SearchRestaurants", "description": "...", "parameters": {...} }
  ],
  "context": [],
  "forwardedProps": {}
}
```

Tool declarations in the input let the **client** declare tools (frontend tools) the server can call back; combined with server-side tools registered on the agent, this enables hybrid execution.

### Event stream

| Event | When |
|-------|------|
| `RUN_STARTED` | Run begins (threadId, runId) |
| `TEXT_MESSAGE_START` / `TEXT_MESSAGE_CONTENT` / `TEXT_MESSAGE_END` | Assistant text (streaming deltas) |
| `TOOL_CALL_START` / `TOOL_CALL_ARGS` / `TOOL_CALL_END` / `TOOL_CALL_RESULT` | Tool invocation lifecycle |
| `STATE_SNAPSHOT` / `STATE_DELTA` | Shared state synchronization |
| `REASONING_START` / `REASONING_MESSAGE_*` / `REASONING_END` | Extended-thinking traces |
| `RUN_ERROR` | Execution error |
| `RUN_FINISHED` | Run ends |

### Consume an AGUI agent from .NET

`AGUIChatClient` implements `IChatClient` over the AGUI protocol — so once constructed, it works with `.AsAIAgent(...)` like any other provider:

```csharp
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.AGUI;
using Microsoft.Extensions.AI;

using HttpClient httpClient = new();
AGUIChatClient chatClient = new(httpClient, serverUrl: "http://localhost:5000");

AIAgent agent = chatClient.AsAIAgent(name: "agui-client", description: "Remote agent over AGUI");

AgentSession session = await agent.CreateSessionAsync();
await foreach (AgentResponseUpdate update in agent.RunStreamingAsync("Hello", session))
{
    foreach (AIContent content in update.Contents)
    {
        if (content is TextContent t) Console.Write(t.Text);
    }
}
```

The client maintains an AGUI `ThreadId` across requests (mapped from the `AgentSession`).

### Frontend tools, backend tools, HITL, state

Advanced AGUI scenarios (covered by `samples/02-agents/AGUI/Step02_BackendTools`, `Step03_FrontendTools`, `Step04_HumanInLoop`, `Step05_StateManagement`):

- **Backend tools** — Tools registered on the agent at server build time:
  ```csharp
  AIAgent agent = chatClient.AsAIAgent(name: "...", instructions: "...",
      tools: [AIFunctionFactory.Create(SearchRestaurants)]);
  app.MapAGUI("/", agent);
  ```
- **Frontend tools** — Client sends tool declarations in `RunAgentInput.Tools`; the agent calls them; client executes and returns results via the next request.
- **HITL** — Wrap agent tools in `ApprovalRequiredAIFunction`. The event stream emits `FunctionApprovalRequestContent`; the client surfaces a confirmation prompt and returns `FunctionApprovalResponseContent` on the next turn.
- **State management** — Pass `RunAgentInput.State` for shared structured state; the agent emits `STATE_SNAPSHOT` and `STATE_DELTA` for predictive UI updates.

### Auth for AGUI

AGUI doesn't prescribe an auth scheme — apply standard ASP.NET Core auth (cookie, bearer, mTLS) to the `/` route. Identity flows into the agent via DI / `HttpContext.User`.

## Choosing between A2A and AGUI

```
Caller is another agent → A2A
Caller is a human-facing UI (web, mobile, desktop) → AGUI
Caller is an LLM looking for a tool → MCP (see tools.md)
```

You can compose: a frontend talks **AGUI** to a router agent, which in turn talks **A2A** to specialist agents, each of which uses **MCP** tools.

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Confusing A2A `AgentSkill` (metadata) with MAF `AgentSkill` (runtime bundle) | They share a name but live in different namespaces. The A2A type goes in the agent card; the MAF type goes through `AgentSkillsProvider`. |
| A2A agent card not discoverable | Confirm `app.MapWellKnownAgentCard(card)` is called; verify `/.well-known/agent-card.json` returns 200 |
| `A2ACardResolver` fails | URL must be the agent's base URL — the resolver appends the well-known path itself |
| AGUI client sends only one message per turn | AGUI sends full message history on every request — this is by design (server is mostly stateless on per-turn) |
| AGUI logs raw user prompts | Disable content capture in your OTel exporter; emit metadata only |
| Tried to use AGUI for agent-to-agent composition | Wrong protocol — use A2A for that. AGUI is for human users. |
| Exposed agent over AGUI without auth | AGUI doesn't define auth — add standard ASP.NET Core auth middleware |
| Multi-tenant A2A: agents leaking between tenants | Each agent is keyed by `Name` in DI. Use distinct names per tenant or partition the host. |
