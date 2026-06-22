---
name: agent-framework-csharp
description: >
  Build .NET agentic apps with Microsoft Agent Framework (MAF, the
  `Microsoft.Agents.AI` family on top of MEAI `IChatClient`). Use when the
  task involves tools/function calling, MCP client tools, agent skills,
  persisted sessions, memory, middleware, or multi-agent workflows
  (sequential/concurrent/handoff/group-chat/HITL), plus A2A/AGUI hosting,
  DI, durable agents, and OpenTelemetry. Triggers: MAF, `AIAgent`,
  `ChatClientAgent`, agent + tools, multi-agent orchestration.
  DO NOT USE FOR a single prompt-response with no tools (use MEAI
  `IChatClient` directly) or authoring MCP *servers* (use the
  `ModelContextProtocol` server SDK).
license: MIT
---

# Microsoft Agent Framework (.NET / C#)

Build production-quality agentic .NET apps using **Microsoft Agent Framework** (`Microsoft.Agents.AI`). MAF sits on top of **Microsoft.Extensions.AI** (`IChatClient`) and adds: agent abstractions (`AIAgent`, `ChatClientAgent`), sessions, tool dispatch via `FunctionInvokingChatClient`, **agent skills** (the file/code/class-based packaging unit), middleware pipelines, multi-agent workflows, declarative YAML, A2A & AGUI hosting, DI hosting, durable agents, and OpenTelemetry.

Use it whenever the scenario involves **tools, multi-step reasoning, or multi-agent collaboration** — hand-rolled tool loops with raw `IChatClient` are an anti-pattern.

## Scope

Covers the full MAF surface: creating an `AIAgent` from any `IChatClient` provider (Azure OpenAI, OpenAI, Foundry, Ollama, Anthropic), function tools, MCP client tools, agent skills (file/code/class-defined), threads and persisted sessions, streaming, structured output, middleware, memory providers (custom, Foundry, Cosmos chat history), workflows (sequential / concurrent / handoff / group chat / HITL / conditional edges / checkpoints / shared state), declarative workflows (YAML), A2A and AGUI protocols, DI hosting, durable agents, and OpenTelemetry.

USE FOR: scaffolding a new MAF app; adding tools, skills, sessions, memory, or workflows to an existing agent; wiring MCP servers as agent tools; multi-agent orchestration; exposing/consuming agents over A2A or AGUI; registering agents in DI; Azure Functions / durable agent hosting; enabling OpenTelemetry on agents and workflows; declarative YAML workflows.

DO NOT USE FOR: pure single-prompt LLM calls with no tool calling (use MEAI `IChatClient` directly); classification on tabular data (use ML.NET); Semantic Kernel projects (MAF supersedes SK); creating MCP *servers* (use the `ModelContextProtocol` server SDK directly); Python Agent Framework (this skill is .NET-only).

## When to Use

- Building a new agent on Azure OpenAI / OpenAI / Foundry / Ollama / Anthropic
- Adding tool / function calling, MCP tools, or **agent skills** (the file/code/class-defined capability bundles) to an existing chat client
- Multi-turn conversations that need durable, serializable state (`AgentSession`)
- Memory: per-session, cross-session, user-scoped — via `AIContextProvider` (custom, Foundry, custom Cosmos-backed `ChatHistoryProvider`)
- Middleware: PII redaction, retries, guardrails, approvals
- Multi-agent: sequential, concurrent, handoff, group chat, human-in-the-loop, conditional edges, checkpointing, shared state
- Declarative workflows defined in YAML
- Exposing agents over **A2A** (agent-to-agent) or **AGUI** (agent-to-user); consuming remote agents the same way
- Hosting in ASP.NET Core, Azure Functions, or as durable workflows
- Enabling distributed tracing on agent runs

## Stop Signals

