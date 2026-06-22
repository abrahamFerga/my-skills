# Declarative Workflows (and Agents)

Declarative MAF lets you define workflows (and, in the future, agents) in **YAML** instead of C#. The runtime parses the YAML, binds it to Foundry agents and PowerFx expressions, and produces an executable `Workflow`.

## Current state

| Surface | Package | Status |
|---------|---------|--------|
| Declarative **workflows** | `Microsoft.Agents.AI.Workflows.Declarative` | Prerelease (rc) — published to NuGet |
| Declarative **workflows + Foundry binding** | `Microsoft.Agents.AI.Workflows.Declarative.Foundry` | Prerelease — published |
| Declarative **workflows + MCP** | `Microsoft.Agents.AI.Workflows.Declarative.Mcp` | Prerelease — published |
| Declarative **agents** | `Microsoft.Agents.AI.Declarative` | **Not on NuGet** (`IsPackable=false`); source-only |

So today's practical advice: use declarative **workflows** in production, and define **agents in C#** (or via Foundry agent management) for now. If you need declarative agents, build the YAML in your repo and reference the source project until the package ships.

```bash
dotnet add package Microsoft.Agents.AI.Workflows.Declarative --prerelease
```

For Foundry-managed agents referenced by a declarative workflow:

```bash
dotnet add package Microsoft.Agents.AI.Workflows.Declarative.Foundry --prerelease
```

## Workflow YAML — anatomy

From `samples/03-workflows/Declarative/StudentTeacher/MathChat.yaml`:

```yaml
kind: Workflow
trigger:
  kind: OnConversationStart
  id: workflow_demo
  actions:

    - kind: InvokeAzureAgent
      id: question_student
      conversationId: =System.ConversationId
      agent:
        name: StudentAgent

    - kind: InvokeAzureAgent
      id: question_teacher
      conversationId: =System.ConversationId
      agent:
        name: TeacherAgent
      output:
        messages: Local.TeacherResponse

    - kind: SetVariable
      id: set_count_increment
      variable: Local.TurnCount
      value: =Local.TurnCount + 1

    - kind: ConditionGroup
      id: check_completion
      conditions:

        - condition: =!IsBlank(Find("CONGRATULATIONS", Upper(MessageText(Local.TeacherResponse))))
          id: check_turn_done
          actions:
            - kind: SendActivity
              id: sendActivity_done
              activity: GOLD STAR!

        - condition: =Local.TurnCount < 4
          id: check_turn_count
          actions:
            - kind: GotoAction
              id: goto_student_agent
              actionId: question_student

      elseActions:
        - kind: SendActivity
          id: sendActivity_tired
          activity: Let's try again later...
```

Anatomy:

| Field | Meaning |
|-------|---------|
| `kind: Workflow` | Top-level type discriminator |
| `trigger` | What starts the workflow — `OnConversationStart` is the common case |
| `actions` | Ordered list of steps to execute |
| `kind` (on each action) | Action type (`InvokeAzureAgent`, `SetVariable`, `ConditionGroup`, `SendActivity`, `GotoAction`, `CreateConversation`, `EndWorkflow`, etc.) |
| `id` | Step identifier — used by `GotoAction.actionId` |
| `=Expression` | PowerFx expression evaluated at runtime |

## PowerFx expressions

