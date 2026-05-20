# Agent Skills

**Agent Skills** are MAF's packaging unit for domain-specific capabilities. A skill bundles **instructions + reference resources + executable scripts** together. The framework loads them via the **progressive-disclosure pattern**: only the skill's name and short description are in the prompt by default; the agent calls `load_skill` to retrieve the full body, then `read_skill_resource` / `run_skill_script` on demand.

This is the MAF implementation of the [Agent Skills specification](https://agentskills.io/) — the same standard the .NET skills repo follows.

## When to use a skill vs. a plain tool

| Use a tool (`AIFunctionFactory.Create`) | Use a skill |
|----------------------------------------|-------------|
| One function with parameters | A coherent capability with multiple steps |
| The LLM should always see it in the schema | The LLM should *discover* it by name and load on demand |
| No reference data needed | The capability has lookup tables, policies, examples |
| Stateless | Bundles instructions, data files, and executable scripts |
| Token cost of always-present tool is fine | You have many capabilities and want them loaded only when relevant |

Skills shine when you have **many capabilities** that would bloat the prompt if all their tools were always present. The advertise → load → read/run loop keeps the default prompt small.

## Experimental attribute warning

`AgentSkillsProvider` (and friends) carry `[Experimental(...)]` markers. Suppress the warning project-wide:

```xml
<PropertyGroup>
  <NoWarn>$(NoWarn);MEAI001;AGENTS001</NoWarn>
</PropertyGroup>
```

Or per file:

```csharp
#pragma warning disable MEAI001, AGENTS001
```

(Use the exact diagnostic IDs the compiler emits — `MEAI001` is the most common; the agent-specific code may vary by version.)

## Three styles of defining a skill

### 1. File-based skills (`SKILL.md` on disk)

**Directory layout** (in `samples/02-agents/AgentSkills/Agent_Step01_FileBasedSkills/skills/`):

```
skills/
  unit-converter/
    SKILL.md                         (required; frontmatter + body)
    references/                      (resources — default name; configurable)
      conversion-table.md
    scripts/                         (scripts — default name; configurable)
      convert.py
```

**SKILL.md format:**

```markdown
---
name: unit-converter
description: Convert between common units using a multiplication factor. Use when asked to convert miles, kilometers, pounds, or kilograms.
---

## Usage

When the user requests a unit conversion:
1. Review `references/conversion-table.md` to find the factor.
2. Run `scripts/convert.py --value <number> --factor <factor>`.
3. Present the converted value with both units.
```

Frontmatter:

| Field | Required | Notes |
|-------|----------|-------|
| `name` | Yes | Kebab-case; must match the parent directory name exactly |
| `description` | Yes | 1024 chars max; this is what the LLM sees during advertise |
| `license` | No | License identifier / reference |
| `compatibility` | No | Version / platform constraints (max 500 chars) |
| `allowed-tools` | No | Space-delimited list of pre-approved tools |
| `metadata` | No | Arbitrary key-value pairs |

**Wiring:**

```csharp
using Microsoft.Agents.AI;

var skillsProvider = new AgentSkillsProvider(
    skillPath: Path.Combine(AppContext.BaseDirectory, "skills"),
    scriptRunner: SubprocessScriptRunner.RunAsync);

AIAgent agent = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential())
    .GetResponsesClient()
    .AsAIAgent(new ChatClientAgentOptions
    {
        Name = "UnitConverterAgent",
        ChatOptions = new() { Instructions = "You are a helpful assistant." },
        AIContextProviders = [skillsProvider],
    },
    model: deploymentName);
```

**Script runner:** `SubprocessScriptRunner.RunAsync` (from the sample, copyable) spawns subprocesses by file extension — `.py` → `python3`, `.js` → `node`, `.sh` → `bash`, `.ps1` → `pwsh`. Working directory is the script's parent; cancellation kills the process tree; output is captured stdout/stderr.

> The framework does not ship a sandbox. Treat skill scripts as full subprocess execution with the host's privileges. For untrusted skills, run them under Hyperlight or another sandbox (`Microsoft.Agents.AI.Hyperlight`).

### 2. Code-defined skills (`AgentInlineSkill`)

Fluent builder for in-process skills. No file system, no subprocesses — scripts and resources are C# delegates.

```csharp
using Microsoft.Agents.AI;
using System.Text.Json;

var unitConverter = new AgentInlineSkill(
    name: "unit-converter",
    description: "Convert between common units using a multiplication factor.",
    instructions: """
        Use this skill when the user asks to convert between units.
        1. Review the conversion-table resource to find the factor.
        2. Use the convert script, passing the value and factor.
        """)
    .AddResource(
        "conversion-table",
        """
        # Conversion Tables
        Formula: **result = value × factor**
        | From       | To         | Factor   |
        |------------|------------|----------|
        | miles      | kilometers | 1.60934  |
        | kilometers | miles      | 0.621371 |
        """)
    .AddResource("conversion-policy", () =>
        $"# Conversion Policy\nDecimal places: 4\nGenerated at: {DateTime.UtcNow:O}")
    .AddScript("convert", (double value, double factor) =>
    {
        double result = Math.Round(value * factor, 4);
        return JsonSerializer.Serialize(new { value, factor, result });
    });

var skillsProvider = new AgentSkillsProvider(unitConverter);

AIAgent agent = chatClient.AsAIAgent(new ChatClientAgentOptions
{
    AIContextProviders = [skillsProvider]
});
```

API:

- `AddResource(name, string value, description? = null)` — static text resource
- `AddResource(name, Delegate factory, description? = null)` — dynamic resource (invoked each read)
- `AddScript(name, Delegate impl, description? = null)` — code script; parameters and return values marshal through JSON

> All `AddResource` / `AddScript` calls must happen **before** the skill's content is first accessed. After that, additions are not reflected.

### 3. Class-based skills (`AgentClassSkill<TSelf>`)

CRTP-based pattern with attribute discovery — the cleanest option for non-trivial reusable skills. Native AOT compatible.

```csharp
using System.ComponentModel;
using System.Text.Json;
using Microsoft.Agents.AI;

internal sealed class UnitConverterSkill : AgentClassSkill<UnitConverterSkill>
{
    public override AgentSkillFrontmatter Frontmatter { get; } = new(
        "unit-converter",
        "Convert between common units using a multiplication factor.");

    protected override string Instructions => """
        Use this skill when the user asks to convert between units.
        1. Review the conversion-table resource.
        2. Use the convert script.
        """;

    [AgentSkillResource("conversion-table")]
    [Description("Lookup table of multiplication factors.")]
    public string ConversionTable => """
        Formula: result = value × factor
        miles → kilometers: 1.60934
        kilograms → pounds: 2.20462
        """;

    [AgentSkillScript("convert")]
    [Description("Multiplies a value by a conversion factor.")]
    private static string ConvertUnits(double value, double factor)
        => JsonSerializer.Serialize(new { value, factor, result = Math.Round(value * factor, 4) });
}

// Wiring:
var skillsProvider = new AgentSkillsProvider(new UnitConverterSkill());
AIAgent agent = chatClient.AsAIAgent(new ChatClientAgentOptions
{
    AIContextProviders = [skillsProvider]
});
```

Discovery:
- `[AgentSkillResource("name")]` on a property or method (instance or static) — value is the resource content
- `[AgentSkillScript("name")]` on a method — method body is the script
- `[Description(...)]` provides the resource/script description shown to the LLM
- For AOT, override `Resources` and `Scripts` properties manually with `CreateResource(...)` / `CreateScript(...)` instead of relying on reflection

## Mixing styles & multi-source skills

`AgentSkillsProviderBuilder` composes multiple sources:

```csharp
var skillsProvider = new AgentSkillsProviderBuilder()
    .UseFileSkills("/opt/myapp/skills", scriptRunner: SubprocessScriptRunner.RunAsync)
    .UseSkills(myInlineSkill1, myInlineSkill2)
    .UseSkill(new UnitConverterSkill())
    .UseScriptApproval(true)              // wrap run_skill_script with ApprovalRequiredAIFunction
    .UseFilter(skill => skill.Frontmatter.Name.StartsWith("approved-"))  // gating
    .UsePromptTemplate(customTemplate)    // override how skills are advertised
    .Build();
```

Duplicate skill names are deduplicated (first occurrence wins).

## Approval gate on scripts

For skills with side effects, gate every `run_skill_script` call:

```csharp
var skillsProvider = new AgentSkillsProviderBuilder()
    .UseFileSkills(skillPath, SubprocessScriptRunner.RunAsync)
    .UseScriptApproval(true)
    .Build();
```

The agent then emits `ToolApprovalRequestContent` for each script call, which you handle the same way as for `ApprovalRequiredAIFunction` (see [tools.md](tools.md#approval-gated-human-in-the-loop-tools)).

## How the LLM uses skills (the loop)

The provider injects three tools into the agent at runtime:

| Tool | What it does |
|------|--------------|
| `load_skill(name)` | Returns the full instructions for the named skill |
| `read_skill_resource(skillName, resourceName)` | Returns a named resource's contents |
| `run_skill_script(skillName, scriptName, arguments)` | Executes a script and returns its output |

In addition, the system prompt is augmented with an `<available_skills>` block listing each skill's name and description. The LLM decides whether to call `load_skill` based on these descriptions — write them like search queries for the LLM to match against user intent.

## Resource and script naming

- Use kebab-case (`conversion-table`, not `ConversionTable`)
- Keep names short and intent-bearing — the LLM passes them as string arguments
- Use `[Description]` on resources/scripts to give the LLM a hint without forcing it to read the content

## DI in class-based skills

Class-based skills can accept DI services in their script methods:

```csharp
[AgentSkillScript("fetch")]
public async Task<string> FetchAsync(string url, IServiceProvider services, CancellationToken cancellationToken)
{
    var httpClient = services.GetRequiredService<HttpClient>();
    return await httpClient.GetStringAsync(url, cancellationToken);
}
```

The `IServiceProvider` parameter is auto-injected from the agent's services (passed via `ChatClientAgent`'s constructor).

## Picking a style

| Style | Best for |
|-------|----------|
| **File-based** | Skills authored by non-developers; on-disk reuse across projects; ship-with-app skills |
| **Inline (`AgentInlineSkill`)** | Quick prototyping; small dynamic skills; skills generated at startup from config |
| **Class-based (`AgentClassSkill<T>`)** | Production skills; testability; AOT; richer integration with the host (DI, services) |

## Common pitfalls

| Pitfall | Solution |
|---------|----------|
| `name` in frontmatter doesn't match the directory name | The provider rejects the skill silently. Use kebab-case for both and keep them identical. |
| Script runs but the agent never seems to call it | Description is vague — rewrite as "Use this skill when X..." with explicit triggers |
| Subprocess scripts hang | They inherit no stdin; ensure scripts don't read from stdin. Cancellation kills the process tree — propagate `CancellationToken`. |
| Built-in `SubprocessScriptRunner` runs untrusted code | It's not sandboxed. Gate with `UseScriptApproval(true)` or run scripts in Hyperlight (`Microsoft.Agents.AI.Hyperlight`) for untrusted skills. |
| `AddResource` / `AddScript` calls after first use don't take effect | `AgentInlineSkill` freezes its content on first access. Build the skill before passing to `AgentSkillsProvider`. |
| Class-based reflection breaks under AOT | Override `Resources` and `Scripts` manually with `CreateResource(...)` / `CreateScript(...)` instead of using `[AgentSkillResource]` / `[AgentSkillScript]` |
| The agent loads everything always | Your skills list is too small or descriptions overlap. With one or two skills, the LLM may just always load them — skills are only useful when you have many of them. |
| Confusing this with the dotnet/skills marketplace concept | Both follow the same `agentskills.io` spec for the file format, but MAF *consumes* skills at runtime; the marketplace *distributes* them to developer agents. |