- **Single prompt → response, no tools, no state** → Use `IChatClient` from `Microsoft.Extensions.AI` directly.
- **Classifying tabular/structured data** → Use ML.NET (`Microsoft.ML`). LLMs are slower, costlier, and non-deterministic for this.
- **Building an MCP *server*** → Use the `ModelContextProtocol` server SDK and `dotnet new mcpserver`. MAF *consumes* MCP tools; it does not author servers.
- **Semantic Kernel migration** → MAF supersedes SK. Don't add SK to a new project.
- **Python project** → This skill is .NET (`Microsoft.Agents.AI`) only.

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Provider | Yes | Azure OpenAI, OpenAI, Foundry, Ollama, or Anthropic. Default Azure OpenAI if unspecified. |
| Model / deployment name | Yes | e.g., `gpt-4o-2024-08-06`, or your Azure deployment name |
| Auth method | Recommended | `ManagedIdentityCredential` in prod; `DefaultAzureCredential` or env-var API key in dev. Never hardcode. |
| Target framework | Yes | `net8.0` or later (`net9.0` / `net10.0` recommended) |
| Hosting model | Recommended | Console, Generic Host, ASP.NET Core, Azure Functions, or A2A/AGUI server |

## Package release status (as of MAF 1.6.x)

This matters because MAF is released package-by-package. Some packages are **stable** (`1.6.x`), most are still **prerelease** (`1.6.x-preview.<date>.<n>` or `-rc<n>`). Pass `--prerelease` only where required.

| Package | Status | Use when |
|---------|--------|----------|
| `Microsoft.Agents.AI` | **Stable** | Always — core agent abstractions |
| `Microsoft.Agents.AI.Abstractions` | **Stable** | Pulled transitively |
| `Microsoft.Agents.AI.OpenAI` | **Stable** | OpenAI + Azure OpenAI providers |
| `Microsoft.Agents.AI.Workflows` | **Stable** | Multi-agent workflows |
| `Microsoft.Agents.AI.Foundry` | **Stable** (1.5.x) | Azure AI Foundry agents; includes `FoundryMemoryProvider` |
| `Microsoft.Agents.AI.Anthropic` | Prerelease | Anthropic provider |
| `Microsoft.Agents.AI.A2A` | Prerelease | Consume A2A agents |
| `Microsoft.Agents.AI.Hosting.A2A.AspNetCore` | Prerelease | Host A2A servers |
| `Microsoft.Agents.AI.AGUI` | Prerelease | Consume AGUI agents |
| `Microsoft.Agents.AI.Hosting.AGUI.AspNetCore` | Prerelease | Host AGUI servers |
| `Microsoft.Agents.AI.Hosting` | Prerelease | `AddAIAgent` DI helpers |
| `Microsoft.Agents.AI.Hosting.AzureFunctions` | Prerelease | Durable agents in Azure Functions |
| `Microsoft.Agents.AI.Workflows.Declarative` | Prerelease (rc1) | YAML workflows |
| `Microsoft.Agents.AI.AzureAI.Persistent` | Prerelease | Legacy — prefer `Microsoft.Agents.AI.Foundry` |
| `Microsoft.Agents.AI.CosmosNoSql` | Prerelease | `CosmosChatHistoryProvider` |
| `Microsoft.Agents.AI.DurableTask` | Prerelease | Durable workflow orchestrations |

> **Avoid:** `Microsoft.Agents.AI.Mem0` (unlisted by owner), `Microsoft.Agents.AI.AzureAI` (superseded — use `.Foundry`), and `Microsoft.Agents.AI.FoundryMemory` (merged into `.Foundry`). The declarative *agent* package (`Microsoft.Agents.AI.Declarative`) is `IsPackable=false` — only consumable from source.

## Core Mental Model

