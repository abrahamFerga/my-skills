# Aspire — publishing and deploying

Scope: turning the app model into deployable artifacts and pushing them to a
target with `aspire publish` / `aspire deploy`, the compute-environment APIs, and
the per-target notes. For Azure resource modeling see [azure.md](azure.md).

## publish vs deploy

| Command | What it does | When |
|---------|--------------|------|
| `aspire publish` | Serializes the app model into **artifacts** (Docker Compose file, Kubernetes manifests/Helm chart, or Bicep) under a publish output dir. Does **not** touch the target. | You want to review/commit the generated infra, or hand it to a separate pipeline. |
| `aspire deploy` | Runs publish, then **builds images, pushes, and applies** them to the configured compute environment. | End-to-end deploy from the CLI. |
| `aspire destroy` | Tears down a previously deployed environment. | Cleaning up. |

Both require a **compute environment** to be declared in the AppHost — otherwise
there's no target to publish for.

## Compute environments

Declare exactly one (typically guarded by publish mode so it doesn't affect
`aspire run`):

```csharp
if (builder.ExecutionContext.IsPublishMode)
{
    builder.AddAzureAppServiceEnvironment("appsvc");
    // builder.AddAzureContainerAppEnvironment("aca");
    // builder.AddKubernetesEnvironment("k8s");
    // builder.AddDockerComposeEnvironment("compose");
}
```

| Environment | Package | Produces | Notes |
|-------------|---------|----------|-------|
| Docker Compose | `Aspire.Hosting.Docker` | `docker-compose.yml` (+ `.env`) | Simplest target; great for a VM or local stack. |
| Kubernetes | `Aspire.Hosting.Kubernetes` | manifests / Helm chart | Hardened in 13.3; pairs with your existing cluster + registry. |
| Azure Container Apps | `Aspire.Hosting.Azure.AppContainers` | Bicep | Aspire's most-native Azure target; scale-to-zero, managed identity wired automatically. |
| Azure App Service | `Aspire.Hosting.Azure.AppService` | Bicep | Matured from preview in 13.x; the default in the architecture skill. |

## Parameters and secrets at deploy time

`AddParameter(..., secret: true)` values come from user-secrets locally. For deploy
they must be supplied by the environment:

- **azd / Azure targets:** parameters surface as Bicep params; secrets land in Key
  Vault and are injected as Key Vault references.
- **Compose / Kubernetes:** secret parameters render into the `.env` / `Secret`
  resources — review before committing and source the real values from your CI
  secret store, not the repo.

Never commit resolved secret values. Treat `aspire publish` output as
infrastructure-as-code to be reviewed, with secrets externalized.

## Deploying to Azure App Service

```csharp
builder.AddAzureAppServiceEnvironment("appsvc");
```

```bash
az login
aspire deploy            # provisions App Service + dependencies, builds, deploys
```

Aspire generates the App Service plan, the web app(s), and managed-identity role
assignments for the Azure resources each service references. If your team already
manages App Service infrastructure with **Terraform** (see
[dotnet-architecture](..//architecture:dotnet-architecture)), prefer Terraform for the
infra and use Aspire only for local orchestration — don't have both `azd` and
Terraform manage the same resources.

## Deploying to Azure Container Apps

```csharp
builder.AddAzureContainerAppEnvironment("aca");
```

Each `AddProject`/`AddContainer` becomes a Container App; `WithExternalHttpEndpoints`
controls ingress; `WithReplicas` and scaling rules map to ACA revisions. Managed
identity and Service Bus/Storage/SQL access are wired into the generated Bicep.

## Docker Compose (non-Azure)

```csharp
builder.AddDockerComposeEnvironment("compose")
    .WithProperties(env => env.BuildContainerImages = true);
```

```bash
aspire publish -o ./publish
docker compose -f ./publish/docker-compose.yml up
```

Good for a single VM, a homelab, or a non-Azure cloud that accepts a Compose file.

## Kubernetes / Helm

```csharp
builder.AddKubernetesEnvironment("k8s");
```

`aspire publish` emits manifests (and a Helm chart). You supply the cluster and a
container registry; wire the image push into your CI. Use this when you already run
Kubernetes — otherwise ACA is less operational overhead for the same model.

## CI/CD shape

A typical pipeline:

1. `dotnet build` / `dotnet test` the solution.
2. `aspire publish -o ./publish` to generate artifacts (review on PRs).
3. On the protected branch, `aspire deploy` (or `azd deploy`) with credentials from
   OIDC/managed identity — never long-lived secrets.

The [dotnet-architecture](..//architecture:dotnet-architecture) skill ships ready-made
GitHub Actions for the Terraform-owned-infra variant (build → deploy to App Service
via OIDC). Use those when Terraform owns the infrastructure and Aspire is local-only.

## Pitfalls

| Pitfall | Fix |
|---------|-----|
| `aspire deploy` errors with "no compute environment" | Declare one (`AddAzure…Environment` / `AddDockerComposeEnvironment` / `AddKubernetesEnvironment`). |
| Compute environment affects `aspire run` | Guard it with `if (builder.ExecutionContext.IsPublishMode)`. |
| Secret parameters end up in committed artifacts | Source them from the CI secret store / Key Vault; review publish output. |
| Both `azd` and Terraform manage the same App Service | Pick one owner for production infra. |
| Image push fails | Ensure the registry is configured and the deploy identity has push rights. |
