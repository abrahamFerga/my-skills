# MAF Provider Wiring

Concrete `IChatClient` setup for every supported provider. The `.AsAIAgent(...)` extension is the same shape across all of them; only the client construction differs.

## Authentication ground rules

- **Never hardcode** API keys, endpoints, or deployment names. Read from environment variables or `IConfiguration`.
- Prefer **`ManagedIdentityCredential`** in production. `DefaultAzureCredential` is fine for local dev but probes many sources — that's latency and security risk you don't want in prod.
- Pin to a **dated model version** (`gpt-4o-2024-08-06`) instead of an unversioned alias to reduce drift.

## Azure OpenAI — Chat Completions

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
    .AsAIAgent(instructions: "...", name: "MyAgent");
```

Packages (all stable): `Microsoft.Agents.AI`, `Microsoft.Agents.AI.OpenAI`, `Azure.AI.OpenAI`, `Azure.Identity`.

**Switch to API-key auth** (dev / CI without Azure AD):

```csharp
using Azure;

var credential = new AzureKeyCredential(
    Environment.GetEnvironmentVariable("AZURE_OPENAI_API_KEY")!);
var client = new AzureOpenAIClient(new Uri(endpoint), credential);
```

## Azure OpenAI — Responses API

Newer endpoint with optional server-side conversation storage:

```csharp
using OpenAI.Responses;

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetResponsesClient()
    .AsAIAgent(model: deploymentName, instructions: "...", name: "MyAgent");
```

**Disable service-side chat history** if you want the framework to manage history (e.g., to use a `ChatHistoryProvider`):

```csharp
AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetResponsesClient()
    .AsIChatClientWithStoredOutputDisabled(model: deploymentName)
    .AsAIAgent(instructions: "...", name: "MyAgent");
```

## OpenAI (direct, non-Azure) — Chat Completions

```csharp
using OpenAI;
using OpenAI.Chat;
using Microsoft.Agents.AI;

var apiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY")
    ?? throw new InvalidOperationException("OPENAI_API_KEY is not set.");
var model = Environment.GetEnvironmentVariable("OPENAI_CHAT_MODEL_NAME") ?? "gpt-4o-2024-08-06";

AIAgent agent = new OpenAIClient(apiKey)
    .GetChatClient(model)
    .AsAIAgent(instructions: "...", name: "MyAgent");
```

Packages (stable): `Microsoft.Agents.AI`, `Microsoft.Agents.AI.OpenAI`, `OpenAI`.

## OpenAI (direct) — Responses API

```csharp
using OpenAI;
using OpenAI.Responses;

AIAgent agent = new OpenAIClient(apiKey)
    .GetResponsesClient()
    .AsAIAgent(model: model, instructions: "...", name: "MyAgent");
```

> `AsAIAgent` on `ResponsesClient` requires the **`model:`** argument — the client isn't bound to a model at construction. On `ChatClient` the model is fixed via `GetChatClient(deploymentName)`.

## Azure AI Foundry — first-class Foundry agents

For agents managed in an Azure AI Foundry project (Foundry has its own agent registry):

```csharp
using Azure.AI.Projects;
using Azure.Identity;
using Microsoft.Agents.AI;

var projectEndpoint = Environment.GetEnvironmentVariable("AZURE_AI_PROJECT_ENDPOINT")!;
var deploymentName = Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME")!;

var projectClient = new AIProjectClient(new Uri(projectEndpoint), new DefaultAzureCredential());

ChatClientAgent agent = projectClient.AsAIAgent(new ChatClientAgentOptions
{
    Name = "FoundryAgent",
    ChatOptions = new() { ModelId = deploymentName, Instructions = "..." }
});
```

Package (stable): `Microsoft.Agents.AI.Foundry` (currently 1.5.x). Adds the `AsAIAgent` extension on `AIProjectClient` and the `FoundryMemoryProvider` (see [memory.md](memory.md)).

## Azure AI Foundry — arbitrary models via OpenAI SDK

For non-OpenAI models hosted in Foundry (Phi, DeepSeek, Llama, xAI, Mistral, etc.) use the OpenAI SDK with the Foundry endpoint override:

```csharp
using System.ClientModel;
using System.ClientModel.Primitives;
using Azure.Identity;
using OpenAI;
using OpenAI.Chat;
using Microsoft.Agents.AI;

var endpoint = Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT")!;
var apiKey = Environment.GetEnvironmentVariable("AZURE_OPENAI_API_KEY");
var model = Environment.GetEnvironmentVariable("AZURE_AI_MODEL_DEPLOYMENT_NAME") ?? "Phi-4-mini-instruct";

var clientOptions = new OpenAIClientOptions { Endpoint = new Uri(endpoint) };

OpenAIClient client = string.IsNullOrWhiteSpace(apiKey)
    ? new OpenAIClient(new BearerTokenPolicy(new DefaultAzureCredential(), "https://ai.azure.com/.default"), clientOptions)
    : new OpenAIClient(new ApiKeyCredential(apiKey), clientOptions);