```
+--------------------------------------------------------+
|  AIAgent (abstract)                                    |
|   └─ ChatClientAgent                                   |   ← what you actually create
|        ├─ IChatClient                                  |   ← from MEAI; wraps any provider
|        ├─ tools[]                                      |   ← AIFunction / MCP / approval-gated
|        ├─ Instructions                                 |
|        ├─ middleware                                   |   ← function/chat-client/agent layers
|        └─ AIContextProvider[]                          |   ← memory, RAG, agent skills, custom
|                                                        |
|   RunAsync(messages, session)        → AgentResponse   |
|   RunStreamingAsync(messages, ...)   → IAsyncEnumerable<AgentResponseUpdate>
|   CreateSessionAsync()               → AgentSession    |   ← serializable conversation handle
+--------------------------------------------------------+
```

Key types (from `Microsoft.Agents.AI`):

| Type | Purpose |
|------|---------|
| `AIAgent` | Abstract base — what business code depends on |
| `ChatClientAgent` | Concrete agent built on `IChatClient` |
| `AgentSession` | Per-conversation state; pass to subsequent `RunAsync` calls |
| `AgentResponse` / `AgentResponseUpdate` | Batch / streaming output |
| `AIFunctionFactory.Create(method)` | Wrap a `[Description]`-tagged method as a tool |
| `ApprovalRequiredAIFunction` | Wrap a tool so calls require human approval |
| `AIContextProvider` / `MessageAIContextProvider` | Inject instructions, messages, or tools per run (memory, RAG, skills) |
| `ChatHistoryProvider` | Persist full conversation history (separate from `AIContextProvider`) |
| `AgentSkillsProvider` | Loads file/code/class-defined **agent skills** (an `AIContextProvider`) |
| `AgentWorkflowBuilder` | `BuildSequential` / `BuildConcurrent` / `CreateHandoffBuilderWith` / `CreateGroupChatBuilderWith` |
| `AIAgentBuilder` (via `.AsBuilder()`) | Compose middleware around an agent |

> The conversation handle is **`AgentSession`** (not `AgentThread` — older / SK docs use that term; MAF renamed it).

## Workflow

### Step 1: Verify prerequisites

```bash
dotnet --version    # require 8.0+; 10.0+ recommended
```

### Step 2: Scaffold the project and add packages

```bash
dotnet new console -n MyAgentApp
cd MyAgentApp

# Core packages — STABLE (no --prerelease needed)
dotnet add package Microsoft.Agents.AI
dotnet add package Microsoft.Agents.AI.OpenAI

# Provider SDK — pick the one matching your scenario
dotnet add package Azure.AI.OpenAI     # Azure OpenAI / Foundry-via-AzureOpenAIClient
dotnet add package Azure.Identity      # for DefaultAzureCredential / ManagedIdentityCredential
```

Minimum `.csproj`:
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.Agents.AI" Version="1.*" />
    <PackageReference Include="Microsoft.Agents.AI.OpenAI" Version="1.*" />
    <PackageReference Include="Azure.AI.OpenAI" Version="2.*" />
    <PackageReference Include="Azure.Identity" Version="1.*" />
  </ItemGroup>
</Project>
```

> Add `--prerelease` (or use a `1.*-*` floating wildcard) **only** for packages outside the stable set above — e.g., A2A, AGUI, Anthropic, Workflows.Declarative, Hosting.

### Step 3: Hello agent (Azure OpenAI)

```csharp
using Azure.AI.OpenAI;
using Azure.Identity;
using Microsoft.Agents.AI;

var endpoint = Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT")
    ?? throw new InvalidOperationException("AZURE_OPENAI_ENDPOINT is not set.");
var deploymentName = Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT_NAME")
    ?? throw new InvalidOperationException("AZURE_OPENAI_DEPLOYMENT_NAME is not set.");

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsAIAgent(name: "HaikuBot", instructions: "You write beautiful haikus.");

