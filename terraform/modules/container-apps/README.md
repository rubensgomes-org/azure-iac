# modules/container-apps

Reusable child module that provisions one `azurerm_container_app` per
entry in `var.apps`, all sharing the same Container App Environment
(module 10), the same shared UAMI (module 04) for both runtime identity
and ACR pull, and the same downstream services (PG, Storage, Service
Bus). Injects the env vars each app needs to authenticate to those
services passwordlessly via `DefaultAzureCredential`.

This is the module where §12 of `docs/PROVISIONING_PLAN.md` finally
comes together: every RBAC grant handed to the shared UAMI in earlier
modules is what makes the env vars below usable at runtime.

## Contract

**Inputs** (see `variables.tf` for full descriptions and validation):

| Name                          | Type          | Default                                       | Description                                                          |
|-------------------------------|---------------|-----------------------------------------------|----------------------------------------------------------------------|
| `env`                         | string        | —                                             | Environment token, baked into app names (`ca-<env>-<app>`).          |
| `resource_group_name`         | string        | —                                             | `rg-<env>-app` (from module 01).                                     |
| `container_app_environment_id`| string        | —                                             | `cae_id` (from module 10).                                           |
| `apps`                        | list(string)  | —                                             | Microservice names. Must match `var.apps` in `env.tfvars`.           |
| `uami_id`                     | string        | —                                             | Shared UAMI resource ID (from module 04). Used for identity + ACR pull. |
| `uami_name`                   | string        | —                                             | Shared UAMI name (`id-<env>-app`). Injected as `POSTGRES_USER`.      |
| `uami_client_id`              | string        | —                                             | Shared UAMI client ID. Injected as `AZURE_CLIENT_ID`.                |
| `acr_login_server`            | string        | —                                             | `<acr>.azurecr.io` (from module 06). Set on `registry.server`.       |
| `postgres_host`               | string        | —                                             | PG FQDN (from module 09). Injected as `POSTGRES_HOST`.               |
| `postgres_databases`          | map(string)   | `{}`                                          | app → DB name (from module 09). Falls back to app name if missing.   |
| `storage_account_name`        | string        | —                                             | Storage account name (from module 07). Injected as `STORAGE_ACCOUNT_NAME`. |
| `storage_container_names`     | map(string)   | `{}`                                          | app → container name (from module 07). Falls back to app name if missing. |
| `servicebus_namespace_fqdn`   | string        | —                                             | Service Bus FQDN (from module 08). Injected as `SERVICEBUS_NAMESPACE_FQDN`. |
| `apps_image_map`              | map(string)   | `{}`                                          | Optional per-app image reference. Missing keys fall back to `default_image`. |
| `default_image`               | string        | `mcr.microsoft.com/k8se/quickstart:latest`    | Placeholder image while ACR is empty.                                |
| `target_port`                 | number        | `80`                                          | Container listen port. `8080` for typical Spring Boot images.        |
| `cpu`                         | number        | `0.25`                                        | vCPU per replica. Must pair with a compatible `memory`.              |
| `memory`                      | string        | `"0.5Gi"`                                     | Memory per replica.                                                  |
| `min_replicas`                | number        | `0`                                           | `0` = scale-to-zero when idle.                                       |
| `max_replicas`                | number        | `1`                                           | Horizontal cap per app.                                              |
| `ingress_external_enabled`    | bool          | `true`                                        | `true` = public FQDN on the environment's static IP.                 |
| `tags`                        | map(string)   | `{}`                                          | Merged with `component` + `app` tags.                                |

**Outputs:**

| Name                    | Description                                                                 |
|-------------------------|-----------------------------------------------------------------------------|
| `app_ids`               | Map app → full Azure Resource ID.                                           |
| `app_names`             | Map app → deployed resource name (`ca-<env>-<app>`).                        |
| `app_fqdns`             | Map app → externally-reachable FQDN, or `null` when ingress is disabled.    |
| `app_latest_revisions`  | Map app → latest revision name.                                             |

## Design decisions

- **Shared UAMI everywhere.** One identity attached to every app for both
  runtime auth (env vars → DAC → tokens) and ACR pull. Simpler than
  per-app identities; playground-friendly trade-off documented in
  `docs/PROVISIONING_PLAN.md` §12.
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
  penalty; override to `1` per-app in the root's `terraform.tfvars` for
  latency-sensitive workloads.

## Placeholder image

The `default_image` (`mcr.microsoft.com/k8se/quickstart:latest`) is
Azure's own "hello world" container for Container Apps. It listens on
port 80 and returns an HTML welcome page — sufficient to prove the
environment, ingress, identity, and RBAC wiring end-to-end before real
Java / Spring Boot images exist in ACR.

Once real images land, override per-app in
`envs/dev/11-container-apps/terraform.tfvars`:

```hcl
apps_image_map = {
  api    = "acrdev1234.azurecr.io/api:1.2.3"
  worker = "acrdev1234.azurecr.io/worker:1.2.3"
}
target_port = 8080   # Spring Boot default
```

## Usage

Called from `envs/dev/11-container-apps/main.tf`. See that root's
`README.md` for the copy-paste apply/verify/destroy sequence.
