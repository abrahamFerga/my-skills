# Multi-Agent Workflows

Use **`Microsoft.Agents.AI.Workflows`** (stable, 1.6.x) when one agent isn't enough — fan-out / fan-in across specialists, sequential pipelines, handoff routing, group chat, human-in-the-loop pauses, conditional branching, checkpoints, loops, and shared state.

Workflows are graphs of executors (agents or plain functions) connected by edges; the framework drives messages through them.

```bash
dotnet add package Microsoft.Agents.AI.Workflows
```

## When to use a workflow vs. a single agent

| Use a single agent (`ChatClientAgent`) | Use a `Workflow` |
|----------------------------------------|------------------|
| One LLM, possibly with tools | Multiple LLMs with different roles |
| Linear conversation | Parallel, branching, looping, or HITL-gated control flow |
| All logic fits in one set of instructions | Specialists need isolated instructions |
| No durable checkpointing needed | You need pause / resume / replay |

**Don't reach for workflows reflexively** — a single agent with tools handles many cases that look multi-agent on paper. Workflows shine when specialists have **conflicting instructions** or work needs to **fan out**.

## Pattern 1: Sequential pipeline

```csharp
using Microsoft.Agents.AI;
using Microsoft.Agents.AI.Workflows;

ChatClientAgent translator = new(chatClient, "Translate the input into French.");
ChatClientAgent summarizer = new(chatClient, "Summarize the input into one sentence.");
ChatClientAgent toneAdjuster = new(chatClient, "Rewrite in a friendly, casual tone.");

Workflow workflow = AgentWorkflowBuilder.BuildSequential(
    workflowName: "translate-summarize-tone",
    translator, summarizer, toneAdjuster);
```

## Pattern 2: Concurrent fan-out

```csharp
ChatClientAgent sentiment = new(chatClient, "Classify the sentiment.");
ChatClientAgent topics = new(chatClient, "Extract topic tags.");
ChatClientAgent entities = new(chatClient, "Extract named entities.");

Workflow workflow = AgentWorkflowBuilder.BuildConcurrent(
    workflowName: "parallel-analysis",
    agents: [sentiment, topics, entities],
    aggregator: results =>
    {
        var combined = new List<ChatMessage>();
        foreach (var perAgent in results) combined.AddRange(perAgent);
        return combined;
    });
```

When `aggregator` is omitted, the workflow returns the last message from each agent.

## Pattern 3: Handoff (triage → specialists)

```csharp
ChatClientAgent historyTutor = new(chatClient,
    instructions: "Help with history. Only respond about history.",
    name: "history_tutor",
    description: "Specialist for historical questions");

ChatClientAgent mathTutor = new(chatClient,
    instructions: "Help with math. Show reasoning.",
    name: "math_tutor",
    description: "Specialist for math questions");

ChatClientAgent triage = new(chatClient,
    instructions: "Pick a specialist for the question. ALWAYS hand off.",
    name: "triage_agent",
    description: "Routes messages to specialists.");

Workflow workflow = AgentWorkflowBuilder.CreateHandoffBuilderWith(triage)
    .WithHandoffs(triage, [mathTutor, historyTutor])     // triage → either specialist
    .WithHandoffs([mathTutor, historyTutor], triage)     // specialist → triage (for new questions)
    .Build();
```

> Agent `description` is what the routing LLM reads to decide handoffs. Be specific.

## Pattern 4: Group chat

```csharp
Workflow workflow = AgentWorkflowBuilder
    .CreateGroupChatBuilderWith(agents =>
        new RoundRobinGroupChatManager(agents) { MaximumIterationCount = 5 })
    .AddParticipants(translatorEn, translatorFr, translatorEs)
    .WithName("translation-roundrobin")
    .Build();
```

`MaximumIterationCount` is your hard cap — **always set it** to prevent runaway loops. Swap `RoundRobinGroupChatManager` for a custom manager to implement moderated turn-taking (e.g., LLM-selected next speaker).

## Pattern 5: Human-in-the-loop (HITL) — `RequestPort`

When the workflow needs external input mid-flight (a user clicking approve, an out-of-band system response):