Console.WriteLine(await agent.RunAsync("Haiku about Agent Framework."));
```

**Rules:**
- Configuration **always** from env vars (`UPPER_SNAKE_CASE`) or `IConfiguration`. Never hardcode.
- In production replace `DefaultAzureCredential` with `ManagedIdentityCredential` to avoid credential probing.
- Pin to a dated model version (e.g., `gpt-4o-2024-08-06`) to reduce drift.

For other providers (OpenAI direct, Foundry, Ollama, Anthropic), see [references/providers.md](references/providers.md).

### Step 4: Add function tools

```csharp
using System.ComponentModel;
using Microsoft.Extensions.AI;

[Description("Get the weather for a given location.")]
static string GetWeather(
    [Description("The location to get the weather for.")] string location)
    => $"The weather in {location} is cloudy with a high of 15°C.";

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsAIAgent(
        instructions: "You are a helpful assistant",
        tools: [AIFunctionFactory.Create(GetWeather)]);
```

**Critical rules:**
- `[Description]` is **required** on the method and every parameter — the LLM picks tools from these strings.
- Tools can be `async` and accept `CancellationToken` (auto-injected, not in the schema).
- **Do not** hand-roll a tool-dispatch loop on `IChatClient`. `AsAIAgent` wires `FunctionInvokingChatClient` automatically.

For approvals, MCP tools, structured output, dynamic tools, images → [references/tools.md](references/tools.md).
For file/code/class-defined **agent skills** (the bundled capabilities pattern) → [references/agent-skills.md](references/agent-skills.md).

### Step 5: Multi-turn with `AgentSession`

```csharp
AgentSession session = await agent.CreateSessionAsync();
Console.WriteLine(await agent.RunAsync("Tell me a joke about a pirate.", session));
Console.WriteLine(await agent.RunAsync("Now add emojis.", session));

// Persist across processes
JsonElement saved = await agent.SerializeSessionAsync(session);
AgentSession resumed = await agent.DeserializeSessionAsync(saved);
```

Sessions carry chat history, context-provider state, and tool-call state. Don't fake multi-turn by mutating `ChatOptions.Messages` — use a session.

### Step 6: Streaming

```csharp
await foreach (AgentResponseUpdate update in agent.RunStreamingAsync("Tell me a story.", session))
{
    Console.Write(update);
}

