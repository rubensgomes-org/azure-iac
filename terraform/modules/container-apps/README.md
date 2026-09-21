# modules/container-apps

Reusable child module that provisions one `azurerm_container_app` per
entry in `var.apps`, all sharing the same Container App Environment
(module 10), the same shared UAMI (module 04) for both runtime identity
and ACR pull, and the same Key Vault (module 05). Injects the env vars
each app needs to authenticate to those services passwordlessly via
`DefaultAzureCredential`.

This is the module where the passwordless model finally comes together:
every RBAC grant handed to the shared UAMI in earlier modules is what
makes the env vars below usable at runtime.

## Contract

**Inputs** (see `variables.tf` for full descriptions and validation):

| Name                           | Type         | Default                                    | Description                                                                  |
|--------------------------------|--------------|--------------------------------------------|------------------------------------------------------------------------------|
| `env`                          | string       | —                                          | Environment token, baked into app names (`ca-<app>-<env>`).                  |
| `resource_group_name`          | string       | —                                          | `rg-<workload>app-<env>` (from module 01).                                   |
| `container_app_environment_id` | string       | —                                          | `cae_id` (from module 10).                                                   |
| `apps`                         | list(string) | —                                          | Microservice names. Must match `var.apps` in `env.tfvars`.                   |
| `uami_id`                      | string       | —                                          | Shared UAMI resource ID (from module 04). Used for identity + ACR pull.      |
| `uami_client_id`               | string       | —                                          | Shared UAMI client ID. Injected as `AZURE_CLIENT_ID`.                        |
| `acr_login_server`             | string       | —                                          | `<acr>.azurecr.io` (from module 06). Set on `registry.server`.               |
| `key_vault_uri`                | string       | —                                          | Vault DNS URI (from module 05). Injected as `KEY_VAULT_URI`.                 |
| `apps_image_map`               | map(string)  | `{}`                                       | Optional per-app image reference. Missing keys fall back to `default_image`. |
| `default_image`                | string       | `mcr.microsoft.com/k8se/quickstart:latest` | Placeholder image while ACR is empty.                                        |
| `target_port`                  | number       | `80`                                       | Container listen port. `8080` for typical Spring Boot images.                |
| `cpu`                          | number       | `0.25`                                     | vCPU per replica. Must pair with a compatible `memory`.                      |
| `memory`                       | string       | `"0.5Gi"`                                  | Memory per replica.                                                          |
| `min_replicas`                 | number       | `0`                                        | `0` = scale-to-zero when idle.                                               |
| `max_replicas`                 | number       | `1`                                        | Horizontal cap per app.                                                      |
| `ingress_external_enabled`     | bool         | `false`                                    | `true` = expose the app on the environment's static IP.                      |
| `apps_without_ingress`         | set(string)  | `[]`                                       | Apps with no `ingress` block at all — no default StartUp probe.              |
| `tags`                         | map(string)  | `{}`                                       | Merged with `component` + `app` tags.                                        |

**Outputs:**

| Name                   | Description                                                                   |
|------------------------|-------------------------------------------------------------------------------|
| `app_ids`              | Map app → full Azure Resource ID.                                             |
| `app_names`            | Map app → deployed resource name (`ca-<app>-<env>`).                          |
| `app_fqdns`            | Map app → FQDN, or `null` when ingress is disabled. Internal-only by default. |
| `app_latest_revisions` | Map app → latest revision name.                                               |

## Design decisions

- **Shared UAMI everywhere.** One identity attached to every app for both
  runtime auth (env vars → DAC → tokens) and ACR pull. Simpler than
  per-app identities; the playground-friendly trade-off is a blast radius
  shared across every app.
- **`revision_mode = "Single"`.** New revisions replace old immediately;
  no traffic-split rules needed. Single-revision mode also removes the
  need for a `Multiple`-mode `traffic_weight` split table.
- **`registry` block declared unconditionally.** Even when apps default
  to `mcr.microsoft.com/k8se/quickstart:latest` (public, unauth pull),
  wiring `registry.identity = <shared-uami>` now means switching to
  ACR-hosted images is a one-line change in `apps_image_map` — the
  identity, RBAC, and block plumbing already exist.
- **Env vars, no secrets.** Every value the app needs at runtime is a
  hostname or an identity ID — none are sensitive. The UAMI itself is
  the credential, held by the platform. `secret` blocks stay unused
  because there's nothing to put in them for the passwordless model.
- **Scale-to-zero default.** `min_replicas = 0` keeps cost near zero
  when apps are idle. First request after a cold-start pays a few-second
  penalty; override to `1` with `TF_VAR_min_replicas` for latency-sensitive
  workloads.

## Placeholder image

The `default_image` (`mcr.microsoft.com/k8se/quickstart:latest`) is
Azure's own "hello world" container for Container Apps. It listens on
port 80 and returns an HTML welcome page — sufficient to prove the
environment, ingress, identity, and RBAC wiring end-to-end before real
Java / Spring Boot images exist in ACR.

Once real images land, override per-app with `TF_VAR_apps_image_map`. The
root cannot hold a `terraform.tfvars` — it is shared by every environment —
so this travels as an export:

```bash
export TF_VAR_apps_image_map='{
  "api":    "crrgomesdev01.azurecr.io/api:1.2.3",
  "worker": "crrgomesdev01.azurecr.io/worker:1.2.3"
}'
export TF_VAR_target_port=8080   # Spring Boot default
```

## Usage

Called from `roots/11-container-apps/main.tf`. See that root's
`README.md` for the copy-paste apply/verify/destroy sequence.