```csharp
RequestPort numberRequestPort = RequestPort.Create<NumberSignal, int>("GuessNumber");
JudgeExecutor judgeExecutor = new(targetNumber: 42);

Workflow workflow = new WorkflowBuilder(numberRequestPort)
    .AddEdge(numberRequestPort, judgeExecutor)
    .AddEdge(judgeExecutor, numberRequestPort)
    .WithOutputFrom(judgeExecutor)
    .Build();
```

Execution loop handles the `RequestInfoEvent`:

```csharp
await using StreamingRun run = await InProcessExecution.RunStreamingAsync(workflow, NumberSignal.Init);

await foreach (WorkflowEvent evt in run.WatchStreamAsync())
{
    switch (evt)
    {
        case RequestInfoEvent requestEvt:
            // Ask the human / external system
            ExternalResponse response = HandleExternalRequest(requestEvt.Request);
            await run.SendResponseAsync(response);
            break;
        case WorkflowOutputEvent done:
            Console.WriteLine(done.As<string>());
            return;
    }
}
```

For agent-tool-approval HITL in group chat, see Pattern 9 below.

## Pattern 6: Conditional edges

```csharp
Workflow workflow = new WorkflowBuilder(spamDetector)
    .AddEdge(spamDetector, mailAssistant, condition: r => r is DetectionResult x && !x.IsSpam)
    .AddEdge(spamDetector, spamHandler,   condition: r => r is DetectionResult x &&  x.IsSpam)
    .AddEdge(mailAssistant, mailSender)
    .WithOutputFrom(spamHandler, mailSender)
    .Build();
```

`AddEdge<T>(source, target, condition: Func<T?, bool>)` only forwards messages matching the predicate. Multiple conditional edges from the same source create branches.

## Pattern 7: Checkpoints (persist & resume)

```csharp
var checkpointManager = CheckpointManager.Default;
var checkpoints = new List<CheckpointInfo>();

await using StreamingRun run = await InProcessExecution
    .RunStreamingAsync(workflow, input, checkpointManager);

await foreach (WorkflowEvent evt in run.WatchStreamAsync())
{
    if (evt is SuperStepCompletedEvent superStep && superStep.CompletionInfo?.Checkpoint is CheckpointInfo cp)
    {
        checkpoints.Add(cp);
    }
}

// Later — restore and continue:
await run.RestoreCheckpointAsync(checkpoints[5], CancellationToken.None);
```

Executor state survives across checkpoints by implementing the lifecycle hooks:

```csharp
protected override ValueTask OnCheckpointingAsync(
    IWorkflowContext context, CancellationToken cancellationToken = default) =>
    context.QueueStateUpdateAsync("bounds", (LowerBound, UpperBound), cancellationToken: cancellationToken);

protected override async ValueTask OnCheckpointRestoredAsync(
    IWorkflowContext context, CancellationToken cancellationToken = default) =>
    (LowerBound, UpperBound) = await context.ReadStateAsync<(int, int)>("bounds", cancellationToken: cancellationToken);
```

`CheckpointManager.Default` is in-memory. For durable workflows that survive process restarts, see `Microsoft.Agents.AI.DurableTask` (prerelease) — built on the Durable Task Framework.

## Pattern 8: Shared state + fan-out/fan-in

Executors exchange data via a scoped key-value store on `IWorkflowContext`:

```csharp
// Producer
public override async ValueTask<string> HandleAsync(string message, IWorkflowContext context, CancellationToken ct)
{
    string fileId = Guid.NewGuid().ToString("N");
    string content = await ReadFileAsync(message, ct);
    await context.QueueStateUpdateAsync(fileId, content, scopeName: "FileContent", ct);
    return fileId;
}

// Consumer (one of N parallel workers)
public override async ValueTask<Stats> HandleAsync(string fileId, IWorkflowContext context, CancellationToken ct)
{
    var content = await context.ReadStateAsync<string>(fileId, scopeName: "FileContent", ct)
        ?? throw new InvalidOperationException("File content not found.");
    return new Stats { WordCount = content.Split(' ').Length };
}
```

Fan-out / fan-in edges:

```csharp
Workflow workflow = new WorkflowBuilder(fileRead)
    .AddFanOutEdge(fileRead, [wordCount, paragraphCount, sentenceCount])
    .AddFanInBarrierEdge([wordCount, paragraphCount, sentenceCount], aggregate)
    .WithOutputFrom(aggregate)
    .Build();
```

`AddFanInBarrierEdge` waits for **all** sources to emit before firing the target.

`IWorkflowContext` state API:

```csharp
ValueTask<T?> ReadStateAsync<T>(string key, string? scopeName = null, CancellationToken ct = default);
ValueTask<T> ReadOrInitStateAsync<T>(string key, Func<T> init, string? scopeName = null, CancellationToken ct = default);
ValueTask QueueStateUpdateAsync<T>(string key, T? value, string? scopeName = null, CancellationToken ct = default);
ValueTask<HashSet<string>> ReadStateKeysAsync(string? scopeName = null, CancellationToken ct = default);
ValueTask QueueClearScopeAsync(string? scopeName = null, CancellationToken ct = default);
```

## Pattern 9: Group chat with tool approval

Combine group chat with `ApprovalRequiredAIFunction` for HITL gating of side-effecting tools:

```csharp
ChatClientAgent devops = new(chatClient,
    instructions: "...",
    name: "DevOpsEngineer",
    description: "Handles deployments",
    tools: [
        AIFunctionFactory.Create(CheckStagingStatus),
        new ApprovalRequiredAIFunction(AIFunctionFactory.Create(DeployToProduction))
    ]);

DeploymentGroupChatManager manager = new([qa, devops]) { MaximumIterationCount = 4 };
Workflow workflow = AgentWorkflowBuilder
    .CreateGroupChatBuilderWith(_ => manager)
    .AddParticipants(qa, devops)
    .Build();

await using StreamingRun run = await InProcessExecution.Lockstep
    .RunStreamingAsync(workflow, initialMessages);

await foreach (WorkflowEvent evt in run.WatchStreamAsync())
{
    if (evt is RequestInfoEvent e &&
        e.Request.TryGetDataAs(out ToolApprovalRequestContent? approval))
    {
        bool approved = AskUserAsync(approval).Result;
        await run.SendResponseAsync(
            e.Request.CreateResponse(approval.CreateResponse(approved)));
    }
}
```

`InProcessExecution.Lockstep` runs the workflow one super-step at a time, making HITL ergonomic.

## Pattern 10: Loops

Cyclic edges are first-class. Connect a downstream executor back to an upstream one:

```csharp
Workflow workflow = new WorkflowBuilder(guesser)
    .AddEdge(guesser, judge)
    .AddEdge(judge, guesser)            // loop back
    .WithOutputFrom(judge)
    .Build();
```

The loop terminates when an executor yields output (`context.YieldOutputAsync(...)`) or requests halt (`context.RequestHaltAsync(...)`).

## Pattern 11: Workflow as an agent

Encapsulate an entire workflow behind the `AIAgent` interface — composable, swappable, and consumable anywhere an agent is expected (including nested in another workflow):

```csharp
AIAgent compositeAgent = workflow.AsAIAgent(
    name: "research-pipeline",
    description: "Multi-step research workflow");

AgentSession session = await compositeAgent.CreateSessionAsync();
await foreach (var update in compositeAgent.RunStreamingAsync(prompt, session))
{
    Console.Write(update);
}
```

For workflows with **stateful executors** that you intend to reuse, implement `IResettableExecutor`:

```csharp
private sealed class AggregateExecutor : Executor<List<ChatMessage>>("aggregate"), IResettableExecutor
{
    private readonly List<ChatMessage> _buffer = [];
    public override ValueTask HandleAsync(...) { _buffer.AddRange(message); ... }
    public ValueTask ResetAsync() { _buffer.Clear(); return default; }
}
```

The framework calls `ResetAsync()` between runs.

## Custom executors

For non-agent steps (parse, fetch, transform), subclass `Executor<TIn, TOut>`:

```csharp
internal sealed class UpperCaseExecutor() : Executor<string, string>("uppercase")
{
    public override ValueTask<string> HandleAsync(
        string message, IWorkflowContext context, CancellationToken cancellationToken = default)
        => ValueTask.FromResult(message.ToUpperInvariant());
}
```

Or bind a function as an executor:

```csharp
Func<string, string> trim = s => s.Trim();
ExecutorBinding trimExec = trim.BindAsExecutor("trim");
```

## Visualization

```csharp
string mermaid = workflow.ToMermaidString();   // pastes into Markdown
string dot = workflow.ToDotString();           // pipe into `dot -Tsvg`
```

Use these for design reviews and debugging — they faithfully represent the executor graph including conditional edges and fan-outs.