// Or collect a streaming run into a single response for inspection:
AgentResponse final = await agent.RunStreamingAsync("...", session).ToAgentResponseAsync();
```

### Step 7: Apply guardrails

Every MAF agent shipped to production must satisfy:

1. **Configuration from env / `IConfiguration`** — no hardcoded endpoints, deployments, or keys.
2. **Explicit `ChatOptions`**: `Temperature = 0f` for determinism; `MaxOutputTokens` to bound responses.
3. **Tool descriptions audited** — no vague `[Description("does stuff")]`.
4. **Approvals on side-effecting tools** — wrap with `ApprovalRequiredAIFunction`.
5. **Observability** — `.AsBuilder().UseOpenTelemetry(sourceName)` on the agent + matching `AddSource` on the tracer.
6. **Never log raw `message.Content` / `response.Text`** — log metadata only.
7. **Model version pinning** — dated id (`gpt-4o-2024-08-06`), not floating alias.
8. **Workflow iteration caps** — `MaximumIterationCount` on group chat / loop managers.

### Step 8: Verify

```bash
dotnet build -c Release -warnaserror
dotnet run
```

Send a prompt that should trigger a tool and confirm dispatch happens.

## Pick the right reference for the next layer

| Need | Load |
|------|------|
| A different provider (OpenAI direct / Foundry / Ollama / Anthropic) | [references/providers.md](references/providers.md) |
| Function tools, approvals, dynamic tools, MCP client tools, structured output, images | [references/tools.md](references/tools.md) |
| **Agent skills** — file-based (`SKILL.md` + scripts/), `AgentInlineSkill`, `AgentClassSkill<T>` | [references/agent-skills.md](references/agent-skills.md) |
| Memory: `AIContextProvider`, `ChatHistoryProvider`, `FoundryMemoryProvider`, `CosmosChatHistoryProvider`, scopes | [references/memory.md](references/memory.md) |
| Middleware: agent / function-invocation / chat-client layers; PII, retries, guardrails | [references/middleware.md](references/middleware.md) |
| Multi-agent: sequential, concurrent, handoff, group chat, HITL, conditional edges, checkpoints, shared state, loops | [references/workflows.md](references/workflows.md) |
| Declarative YAML workflows (`Microsoft.Agents.AI.Workflows.Declarative`) | [references/declarative.md](references/declarative.md) |
| **A2A** (agent-to-agent) and **AGUI** (agent-to-user) — expose & consume agents over HTTP | [references/remote-agents.md](references/remote-agents.md) |
| DI registration, ASP.NET / Azure Functions / Durable hosting, OpenTelemetry | [references/hosting-and-observability.md](references/hosting-and-observability.md) |

## Validation

- [ ] `dotnet build -c Release -warnaserror` passes
- [ ] Project targets `net8.0` or later
- [ ] Stable core packages (`Microsoft.Agents.AI`, `.OpenAI`, `.Workflows`, `.Foundry`) referenced without `--prerelease`; preview packages explicitly flagged
- [ ] No API keys / endpoints hardcoded
- [ ] Every tool method has `[Description]` on method and every parameter
- [ ] Multi-turn uses `AgentSession` (not manual `ChatMessage` accumulation)
- [ ] Side-effecting tools wrapped in `ApprovalRequiredAIFunction`
- [ ] When hosted (ASP.NET / Functions), agent registered in DI — not constructed per-request
- [ ] `ChatOptions.Temperature` and `MaxOutputTokens` set explicitly
- [ ] OpenTelemetry wired on any deployed (non-sample) agent
- [ ] Logs do **not** include raw message contents

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Building an agent by writing a tool-dispatch loop on `IChatClient` | Use `AsAIAgent(tools: [...])` — `FunctionInvokingChatClient` is auto-wired |
| Tool not invoked despite obvious user intent | `[Description]` is missing or vague — be specific |
| Adding `--prerelease` to `Microsoft.Agents.AI` | The core package is **stable** since 1.6.x — don't pass `--prerelease` for it |
| Recommending `Microsoft.Agents.AI.Mem0` | Owner-unlisted on NuGet — use `FoundryMemoryProvider` from `.Foundry`, or write a custom `AIContextProvider`. See [references/memory.md](references/memory.md). |
| Recommending `Microsoft.Agents.AI.AzureAI` | Superseded — use `Microsoft.Agents.AI.Foundry` |
| Recommending `Microsoft.Agents.AI.FoundryMemory` | Merged into `Microsoft.Agents.AI.Foundry` |
| Looking for `AgentThread` | Renamed to `AgentSession` — use `agent.CreateSessionAsync()` |
| Calling `AsAIAgent` on a Semantic Kernel `Kernel` | MAF supersedes SK — build a `ChatClientAgent` from `IChatClient` |
| Hardcoded API key in `appsettings.json` | User-secrets in dev, Key Vault / Managed Identity in prod |
| `DefaultAzureCredential` in production | Latency / probing risk — use `ManagedIdentityCredential` |
| Multi-turn by manually appending `ChatMessage`s into options | Use `agent.CreateSessionAsync()` |
| Logging `message.Content` for debugging | Contents may be PII or secrets — log metadata only (role, length, tool name) |
| Confusing **agent skills** with `[Description]`-tagged tools | Skills are larger, file-bundled capability units loaded on demand. Tools are single functions. See [references/agent-skills.md](references/agent-skills.md). |
| Confusing A2A with MCP | MCP = model calls a tool. A2A = agent calls another agent over a discovery-friendly protocol. See [references/remote-agents.md](references/remote-agents.md). |
| Using MAF for a single prompt-response call with no tools | Use `IChatClient` directly from MEAI |
| Re-using `AgentSession` across different agents | Sessions are agent-specific |
| Token cost surprises | Set `MaxOutputTokens`; count tokens client-side with `Microsoft.ML.Tokenizers`; enforce a per-session budget |

## Reference Files

- [references/providers.md](references/providers.md) — Provider wiring for Azure OpenAI (Chat / Responses), OpenAI, Foundry, Ollama, Anthropic. Auth options, environment variables, `clientFactory` middleware injection. **Load when:** picking or switching providers.
- [references/tools.md](references/tools.md) — Function tools, parameter conventions, async + DI, approvals (`ApprovalRequiredAIFunction`), per-request tools, dynamic tool expansion (`FunctionInvokingChatClient.CurrentContext`), MCP client integration, structured output (`RunAsync<T>`), image input. **Load when:** implementing anything tool-related beyond the basic `[Description]` pattern.
- [references/agent-skills.md](references/agent-skills.md) — The **agent skill** system: file-based `SKILL.md` + scripts/, `AgentInlineSkill` fluent builder, `AgentClassSkill<TSelf>` with `[AgentSkillResource]` / `[AgentSkillScript]` attributes. `AgentSkillsProvider`, `AgentSkillsProviderBuilder`, `SubprocessScriptRunner`. **Load when:** organizing capabilities as on-disk bundles or building reusable skill libraries.
- [references/memory.md](references/memory.md) — `AIContextProvider` vs `MessageAIContextProvider` vs `ChatHistoryProvider`, `ProviderSessionState<T>`, scopes (per-session, cross-session, user-scoped), `FoundryMemoryProvider`, `CosmosChatHistoryProvider`. **Load when:** the agent needs memory across turns or across conversations.
- [references/middleware.md](references/middleware.md) — Agent / function-invocation / chat-client middleware. PII filtering, guardrails, per-request middleware. Composition order. **Load when:** adding cross-cutting concerns.
- [references/workflows.md](references/workflows.md) — `AgentWorkflowBuilder` (sequential, concurrent, handoff, group chat); custom executors; `RequestPort` (HITL), conditional edges, `CheckpointManager`, shared state, fan-out/fan-in, loops, visualization, `workflow.AsAIAgent()`. **Load when:** the task involves more than one agent or non-linear control flow.
- [references/declarative.md](references/declarative.md) — Declarative YAML workflows via `Microsoft.Agents.AI.Workflows.Declarative` (rc), PowerFx expressions, action kinds, Foundry agent invocation. Brief mention of declarative agents (source-only, not on NuGet). **Load when:** defining workflows as data, not code.
- [references/remote-agents.md](references/remote-agents.md) — **A2A**: exposing agents via `MapA2AHttpJson` / `MapA2AJsonRpc` / `MapWellKnownAgentCard`; consuming via `A2ACardResolver` + `AgentCard.AsAIAgent()`. **AGUI**: server via `app.MapAGUI(...)` + `AddAGUI()`; client via `AGUIChatClient`. When to use each. **Load when:** agents call each other over the network, or a frontend talks to an agent.
- [references/hosting-and-observability.md](references/hosting-and-observability.md) — DI shapes (`AddAIAgent`, keyed clients, custom factories), ASP.NET Core minimal API, Azure Functions durable agents, OpenTelemetry wiring, retry/resilience, token budgeting. **Load when:** moving from a console sample to a hosted service.

## More Info

- [Microsoft Agent Framework documentation](https://learn.microsoft.com/agent-framework/) — Official docs
- [microsoft/agent-framework](https://github.com/microsoft/agent-framework) — Source (samples under `dotnet/samples/`)
- [Microsoft.Extensions.AI documentation](https://learn.microsoft.com/dotnet/ai/microsoft-extensions-ai) — The MEAI layer MAF builds on
- [Agent Skills specification](https://agentskills.io/) — Open spec the AgentSkillsProvider implements
- [A2A Protocol](https://a2a-protocol.org/) — Spec
- [Model Context Protocol](https://modelcontextprotocol.io/specification/) — Spec for MCP tools consumed by agents
