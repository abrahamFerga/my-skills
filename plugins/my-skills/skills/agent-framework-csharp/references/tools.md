# Tools, MCP, Structured Output, and Multimodal

Detailed patterns for tools in MAF: declarative function tools, approval-gated tools, per-request and dynamic tools, MCP tools, structured output, and image input.

For larger capability bundles (instructions + resources + scripts as a unit), see [agent-skills.md](agent-skills.md). Skills wrap *related* tools / resources together; this reference covers individual tools.

## Basic function tool

The 90% case: a method with `[Description]` on the method and every parameter.

```csharp
using System.ComponentModel;
using Microsoft.Extensions.AI;

[Description("Get the weather for a given location.")]
static string GetWeather(
    [Description("The location to get the weather for.")] string location)
    => $"Cloudy, 15°C in {location}.";

AIAgent agent = chatClient.AsAIAgent(
    instructions: "...",
    tools: [AIFunctionFactory.Create(GetWeather)]);
```

Rules:

- `[Description]` is **required** on the method and every parameter — the LLM picks tools from these strings.
- Tools can be static or instance methods, sync or async.
- `CancellationToken` is auto-injected and excluded from the schema.
- Return type can be `string`, a serializable object, `Task<T>`, or `ValueTask<T>`.
- Use `AIFunctionFactory.Create(method, name: "ExplicitName")` to override the auto-derived name.

## Async tool with DI

`AIFunctionFactory.Create` accepts any delegate — capture services via closure.

```csharp
public sealed class WeatherTools(HttpClient httpClient)
{
    [Description("Fetch the current weather for a city.")]
    public async Task<string> GetWeatherAsync(
        [Description("City name.")] string city,
        CancellationToken cancellationToken)
    {
        var response = await httpClient.GetStringAsync($"/weather?city={city}", cancellationToken);
        return response;
    }
}

// Wiring:
services.AddHttpClient<WeatherTools>();
var weatherTools = services.BuildServiceProvider().GetRequiredService<WeatherTools>();
var tool = AIFunctionFactory.Create(weatherTools.GetWeatherAsync);
```

For DI-resolved agents, register tools as keyed services — see [hosting-and-observability.md](hosting-and-observability.md).

## Approval-gated (human-in-the-loop) tools

Wrap any tool with `ApprovalRequiredAIFunction`. The agent emits a `ToolApprovalRequestContent`; your code asks the user, then sends the decision back.

```csharp
using Microsoft.Extensions.AI;

AIAgent agent = chatClient.AsAIAgent(
    instructions: "...",
    tools: [new ApprovalRequiredAIFunction(AIFunctionFactory.Create(GetWeather))]);

AgentSession session = await agent.CreateSessionAsync();
AgentResponse response = await agent.RunAsync("What's the weather in Amsterdam?", session);

List<ToolApprovalRequestContent> approvals = response.Messages
    .SelectMany(m => m.Contents)
    .OfType<ToolApprovalRequestContent>()
    .ToList();

while (approvals.Count > 0)
{
    List<ChatMessage> replies = approvals.ConvertAll(req =>
    {
        var call = (FunctionCallContent)req.ToolCall;
        Console.Write($"Approve {call.Name}? (Y/n): ");
        bool approved = Console.ReadLine()?.Equals("Y", StringComparison.OrdinalIgnoreCase) ?? false;
        return new ChatMessage(ChatRole.User, [req.CreateResponse(approved)]);
    });

    response = await agent.RunAsync(replies, session);
    approvals = response.Messages
        .SelectMany(m => m.Contents)
        .OfType<ToolApprovalRequestContent>()
        .ToList();
}
```

Use cases:
- Any side-effecting tool (sending email, paying, deploying, deleting)
- Tools that touch sensitive PII or external systems
- Audit-critical workflows

For streaming, swap `RunAsync` for `RunStreamingAsync(...).ToListAsync()` and collect approvals from `update.Contents`.

## Per-request tools