Anything prefixed with `=` is a [PowerFx](https://learn.microsoft.com/power-platform/power-fx/overview) expression evaluated by the workflow runtime's `RecalcEngine`.

Scopes available:
- `Env.VARNAME` — environment variable (resolves through `IConfiguration`)
- `System.ConversationId` — current conversation id
- `Local.<name>` — a variable declared / set within this workflow run

Examples:

```yaml
model:
  id: =Env.AZURE_OPENAI_DEPLOYMENT_NAME

value: =Local.TurnCount + 1
condition: =!IsBlank(Find("CONGRATULATIONS", Upper(MessageText(Local.TeacherResponse))))
```

PowerFx functions like `Upper`, `Find`, `IsBlank`, `MessageText` are standard PowerFx + MAF-specific extensions.

## Loading a workflow in .NET

```csharp
using Microsoft.Agents.AI.Workflows;
using Microsoft.Agents.AI.Workflows.Declarative;
using Microsoft.Extensions.AI;

// Configure options — Foundry endpoint, configuration source, etc.
DeclarativeWorkflowOptions options = new(
    /* set Configuration, AgentProvider, etc. */);

// Load YAML and build the workflow
Workflow workflow = DeclarativeWorkflowBuilder.Build<string>(
    workflowFile: "Marketing.yaml",
    options: options);

// Execute it like any other workflow
await using StreamingRun run = await InProcessExecution.RunStreamingAsync(workflow, "Plan a launch for our new product.");
await run.TrySendMessageAsync(new TurnToken(emitEvents: true));

await foreach (WorkflowEvent evt in run.WatchStreamAsync())
{
    // handle events as usual — see workflows.md
}
```

`DeclarativeWorkflowBuilder.Build<TInput>` overloads accept either a file path or a `TextReader`. The generic `TInput` is what the workflow's root executor will receive (use `string`, `ChatMessage`, or `IEnumerable<ChatMessage>` for most cases).

## Wiring Foundry agents

The `InvokeAzureAgent` action looks up an agent **by name** from an Azure AI Foundry project. The YAML doesn't define the agents — they live in Foundry. Create them once (via the Foundry portal or programmatically with `AIProjectClient`):

```csharp
using Azure.AI.Projects;
using Azure.AI.Projects.Agents;

AIProjectClient client = new(new Uri(foundryEndpoint), new DefaultAzureCredential());

await client.CreateAgentAsync(
    agentName: "AnalystAgent",
    agentDefinition: new DeclarativeAgentDefinition(modelName)
    {
        Instructions = "You are a marketing analyst..."
    },
    agentDescription: "Analyst agent for Marketing workflow");
```

Then the workflow YAML references it:

```yaml
- kind: InvokeAzureAgent
  agent:
    name: AnalystAgent
```

Use the `Microsoft.Agents.AI.Workflows.Declarative.Foundry` package to bind the workflow runtime to a Foundry project.

## Common action kinds

| Kind | Purpose |
|------|---------|
| `InvokeAzureAgent` | Call a Foundry-hosted agent |
| `CreateConversation` | Start a new conversation context |
| `SetVariable` | Assign a `Local.*` variable |
| `ConditionGroup` | Branch on PowerFx conditions |
| `SendActivity` | Send a message to the user |
| `GotoAction` | Jump to a previously-defined action (loops, retries) |
| `EndWorkflow` | Terminate the workflow |
| `InvokeFunctionTool` | Call a registered C# function |
| `InvokeMcpTool` | Call an MCP tool — requires `Workflows.Declarative.Mcp` |
| `InvokeHttpRequest` | Make an HTTP call |
| `ExecuteCode` | Execute a code block (sandboxed via Hyperlight, depending on config) |

See `samples/03-workflows/Declarative/` for one sample per action kind.

## Common patterns

### Sequential agents

```yaml
trigger:
  kind: OnConversationStart
  actions:
    - kind: InvokeAzureAgent
      agent: { name: AnalystAgent }
      output: { messages: Local.Analysis }
    - kind: InvokeAzureAgent
      agent: { name: WriterAgent }
      input: { messages: Local.Analysis }
      output: { messages: Local.Draft }
    - kind: InvokeAzureAgent
      agent: { name: EditorAgent }
      input: { messages: Local.Draft }
```

### Looping with condition

```yaml
- kind: ConditionGroup
  conditions:
    - condition: =Local.TurnCount < 5
      actions:
        - kind: GotoAction
          actionId: invoke_analyst
  elseActions:
    - kind: EndWorkflow
```

### HTTP tool call

```yaml
- kind: InvokeHttpRequest
  url: =Env.API_BASE_URL & "/search?q=" & EncodeUrl(Local.Query)
  method: GET
  headers:
    Authorization: =Concat("Bearer ", Env.API_TOKEN)
  output: { responseObject: Local.ApiResponse }
```

## Declarative agents — YAML format (not yet on NuGet)

The repo defines a YAML format for agents in `declarative-agents/`. The runtime is `Microsoft.Agents.AI.Declarative` which is **`IsPackable=false`** — to use it today you'd need to consume it as a project reference from a local clone of the agent-framework repo.

Format preview (from `declarative-agents/agent-samples/chatclient/GetWeather.yaml`):

```yaml
kind: Prompt
name: Assistant
description: Helpful assistant
instructions: You are a helpful assistant. You answer questions using the tools provided.
model:
  options:
    temperature: 0.9
    topP: 0.95
    allowMultipleToolCalls: true
    chatToolMode: auto
tools:
  - kind: function
    name: GetWeather
    description: Get the weather for a given location.
    bindings:
      get_weather: get_weather
    parameters:
      properties:
        location:
          kind: string
          description: The city and state.
          required: true
```

If/when published, the loader is:

```csharp
var agentFactory = new ChatClientPromptAgentFactory(chatClient, [AIFunctionFactory.Create(GetWeather, "GetWeather")]);
AIAgent agent = await agentFactory.CreateFromYamlAsync(File.ReadAllText("Assistant.yaml"));
```

**Recommendation for now:** define agents in C# (`ChatClientAgent` / `AsAIAgent`) and reference them by name from declarative workflows.

## When to use declarative

| Choose declarative | Choose code |
|--------------------|-------------|
| Workflow shape changes more often than code | Workflow is part of the app's core logic |
| Non-developers (analysts, ops) need to author / tweak workflows | Authors are .NET developers |
| Workflows are tenant-customizable at runtime | Workflows are fixed at build time |
| The workflow consists mostly of Foundry agent calls + simple branching | The workflow has rich C#-specific logic |

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Referenced `Microsoft.Agents.AI.Declarative` package not found on NuGet | Correct — it's `IsPackable=false`. Use C# for agents and reference them by name from YAML. |
| Workflow YAML compiles but agent doesn't run | Confirm the Foundry agent exists by that exact name in the project (`InvokeAzureAgent.agent.name`) |
| PowerFx expression doesn't resolve env var | Confirm `IConfiguration` is bound on `DeclarativeWorkflowOptions` and the env var name matches exactly |
| Infinite loop on `GotoAction` | Add a `Local.TurnCount` and a `ConditionGroup` check to terminate |
| Workflow input type doesn't match | The root executor accepts `TInput`, `ChatMessage`, `IEnumerable<ChatMessage>`, `string`, and `TurnToken`. Pick the type matching your invocation. |
| MCP tool action not recognized | Add the `Microsoft.Agents.AI.Workflows.Declarative.Mcp` package and register its handler |