AIAgent agent = client.GetChatClient(model).AsAIAgent(instructions: "...", name: "MyAgent");
```

> **Pick a function-calling-capable model** if the agent will use tools. Smaller Foundry models often skip that capability.

## Ollama (local / self-hosted)

```csharp
using OllamaSharp;
using Microsoft.Extensions.AI;
using Microsoft.Agents.AI;

var endpoint = Environment.GetEnvironmentVariable("OLLAMA_ENDPOINT")!;       // e.g. http://localhost:11434
var modelName = Environment.GetEnvironmentVariable("OLLAMA_MODEL_NAME")!;    // e.g. llama3.2

AIAgent agent = new OllamaApiClient(new Uri(endpoint), modelName)
    .AsAIAgent(instructions: "...", name: "MyAgent");
```

Packages: `Microsoft.Agents.AI`, `OllamaSharp`, `Microsoft.Extensions.AI`.

> Ollama tool-calling support varies by model. Verify with a small `[Description]`-tagged tool before relying on it.

## Anthropic — public API or Azure Foundry

```csharp
using Anthropic;
using Anthropic.Foundry;
using Azure.Identity;
using Microsoft.Agents.AI;

string deploymentName = Environment.GetEnvironmentVariable("ANTHROPIC_CHAT_MODEL_NAME") ?? "claude-haiku-4-5";
string? resource = Environment.GetEnvironmentVariable("ANTHROPIC_RESOURCE");
string? apiKey = Environment.GetEnvironmentVariable("ANTHROPIC_API_KEY");

using AnthropicClient client = resource is null
    ? new AnthropicClient { ApiKey = apiKey ?? throw new InvalidOperationException("ANTHROPIC_API_KEY is required") }
    : apiKey is not null
        ? new AnthropicFoundryClient(new AnthropicFoundryApiKeyCredentials(apiKey, resource))
        : new AnthropicFoundryClient(new AnthropicFoundryIdentityTokenCredentials(
            new DefaultAzureCredential(), resource, ["https://ai.azure.com/.default"]));

AIAgent agent = client.AsAIAgent(model: deploymentName, instructions: "...", name: "MyAgent");
```

Package: `Microsoft.Agents.AI.Anthropic` (prerelease — install with `--prerelease`).

`ANTHROPIC_RESOURCE` is the subdomain in the Foundry endpoint (the part before `.services.ai.azure.com`).

## Wrapping the chat client with construction-time middleware

To attach resilience, logging, or telemetry to the chat client *before* it becomes an agent, build the chat-client pipeline first:

```csharp
using Microsoft.Extensions.AI;

IChatClient chatClient = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetChatClient(deploymentName)
    .AsIChatClient()                       // expose as IChatClient for the builder
    .AsBuilder()
    .UseLogging()                          // from Microsoft.Extensions.AI
    .Build();

AIAgent agent = chatClient.AsAIAgent(instructions: "...", name: "MyAgent");
```

> Function-invocation middleware does **not** belong here — it's wired automatically by `AsAIAgent` via `FunctionInvokingChatClient`. See [middleware.md](middleware.md) for the function-invocation layer.

## Choosing between providers

| Choose | When |
|--------|------|
| **Azure OpenAI Chat** | On Azure with Azure OpenAI Service; Azure AD auth and quotas |
| **Azure OpenAI Responses** | Same, plus server-side conversation history |
| **Azure AI Foundry (Project)** | Agents managed in a Foundry project; first-class memory store integration |
| **Foundry via OpenAI SDK** | Non-OpenAI model (Phi, Llama, DeepSeek, xAI) hosted in Foundry |
| **OpenAI direct** | Not on Azure; prototyping with OpenAI's API |
| **Ollama** | Local / air-gapped / cost-sensitive — accept variable tool-calling fidelity |
| **Anthropic** | You need Claude specifically (reasoning, large context, agent quality) |

## Canonical environment variables

| Variable | Used by |
|----------|---------|
| `AZURE_OPENAI_ENDPOINT` | Azure OpenAI, Foundry-via-OpenAI |
| `AZURE_OPENAI_DEPLOYMENT_NAME` | Azure OpenAI |
| `AZURE_OPENAI_API_KEY` | Azure OpenAI / Foundry (when not using AAD) |
| `AZURE_AI_PROJECT_ENDPOINT` | Azure AI Foundry Project |
| `AZURE_AI_MODEL_DEPLOYMENT_NAME` | Foundry deployments |
| `OPENAI_API_KEY`, `OPENAI_CHAT_MODEL_NAME` | OpenAI direct |
| `OLLAMA_ENDPOINT`, `OLLAMA_MODEL_NAME` | Ollama |
| `ANTHROPIC_API_KEY`, `ANTHROPIC_RESOURCE`, `ANTHROPIC_CHAT_MODEL_NAME` | Anthropic / Foundry-hosted Anthropic |

Use `dotnet user-secrets` for local development; environment variables or Key Vault in CI / production.