## Observability for workflows

```csharp
Workflow workflow = new WorkflowBuilder(upper)
    .AddEdge(upper, reverse)
    .WithOpenTelemetry(
        configure: cfg => cfg.EnableSensitiveData = false,
        activitySource: myActivitySource)
    .Build();
```

Register `"Microsoft.Agents.AI.Workflows*"` as an `AddSource` on the tracer provider. Each executor produces a span. Combine with agent-level OpenTelemetry — see [hosting-and-observability.md](hosting-and-observability.md).

## Executing a workflow

### One-shot

```csharp
await using Run run = await InProcessExecution.RunAsync(
    workflow,
    input: new List<ChatMessage> { new(ChatRole.User, "Hello") });

foreach (WorkflowEvent evt in run.NewEvents)
{
    if (evt is WorkflowOutputEvent output)
    {
        var messages = output.As<List<ChatMessage>>();
    }
}
```

### Streaming (preferred for user-facing workflows)

```csharp
await using StreamingRun run = await InProcessExecution.RunStreamingAsync(workflow, messages);
await run.TrySendMessageAsync(new TurnToken(emitEvents: true));

await foreach (WorkflowEvent evt in run.WatchStreamAsync())
{
    switch (evt)
    {
        case AgentResponseUpdateEvent e:
            Console.Write(e.Update.Text);
            break;
        case WorkflowOutputEvent output:
            return output.As<List<ChatMessage>>()!;
        case ExecutorFailedEvent failed:
            Console.Error.WriteLine($"Executor {failed.ExecutorId} failed: {failed.Data}");
            break;
        case WorkflowErrorEvent err:
            Console.Error.WriteLine(err.Exception?.ToString());
            break;
    }
}
```

## Events you'll observe

| Event | Meaning |
|-------|---------|
| `AgentResponseUpdateEvent` | A token / chunk from an agent (streaming) — has `ExecutorId` + `Update` |
| `ExecutorCompletedEvent` | An executor produced its final output |
| `ExecutorFailedEvent` | An executor threw |
| `RequestInfoEvent` | A `RequestPort` is requesting external input — respond via `run.SendResponseAsync` |
| `SuperStepCompletedEvent` | One super-step done — checkpoint may be available via `.CompletionInfo.Checkpoint` |
| `WorkflowOutputEvent` | The workflow finished — final payload in `.As<T>()` |
| `WorkflowErrorEvent` | Fatal workflow error |

## Workflow guardrails

1. **Iteration caps** on group chat / loops — `MaximumIterationCount` or equivalent.
2. **Per-executor timeouts** — wrap LLM-calling executors in chat-client middleware with a timeout.
3. **Error handling** — observe `ExecutorFailedEvent` / `WorkflowErrorEvent`; don't silently `continue`.
4. **Token budget** — concurrent fan-out multiplies cost. Estimate before scaling.
5. **Observability** — `.WithOpenTelemetry(...)` and matching trace sources.
6. **Idempotency for replays** — checkpointed executors can re-run on the same input; design accordingly.

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| Group chat never terminates | Set `MaximumIterationCount`; implement a stop condition in the chat manager |
| Concurrent workflow blows budget | Cap agent count; estimate tokens before scaling fan-out |
| Handoff loops between specialist and triage | Add a hop counter or terminate after N handoffs |
| Lost output because event loop ignores `WorkflowErrorEvent` | Always handle error events explicitly |
| Workflow output cast fails | Sequential / concurrent default to `List<ChatMessage>` — use `output.As<List<ChatMessage>>()` |
| Tried to inject middleware "on the workflow" | Middleware attaches to individual agents inside the workflow. Build wrapped agents first, then pass to `AgentWorkflowBuilder`. |
| Treated `Workflow` like an `AIAgent` | Different types — use `workflow.AsAIAgent()` if you need an agent surface |
| Stateful executor reused across runs without reset | Implement `IResettableExecutor` |
| HITL pause doesn't fire | Confirm the workflow has a `RequestPort` and the streaming loop dispatches on `RequestInfoEvent` |
| Checkpoint restoration loses state | Implement `OnCheckpointingAsync` / `OnCheckpointRestoredAsync` on every stateful executor |
| Shared-state key collisions | Use distinct `scopeName` strings per logical group (`"FileContent"`, `"UserPrefs"`) — don't rely on the default scope |
