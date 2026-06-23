# GitHub Actions Scaffold

Explains [../assets/github-workflows/](../assets/github-workflows/): three
workflows that build/test the app, provision infra, and deploy — all
authenticating to Azure with **OIDC federated credentials** (no stored
passwords or publish profiles).

## The three workflows

| Workflow | Trigger | Does |
|----------|---------|------|
| [`ci.yml`](../assets/github-workflows/ci.yml) | push to `main`, all PRs | `dotnet restore` → `dotnet format --verify-no-changes` → `build` → `test` (with coverage). No cloud auth. |
| [`cd-infra.yml`](../assets/github-workflows/cd-infra.yml) | push/PR touching `infra/**` | PR: `fmt`/`validate`/`plan` only. main: `plan` then **`apply`** behind a prod environment gate. OIDC. |
| [`cd-app.yml`](../assets/github-workflows/cd-app.yml) | push to `main`, or manual dispatch | `dotnet publish` → upload artifact → `azure/login` (OIDC) → `azure/webapps-deploy@v3`. Environment-gated. |

## Pinned action versions

| Action | Version | Used in |
|--------|---------|---------|
| `actions/checkout` | `@v4` | all |
| `actions/setup-dotnet` | `@v4` | ci, cd-app (reads `global.json`) |
| `actions/upload-artifact` / `download-artifact` | `@v4` | all |
| `azure/login` | `@v2` | cd-infra, cd-app |
| `hashicorp/setup-terraform` | `@v3` | cd-infra |
| `azure/webapps-deploy` | `@v3` | cd-app |

> Pin to the major where Microsoft/GitHub ship rolling majors (`@v4`, `@v2`).
> For supply-chain-strict orgs, pin to a full commit SHA instead.

## OIDC: how auth works (no secrets)

```
GitHub job (id-token: write)
   │  1. requests a short-lived OIDC JWT from GitHub's provider
   ▼
azure/login@v2  (client-id, tenant-id, subscription-id — IDs, not secrets)
   │  2. presents the JWT to Entra ID
   ▼
Entra ID checks the federated credential's subject (repo + ref/environment)
   │  3. issues a short-lived Azure access token
   ▼
az CLI / azurerm provider / webapps-deploy use that token
```

Every OIDC job declares:

```yaml
permissions:
  id-token: write   # mint the federated token
  contents: read    # checkout
```

`AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID` are stored as
GitHub **variables** (`vars.*`), not secrets — they're identifiers, and the
federated *trust* is what authorizes use. There is **no client secret** and no
publish profile anywhere.

### One-time Azure setup (outside this scaffold)

1. Create an Entra app registration (or use a User-Assigned Managed Identity).
2. Add **federated credentials** whose `subject` matches each job context, e.g.:
   - `repo:<org>/<repo>:ref:refs/heads/main` (for `apply`/deploy on main)
   - `repo:<org>/<repo>:pull_request` (for PR `plan`)
   - `repo:<org>/<repo>:environment:prod` (for environment-gated jobs)
3. Grant that principal the Azure RBAC it needs (e.g. **Contributor** on the
   target subscription/RG, **Storage Blob Data Contributor** on the state
   container, and whatever Key Vault role the apply needs).
4. Set repo/environment variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`, the `TFSTATE_*` trio, and `AZURE_WEBAPP_NAME`
   (from the Terraform `web_app_name` output).

> The federated `subject` must include the **environment** form for jobs that
> declare `environment: prod`, because GitHub changes the token subject when a
> job runs in an environment. Missing this is the #1 OIDC failure.

## Environments & approvals

Both CD workflows use `environment:` on their deploy/apply jobs:

- `cd-infra.yml`'s `apply` job → `environment: prod`.
- `cd-app.yml`'s `deploy` job → `environment: ${{ inputs.environment || 'prod' }}`.

Configure the GitHub **environment** (Settings → Environments) with **required
reviewers** so a human approves before `terraform apply` or a prod deploy runs,
and scope environment-specific variables/secrets there. This is the approval gate;
the workflow files only reference it.

## Flow between the three

```
PR opened ──► ci.yml (build/test/format)         must be green to merge
          └─► cd-infra.yml: plan only            review the plan on the PR

merge to main
   ├─► cd-infra.yml: plan → [approve] → apply     infra converges first
   └─► cd-app.yml: publish → [approve] → deploy    then the app ships
```

Run `cd-infra` to convergence before `cd-app` the first time (the app needs the
web app + identity to exist). On steady-state, app-only changes skip infra
(`paths-ignore: infra/**`) and infra-only changes skip the app deploy.

## Why `dotnet format --verify-no-changes` in CI

It fails the build if any file violates
[`.editorconfig`](../assets/solution/.editorconfig), keeping style out of code
review. Pair it with `TreatWarningsAsErrors` (set in
[`Directory.Build.props`](../assets/solution/Directory.Build.props)) so both style
and analyzer findings block merges.