Pass tools that should only apply to one call via `ChatClientAgentRunOptions`:

```csharp
var options = new ChatClientAgentRunOptions(new ChatOptions
{
    Tools = [AIFunctionFactory.Create(GetWeather)]
});

var response = await agent.RunAsync("Weather in Seattle?", session, options);
```

Per-request tools merge with constructor-provided tools for that call only.

## Dynamic tool expansion (tool that adds tools)

Use `FunctionInvokingChatClient.CurrentContext` from inside a tool to mutate the live `ChatOptions.Tools` list mid-conversation.

```csharp
AIFunction requestTools = AIFunctionFactory.Create(
    [Description("Request additional tools to be loaded.")]
    ([Description("Category of capability needed (e.g., 'weather', 'time').")] string category) =>
    {
        var context = FunctionInvokingChatClient.CurrentContext
            ?? throw new InvalidOperationException("No ambient FunctionInvocationContext.");

        var tools = context.Options?.Tools;
        if (tools is null) return "Tools list unavailable.";

        if (toolCatalog.TryGetValue(category, out var newTools))
        {
            foreach (var t in newTools)
            {
                if (t is AIFunction fn && !tools.Any(x => x is AIFunction e && e.Name == fn.Name))
                    tools.Add(t);
            }
            return $"Loaded: {string.Join(", ", newTools.OfType<AIFunction>().Select(t => t.Name))}";
        }
        return $"Unknown category '{category}'.";
    },
    name: "RequestTools");

AIAgent agent = chatClient.AsAIAgent(
    instructions: "When you need a capability you don't have, call RequestTools.",
    tools: [requestTools]);
```

This pattern keeps the initial tool surface small (faster, cheaper prompts) and grows it on demand. For LLM-decided dispatch of larger capability units, prefer **agent skills** — see [agent-skills.md](agent-skills.md).

## MCP tools — consuming an MCP server from an agent

MAF agents accept MCP-server tools natively. Use the `ModelContextProtocol` client SDK to connect, list tools, and cast them to `AITool`.

```csharp
using ModelContextProtocol.Client;
using Microsoft.Extensions.AI;
using Microsoft.Agents.AI;

await using var mcpClient = await McpClient.CreateAsync(new StdioClientTransport(new()
{
    Name = "GitHub-MCP",
    Command = "npx",
    Arguments = ["-y", "@modelcontextprotocol/server-github"],
}));

IList<McpClientTool> mcpTools = await mcpClient.ListToolsAsync();

AIAgent agent = chatClient.AsAIAgent(
    instructions: "You answer questions about GitHub repositories.",
    tools: [.. mcpTools.Cast<AITool>()]);

Console.WriteLine(await agent.RunAsync(
    "Summarize the last four commits to microsoft/agent-framework."));
```

Package: `ModelContextProtocol` (client side; not `ModelContextProtocol.Server` which is for building servers).

Transport options:
- **`StdioClientTransport`** — Subprocess via stdin/stdout; works for any local MCP server (Node, .NET, Python).
- **HTTP transport** — For remote MCP servers exposed over Streamable HTTP.

For building MCP **servers**, use the `ModelContextProtocol` server SDK and the `dotnet new mcpserver` template — that's outside the scope of this skill, which only covers *consuming* MCP tools from a MAF agent.

> MCP tools execute over the protocol — higher latency than local `AIFunction` tools, and they fail differently (transport timeouts vs. exceptions). Wrap critical MCP calls with retry middleware (see [middleware.md](middleware.md)).

## Structured output

### Option A — `RunAsync<T>` (the typed path)

```csharp
public sealed class CityInfo
{
    public string? Name { get; set; }
    public string? Country { get; set; }
    public int Population { get; set; }
}

AIAgent agent = chatClient.AsAIAgent(instructions: "You are helpful.");

AgentResponse<CityInfo> response = await agent.RunAsync<CityInfo>("Tell me about Paris.");
CityInfo city = response.Result;
```

