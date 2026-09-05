# 11-container-apps (envs/dev)

Root Terraform config that provisions one Azure Container App per entry in
`var.apps`, all sharing the same environment (module 10), the same shared
UAMI (module 04) for both runtime identity and ACR pull, and the same PG /
Storage / Service Bus endpoints. This is the module where the passwordless
auth model finally comes together end-to-end. State lives at key
`container-apps/terraform.tfstate` in the backend blob container.

Wraps [`../../../modules/container-apps/`](../../../modules/container-apps/README.md).

**`make apply-container-apps` on its own will NOT work** unless all seven
prerequisites below are already applied. This root reads every one of
them through `data.terraform_remote_state`, and against an empty state
key the plan fails with *Unsupported attribute* rather than a useful
message. Apply the chain in order first:

```bash
make apply-resource-groups        # 01
make apply-managed-identities     # 04
make apply-acr                    # 06
make apply-storage                # 07
make apply-service-bus            # 08
make apply-postgresql             # 09  (plus its manual Cloud Shell bootstrap)
make apply-container-app-environment  # 10
make apply-container-apps         # 11
```

or just `make apply` from the repo root, which walks 01 → 12.

## Prerequisites

Modules **01, 04, 06, 07, 08, 09, and 10** applied. This root reads:

| From                         | Outputs consumed                                     |
|------------------------------|------------------------------------------------------|
| 01-resource-groups           | `rg_app_name`                                        |
| 04-managed-identities        | `uami_app_id`, `uami_app_name`, `uami_app_client_id` |
| 06-acr                       | `acr_login_server`                                   |
| 07-storage                   | `sa_name`, `container_names`                         |
| 08-service-bus               | `sb_namespace_fqdn`                                  |
| 09-postgresql                | `pg_fqdn`, `pg_databases`                            |
| 10-container-app-environment | `cae_id`                                             |

Additional requirements:

- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`,
  `ARM_SUBSCRIPTION_ID` exported in the current shell.
- `../env.tfvars` populated with `env` and `apps`.
- Both `.tfvars` files are gitignored and are NOT in a fresh clone. Create them
  once — see [`INITIAL_SETUP.md`](../../../INITIAL_SETUP.md) § Terraform
  Variable Files. Tags are not among their values: they come from the committed
  [`../tags.json`](../tags.json), with `TF_VAR_owner` overriding `owner`.
- The shared UAMI already registered as an AAD principal in PG (the
  manual Cloud Shell bootstrap from `09-postgresql/README.md`) —
  otherwise apps will start but every DB call will fail with
  `password authentication failed for user "id-dev-app"`.
- If real images are referenced in `apps_image_map` — the images must
  actually exist in ACR under those exact tags. First apply on a missing
  image fails with a container-pull error and leaves the app in a
  failed provisioning state (fix: push the image, re-apply).

## Provision

```bash
cd terraform/envs/dev/11-container-apps

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=container-apps/terraform.tfstate"

terraform plan \
  -out=tfplan

terraform apply tfplan
```

Apply time is ~2-4 minutes on a fresh environment — Azure provisions one
revision per app in parallel, and the placeholder quickstart image pulls
quickly from `mcr.microsoft.com`. Real Java / Spring Boot images can add
30-60s per app depending on image size.

## Verify

```bash
# Apps exist, provisioning state = Succeeded
az containerapp list -g "rg-dev-app${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" -o table
# Expect one row per entry in var.apps (e.g. ca-dev-api, ca-dev-worker).

# Ingress FQDNs (matches terraform output app_fqdns)
az containerapp list -g "rg-dev-app${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" \
  --query "[].{name:name, fqdn:properties.configuration.ingress.fqdn}" \
  -o table

# Identity wired to the shared UAMI on every app
UAMI_ID=$(cd ../04-managed-identities && terraform output -raw uami_app_id)
az containerapp list -g "rg-dev-app${TF_VAR_rg_suffix:+-$TF_VAR_rg_suffix}" \
  --query "[].{name:name, uami:keys(identity.userAssignedIdentities)[0]}" \
  -o table
# Expect uami column to equal $UAMI_ID for every row.

# Placeholder image reachable (200 OK returns Azure's hello page)
API_FQDN=$(terraform output -json app_fqdns | jq -r '.api')
curl -sSf "https://$API_FQDN/" | head -20
```

Sanity outputs from Terraform:

```bash
terraform output app_fqdns              # per-app public URLs
terraform output app_latest_revisions   # for rollback / diagnostics
```

## Destroy

```bash
cd terraform/envs/dev/11-container-apps

terraform destroy
```

Container Apps have no soft-delete window on their names, so a
destroy+recreate is free of the naming dance PG / KV / LAW go through.

**Order matters going the other way.** Module 10 (Container App
Environment) refuses to delete while apps still live inside it — always
destroy this module first, then module 10. Same rule applies in reverse
for provisioning (module 10 before this one).

## Swapping the placeholder image for real ACR-hosted images

The child module defaults to `mcr.microsoft.com/k8se/quickstart:latest`
so the first `terraform apply` succeeds even with an empty ACR. To swap
to real images:

1. Push images to the ACR provisioned by module 06:

   ```bash
   ACR_NAME=$(cd ../06-acr && terraform output -raw acr_name)
   az acr login --name "$ACR_NAME"
   docker tag api:local  "$ACR_NAME.azurecr.io/api:1.0.0"
   docker push "$ACR_NAME.azurecr.io/api:1.0.0"
   ```

2. Edit `terraform.tfvars` in this directory:

   ```hcl
   apps_image_map = {
     api    = "rubensdevacr.azurecr.io/api:1.0.0"
     worker = "rubensdevacr.azurecr.io/worker:1.0.0"
   }
   target_port = 8080   # Spring Boot default; 80 for the placeholder
   ```

3. Re-apply:

   ```bash
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

`revision_mode = "Single"` means the new revision replaces the old
immediately.

## Notes

- **Passwordless auth end-to-end.** Every value injected as an env var
  is either a hostname or the UAMI's client_id — none are secrets. Apps
  authenticate to PG, Blob, Service Bus, and Key Vault via
  `DefaultAzureCredential`; the platform holds the credential material.
- **Shared UAMI on every app.** Same identity for runtime, same
  identity for ACR pull. The trade-off is a blast radius shared across
  every app.
- **Scale-to-zero by default.** `min_replicas = 0` means apps sleep
  after 5 minutes of idle. First request after idle pays a cold-start
  latency. Set `min_replicas = 1` in `terraform.tfvars` for
  latency-sensitive apps.
- **No `secret {}` blocks.** Nothing to put in them under the
  passwordless model — the UAMI is the credential.
- **Service Bus queue names not injected.** Module 08 defaults to
  `queues = []`. When workloads actually need queues, add a
  `servicebus_queue_names` variable to the child module and thread it
  through here.
