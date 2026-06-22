---
name: pluggable-connectors
description: >
  Implement the pluggable-connector pattern in a generated system so users can install or
  remove integrations (Slack, Teams, email, CRM, calendar) on demand without breaking the
  rest of the system. Installs an Infrastructure.Connectors contracts project, a config-driven
  ConnectorRegistry, a `/api/connectors` endpoint group, a Dashboard "Integrations" page, and
  MAF tool registration for channel connectors — plus the `connector.json` folder contract each
  connector ships.
  USE FOR: a generated system that needs channel-style integrations (chat/email/SMS) or
  third-party data integrations (CRM/billing/calendar) the user expects to compose; authoring
  or reviewing a connector folder; adding the registry/endpoint/dashboard surface for connectors.
  DO NOT USE FOR: the .NET backbone itself (use ../dotnet-aspire-base/SKILL.md); declaring which
  connectors are installed (that lives in workflow config, not here); implementing a specific
  connector's runtime logic (lives in that connector's `dotnet/` folder, not in this pattern).
license: MIT
disable-model-invocation: true
---

# pluggable-connectors

The pattern that lets a generated system grow integrations after the fact. Inspired by [OpenClaw](https://github.com/openclaw/openclaw), where channels and skills are installed on demand. The same pattern handles:

- **Channels** — Slack, Microsoft Teams, WhatsApp, Discord, Telegram, Signal, iMessage, email, SMS (anything the chatbot can speak through)
- **Integrations** — Salesforce, HubSpot, Stripe, Google Calendar, Outlook (anything the system reads from or writes to)

## Approach

Work as a staff-level system architect: pragmatic, decisive, willing to write things down. The whole point of this pattern is that a second, third, or tenth connector is a *finite addition*, not a rewrite — so partition cleanly behind contracts and refuse premature abstraction. Three similar connectors is not yet a framework; the contracts you define here (`IConnector`, `IChannel`, `IIntegration`) are the only coupling allowed. Boring technology when it fits — the registry is config-driven discovery, not a plugin DSL. When you deviate from the pattern, write the ADR then, not later.

## When to use

- A generated system needs channel-style integrations or third-party data integrations the user expects to compose on demand
- Authoring or reviewing a connector folder (the `connector.json` + `dotnet/` companion)
- Adding the registry / endpoint / dashboard surface that makes connectors installable

## When NOT to use

- The .NET backbone itself → use [../dotnet-aspire-base/SKILL.md](../dotnet-aspire-base/SKILL.md). This pattern mounts onto that backbone.
- Declaring *which* connectors are installed → that's workflow configuration, not this pattern.
- A specific connector's runtime logic → lives in that connector's `dotnet/` folder, copied in at install; not in this pattern.

## What this skill installs

When a generated system adopts this pattern, the following appears:

1. **`Infrastructure.Connectors/` project** containing:
   - `IConnector` — base contract (lifecycle: `RegisterAsync`, `ValidateAsync`, capabilities)
   - `IChannel : IConnector` — for channel-style connectors (send message, receive webhook)
   - `IIntegration : IConnector` — for data-integration connectors (sync, query)
   - `ConnectorRegistry` — discovers installed connectors at startup
2. **`connectors.config.json`** at the system root — the source of truth for which connectors are installed and their per-tenant config. Validated against `IOptions<ConnectorsOptions>` at startup.
3. **`ConnectorEndpointsExtensions`** — a minimal API endpoint group exposing `/api/connectors`, `/api/connectors/{name}/health`, and per-connector webhook endpoints.
4. **Dashboard "Integrations" page** — lists installed connectors, per-tenant config UI, connect/disconnect actions.
5. **MAF tool registration** — for each installed channel, a MAF tool the industry chatbot can call to send messages.

## Steps

1. **Verify [../dotnet-aspire-base/SKILL.md](../dotnet-aspire-base/SKILL.md) and a MAF agents setup are in place.** This pattern depends on both.
2. **Create `Infrastructure.Connectors/`** with the contracts above. Reference it from `Application` and `Api`.
3. **Add the `ConnectorRegistry` to DI** in `Program.cs`: it scans `Infrastructure.<Connector>` projects (added when a connector is installed) and registers each one.
4. **Create `connectors.config.json`** with an empty `installed: []` array. Bind to `ConnectorsOptions` via the `IOptions<T>` pattern.
5. **Add the endpoint group** for the connector API surface.
6. **Add the Dashboard page** under `web/src/pages/integrations/`. Use the shared `DataTable` and shadcn `Form`.
7. **Register MAF tools** for the `IChannel` contract — the chatbot agent should receive a `send_message_via(channel, ...)` tool that fans out across whatever channels are installed.

## Output: the connector folder contract

When a connector is declared in the workflow's connector list and installation runs, the installing skill copies the folder from `connectors/<name>/` into the target system. The folder is **pure data on disk** — no script in it executes at install time; setup logic lives in the generated `DependencyInjection.cs` that runs at the *generated system's* startup, not at install. The folder must contain:

```text
connectors/<name>/
├── connector.json       # the manifest, specified below
├── README.md            # human-readable: what it does, what it needs
├── dotnet/              # Files merged into Infrastructure.<Connector>/
│   ├── <Name>Connector.cs        # Implements IChannel or IIntegration
│   ├── <Name>Options.cs          # Strongly-typed config
│   └── DependencyInjection.cs    # Add<Name>Connector(this IServiceCollection)
├── infra/               # Terraform fragments merged into the system's IaC
└── web/ (optional)      # React components for connector-specific config UI
```

### `connector.json`

Every connector — channel or integration — ships exactly one `connector.json` at `connectors/<kebab-name>/connector.json`. Indent with 2 spaces; trailing newline.

```json
{
  "name": "<kebab-name>",
  "type": "channel | integration",
  "version": "<semver>",
  "description": "<one or two sentences>",
  "capabilities": ["<kebab-name>", ...],
  "requires": {
    "patterns": ["<pattern-skill-name>", ...],
    "secrets": ["<secret-reference-name>", ...],
    "capabilities": ["<capability-name>", ...]
  },
  "homepage": "<https url>"
}
```

| Field | Required | Type | Rule |
|---|---|---|---|
| `name` | yes | string | Kebab-case, pattern `^[a-z][a-z0-9-]{0,38}$`. **Must match the folder name** (`connectors/<name>/`). |
| `type` | yes | string | `channel` (the chatbot speaks through it — Slack, Teams, WhatsApp, email, SMS) or `integration` (data sync — Salesforce, HubSpot, Stripe, calendars). |
| `version` | yes | string | Semantic version `<major>.<minor>.<patch>[-<prerelease>]`. Pattern: `^[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9.-]+)?$`. |
| `description` | yes | string | One or two sentences, 16–280 chars. Shown when the user lists installable connectors. |
| `capabilities` | yes | string[] | Verbs the connector exposes (channel example: `["send-message", "receive-webhook", "list-channels"]`). Each entry kebab-case; at least one. |
| `requires.patterns` | no | string[] | Pattern skills the system must have before this connector can be installed. The installing skill arranges them first. |
| `requires.secrets` | no | string[] | Names of secrets needed at runtime — kebab-case identifiers (e.g. `slack-bot-token`). Stored as references in the cloud secret store; **never embedded values**. |
| `requires.capabilities` | no | string[] | Cross-cutting capabilities (e.g. `ocr`, `vector-db`) the connector depends on. The installing skill verifies the system has them. |
| `homepage` | no | string | Optional `https://...` URL to docs or the upstream service. |

Unknown top-level keys are an error.

**Validation a skill must do on every read or write of `connector.json`:**

1. Parse as JSON.
2. Walk every required field; check it against the pattern table.
3. Reject unknown top-level keys.
4. Run the secret-pattern scan over every string value and **reject any embedded secret value** — `requires.secrets` is for reference *names*, not values.
5. Confirm `name` matches the folder name on disk.

## Guardrails

- **Removable, atomically.** Removing a connector (config change plus the next reconciliation) must leave the system buildable and the other connectors functional. No connector may import another connector directly — only the contracts in `Infrastructure.Connectors/`.
- **Config-driven, not code-driven.** Enabling/disabling per tenant happens in `connectors.config.json` or the dashboard, not in code.
- **One DI registration per connector**, namespaced as `services.AddSlackConnector()`. Never modify `Program.cs` connector-by-connector — the registry handles discovery.
- **Webhooks under `/api/connectors/{name}/webhook`** — never let a connector define top-level routes.
- **Secrets via the cloud secret store**, never in `connectors.config.json` or `connector.json`. The config holds references like `{ "tokenSecretId": "slack-bot-token" }`.
- **Tenant-scoped config.** Connector configuration is per tenant; it flows through the same `ITenantContext` and multi-tenancy filters the rest of the system uses.
- **Enterprise contract still applies.** Connector endpoints carry the same auth, RBAC, rate-limiting, idempotency, and Problem Details wiring as the rest of the API. A connector is not an excuse to bypass the cross-cutting contract; surface any conflict and write an ADR rather than silently downgrading.

## Related skills

- [../dotnet-aspire-base/SKILL.md](../dotnet-aspire-base/SKILL.md) — the .NET + Aspire backbone this pattern mounts onto.
- [../verify-runtime/SKILL.md](../verify-runtime/SKILL.md) — exercises installed connectors (webhook endpoints, health) at runtime.
- An industry-chatbot pattern consumes installed channel connectors via the MAF tools registered here; a multi-tenant pattern scopes connector configs per tenant; a MAF agents stack skill provides the tool-registration utilities.