The framework generates a JSON schema from `CityInfo` and sets it on the request. Works on any provider with structured-output support.

### Option B — `ChatResponseFormat.ForJsonSchema<T>`

When the agent is constructed once and used for many calls of the same shape:

```csharp
using System.Text.Json;
using Microsoft.Extensions.AI;

AIAgent agent = chatClient.AsAIAgent(new ChatClientAgentOptions
{
    Name = "CityLookup",
    ChatOptions = new()
    {
        Instructions = "You are helpful.",
        ResponseFormat = ChatResponseFormat.ForJsonSchema<CityInfo>()
    }
});

AgentResponse response = await agent.RunAsync("Tell me about Paris.");
CityInfo city = JsonSerializer.Deserialize<CityInfo>(response.Text)!;
```

### Option C — `UseStructuredOutput` middleware

For models / providers that don't natively support structured output, the middleware reshapes the text response into JSON using a separate chat client:

```csharp
IChatClient secondaryClient = chatClient.AsIChatClient();

AIAgent agent = chatClient.AsAIAgent(name: "Helper", instructions: "You are helpful.")
    .AsBuilder()
    .UseStructuredOutput(secondaryClient)
    .Build();

AgentResponse<CityInfo> response = await agent.RunAsync<CityInfo>("Tell me about Paris.");
```

> Validate the deserialized result before using it. Provide a fallback for malformed responses.

## Image / multimodal input

Use `DataContent` to attach an image alongside text. Works with vision-capable models.

```csharp
using Microsoft.Extensions.AI;

var message = new ChatMessage(ChatRole.User,
    [
        new TextContent("What do you see in this image?"),
        await DataContent.LoadFromAsync("Assets/walkway.jpg"),
    ]);

var session = await agent.CreateSessionAsync();
await foreach (var update in agent.RunStreamingAsync(message, session))
{
    Console.Write(update);
}
```

`DataContent.LoadFromAsync` reads the file and infers MIME type from the extension. For remote images, construct `new DataContent(uri, mediaType)`.

## Picking the right tool style

| Style | Best for |
|-------|----------|
| `AIFunctionFactory.Create(method)` | Static or instance methods — most common case |
| `AIFunctionFactory.Create(delegate, name: ...)` | Lambdas or methods whose default name is unclear |
| `ApprovalRequiredAIFunction` | Side-effecting / sensitive tools |
| Per-request `ChatClientAgentRunOptions.ChatOptions.Tools` | Tools that vary per call |
| `FunctionInvokingChatClient.CurrentContext` mutation | Agent should discover tools mid-loop |
| `McpClient.ListToolsAsync()` | Tools provided by an external MCP server |
| **Agent skills** (see [agent-skills.md](agent-skills.md)) | A bundle of instructions + resources + scripts loaded on demand |

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Tool not invoked | Check `[Description]` strings — they're vague or missing |
| Tool invoked with wrong args | Add `[Description]` on parameters; consider tighter parameter types (enums, records) |
| Async tools hang | Accept `CancellationToken` and propagate it; never `.Result` / `.Wait()` |
| MCP tool throws after a long pause | Wrap with timeout + retry middleware; MCP transports fail asynchronously |
| Approval workflow silently auto-approves | Verify you're constructing `ApprovalRequiredAIFunction`, not a plain `AIFunction` |
| Dynamic tool addition doesn't take effect | The new tool only applies to *subsequent* iterations of the same function-calling loop, not the current LLM call |
| Schema generation fails for `RunAsync<T>` | The type must be a POCO with public properties and a public default constructor, or annotated with `[JsonSerializable]` |
| `DataContent` rejects an image | Verify the MIME type was inferred (check extension) and the model supports vision |
| Constructor `tools:` mixed with `ChatClientAgentOptions.ChatOptions.Tools` | The constructor `tools` win for the agent lifetime; per-request tools go on `ChatClientAgentRunOptions`. Pick one. |
