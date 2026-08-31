# 09-postgresql (envs/dev)

Root Terraform config that provisions the shared PostgreSQL Flexible
Server for the `dev` environment, one database per microservice, the AAD
administrator binding, the runner + Azure-services firewall rules, and
the psql-driven bootstrap that registers the shared UAMI as an
AAD-authenticated PG role with per-DB grants. State lives in
`tfstate/postgresql/terraform.tfstate` on the bootstrap storage account.

Wraps [`../../../modules/postgresql/`](../../../modules/postgresql/README.md).

## Upstreams

**Apply the upstreams first.** This root reads modules 01 and 04 through
`data.terraform_remote_state`; against an empty state key a plan fails
with *Unsupported attribute* rather than anything self-explanatory.
Bring module 09 up with:

```bash
make apply-resource-groups      # 01 — rg-dev-data and friends
make apply-managed-identities   # 04 — the shared UAMI this module registers in PG
make apply-postgresql           # 09
```

Expect a create-only plan: the server, two firewall rules, the Entra
admin binding, and one database per entry in `apps`. The server name is
`psql-dev-<hex>` from `random_id.suffix`, which regenerates on a fresh
apply — so it will NOT be the name any earlier run used.

**Then run the data-plane bootstrap once, by hand.** The in-line
`null_resource.pg_bootstrap` is gated OFF (`run_bootstrap = false`)
because this runner's ISP blocks outbound TCP 5432 to Azure PG, so
Terraform cannot complete the psql step from here. That gate is still in
place and still correct. Grab the FQDN:

```bash
terraform output -raw pg_fqdn
```

then follow [Data-plane bootstrap (Cloud Shell)](#data-plane-bootstrap-cloud-shell)
below — open https://shell.azure.com, verify group membership, run the
SQL block. Takes <10 seconds, and it is idempotent. §12a of
[`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md)
describes the Container Apps Job that is meant to replace this manual
step (deferred item D3).

Everything below this section is the full module reference.

## Prerequisites

- Modules **01** (`01-resource-groups`) and **04** (`04-managed-identities`)
  applied — this root reads `rg_data_name` and `uami_app_name` from their
  remote state.
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`
  exported in the current shell.
- `../env.tfvars` populated with `env`, `location`, `apps`, `tags`, AND
  BOTH `pg_entra_admin_group_object_id` (a real GUID) and
  `pg_entra_admin_group_name` (the same group's display name — kept as
  a separate variable because the object-ID → display-name lookup via
  `data.azuread_group` needs Directory.Read scopes the Terraform SP
  usually lacks).
- The Terraform SP is a **member of the Entra admin group** referenced
  by that object ID. Without membership the AAD token is issued but PG
  rejects the connection during the null_resource step.
- **On the runner:** `az` CLI (2.60+), `psql` (Postgres client 15+),
  and `bash` on `PATH`. The null_resource shells out to all three.

### One-time Entra admin group setup

Run from an INTERACTIVE `az login` session (a shell where `az`
authenticated as your user, not the Terraform SP). The commands need
Directory.Read.All-equivalent scopes that the SP typically lacks.

```bash
# 1. Create the group (skip if it already exists)
az ad group create \
  --display-name  "az-dev-pg-admins" \
  --mail-nickname "az-dev-pg-admins"

# 2. Resolve the Terraform SP's OBJECT ID from its clientId.
#    IMPORTANT: `az ad group member add --member-id` takes the SP's
#    Entra object_id, which is DIFFERENT from ARM_CLIENT_ID (the SP's
#    application/clientId). Passing ARM_CLIENT_ID directly silently
#    fails membership resolution later.
SP_OBJECT_ID=$(az ad sp show --id "$ARM_CLIENT_ID" --query id -o tsv)

# 3. Add the Terraform SP and yourself as members
az ad group member add \
  --group     "az-dev-pg-admins" \
  --member-id "$SP_OBJECT_ID"

az ad group member add \
  --group     "az-dev-pg-admins" \
  --member-id "$(az ad signed-in-user show --query id -o tsv)"

# 4. Fetch the group's object ID and paste into env.tfvars
az ad group show --group "az-dev-pg-admins" --query id -o tsv
```

## Provision

```bash
cd terraform/envs/dev/09-postgresql

terraform init \
  -backend-config=../backend.hcl \
  -backend-config="key=postgresql/terraform.tfstate"

terraform plan \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars \
  -out=tfplan

terraform apply tfplan
```

Terraform provisions the server, AAD administrator binding, firewall
rules, and per-app databases — but **stops short of the psql data-plane
step** (see next section for why + how to run it). Expect apply time
~6-8 minutes for a fresh server.

## Data-plane bootstrap (Cloud Shell)

The shared UAMI still needs to be registered as an AAD-authenticated PG
role via `pgaadauth_create_principal`, and each app database needs a
`GRANT CONNECT` + `GRANT USAGE, CREATE ON SCHEMA public` for that role.
Container Apps in module 11 will fail to open a connection until this
step runs.

The child module has an in-line `null_resource.pg_bootstrap` that does
exactly this, but it's **gated off by default** (`run_bootstrap = false`
in [`main.tf`](main.tf)) because most corporate / home networks block
outbound TCP 5432, which turns `terraform apply` into an unrecoverable
failure. Instead, run the SQL once from **Azure Cloud Shell** — Cloud
Shell egresses from Azure public IP space, and the `allow-azure-services`
firewall rule created by this module already covers it.

Open Cloud Shell at https://shell.azure.com (Bash). Verify your identity
is a member of the PG Entra admin group (`az-dev-pg-admins`) — Cloud
Shell logs you in as your own user, not the Terraform SP:

```bash
az ad signed-in-user show --query userPrincipalName -o tsv
az ad group member check \
  --group "az-dev-pg-admins" \
  --member-id "$(az ad signed-in-user show --query id -o tsv)" \
  --query value
# Expect: true
```

Then run the bootstrap:

```bash
# ---- pull values from Terraform outputs on your local machine and paste
# ---- them here, since Cloud Shell has no access to your tfstate
# Replace <hex> with the suffix from `terraform output -raw pg_fqdn`. It is
# regenerated on every fresh apply, so do not reuse one from an earlier run.
PG_FQDN="psql-dev-<hex>.postgres.database.azure.com"
ADMIN_GROUP="az-dev-pg-admins"
UAMI_NAME="id-dev-app"
APPS=(api worker)   # must match var.apps in env.tfvars

# AAD access token scoped to the Azure PG data plane
export PGPASSWORD=$(az account get-access-token \
  --resource https://ossrdbms-aad.database.windows.net \
  --query accessToken -o tsv)

# Step 1 — register the shared UAMI as an AAD principal (idempotent)
psql "host=$PG_FQDN port=5432 dbname=postgres user=$ADMIN_GROUP sslmode=require" <<SQL
DO \$mig\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$UAMI_NAME') THEN
    PERFORM pgaadauth_create_principal('$UAMI_NAME', false, false);
  END IF;
END
\$mig\$;
SQL

# Step 2 — per-app CONNECT + schema grants (GRANT is idempotent in PG)
for APP in "${APPS[@]}"; do
  psql "host=$PG_FQDN port=5432 dbname=postgres user=$ADMIN_GROUP sslmode=require" \
    -c "GRANT CONNECT ON DATABASE \"$APP\" TO \"$UAMI_NAME\";"
  psql "host=$PG_FQDN port=5432 dbname=$APP user=$ADMIN_GROUP sslmode=require" \
    -c "GRANT USAGE, CREATE ON SCHEMA public TO \"$UAMI_NAME\";"
done
```

Expected runtime: <10 seconds total. Idempotent — safe to re-run if you
add an app to `var.apps` later (add its name to `APPS=(...)` and run the
loop again; step 1 no-ops).

**Long-term:** the manual step goes away when this bootstrap moves into
a Container Apps Job triggered by GitHub Actions. See
[`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §12a
for the design. Until that lands, the Cloud Shell path is the sanctioned
workaround.

## Verify

```bash
# Server exists, state Ready, AAD-only auth on
PG_NAME=$(terraform output -raw pg_server_name)
az postgres flexible-server show -g rg-dev-data -n "$PG_NAME" \
  --query "{name:name, state:state, fqdn:fullyQualifiedDomainName, aadAuth:authConfig.activeDirectoryAuth, pwAuth:authConfig.passwordAuth}" \
  -o table
# Expect state=Ready, aadAuth=Enabled, pwAuth=Disabled.

# Databases (one per var.apps)
az postgres flexible-server db list -g rg-dev-data -s "$PG_NAME" \
  --query "[?name!='azure_maintenance' && name!='azure_sys' && name!='postgres'].name" \
  -o tsv

# AAD administrator binding
az postgres flexible-server ad-admin list -g rg-dev-data -s "$PG_NAME" \
  --query "[].{principal:principalName, type:principalType, obj:objectId}" \
  -o table
# Expect one row: your Entra admin group.

# Firewall rules (runner IP + Azure services)
az postgres flexible-server firewall-rule list -g rg-dev-data -n "$PG_NAME" \
  --query "[].{name:name, start:startIpAddress, end:endIpAddress}" \
  -o table
```

Optional — confirm the shared UAMI is registered as an AAD principal
(requires `az login` as a group member + `psql`):

```bash
GROUP_NAME=$(terraform output -raw pg_admin_login)
PG_FQDN=$(terraform output -raw pg_fqdn)
export PGPASSWORD=$(az account get-access-token \
  --resource https://ossrdbms-aad.database.windows.net \
  --query accessToken -o tsv)

psql "host=$PG_FQDN port=5432 dbname=postgres user=$GROUP_NAME sslmode=require" \
  -c "SELECT rolname FROM pg_roles WHERE rolname = 'id-dev-app';"
# Expect one row: id-dev-app.
```

## Destroy

```bash
cd terraform/envs/dev/09-postgresql

PG_NAME=$(terraform output -raw pg_server_name)   # capture BEFORE destroy

terraform destroy \
  -var-file=../env.tfvars \
  -var-file=terraform.tfvars

# Post-destroy: Flexible Server holds the name up to 7 days.
az postgres flexible-server list --show-deleted -o table \
  | grep "$PG_NAME" || echo "(name is already free)"
```

No purge command exists for Flex — the name is either in the
soft-deleted list (need a new random suffix to reprovision, which the
child module produces automatically) or gone.

**Order matters.** Container Apps (module 11) connect via the shared
UAMI. Destroy module 11 first — otherwise running apps see
`FATAL: no pg_hba.conf entry` the moment the AAD admin or the AAD
principal disappears.

## Reprovision

Same commands as **Provision**. The `random_id` suffix is keyed on
`env`, so reprovisioning the same env lands on a fresh name
(`psql-dev-<newhex>`) — the 7-day soft-delete tombstone on the old
name does not block the new one.

See [`docs/PROVISIONING_PLAN.md`](../../../../docs/PROVISIONING_PLAN.md) §8
for the reprovision shortcut.

## Troubleshooting

### `LocationIsOfferRestricted` on server create

```
Status:  "LocationIsOfferRestricted"
Message: "Subscriptions are restricted from provisioning in location
          'eastus'. Try again in a different location."
```

Per-subscription + per-service restriction. Common on free / trial /
MSDN / CSP subscriptions — every other module (RGs, VNet, KV, ACR,
Storage, Service Bus) provisions to the restricted region without
issue; PG Flex alone is gated.

**You should not hit this today.** The estate is `centralus`, which is
not restricted for this subscription. The error above quotes `eastus`
because that is where the estate lived until v0.4.2, and it is the
reason this root used to carry a `location = "eastus2"` override. That
override has been removed — PG Flex now inherits `centralus` from the
shared `../env.tfvars` like everything else.

It becomes relevant again the moment you move the estate. Check the
candidate region BEFORE editing `env.tfvars`:

```bash
az postgres flexible-server list-skus --location <region> -o json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0].get("reason") or "no restriction")'
# "no restriction"                        = region works
# "Provisioning is restricted in this..." = pick another
```

If the new region is restricted, the cheapest fix is what this root did
before: reinstate a single `location = "<nearest-unrestricted>"` line in
[`terraform.tfvars`](terraform.tfvars) to move PG Flex alone. The parent
RG `rg-dev-data` follows `env.tfvars` — Azure allows an RG to hold
resources in a different region.

### `InvalidResourceLocation` 409 after a failed create

```
409 Conflict — InvalidResourceLocation: The resource 'psql-dev-<hex>'
already exists in location '<old-region>' in resource group 'rg-dev-data'.
A resource with the same name cannot be created in location '<new-region>'.
```

Happens when the previous apply failed mid-create (e.g. from the
`LocationIsOfferRestricted` above): Azure holds the server name in the
original region even though the resource itself never became healthy,
AND Terraform's `random_id.suffix` is already in state — so the retry
tries to create the same name in a different region and Azure refuses.

Fix in two steps:

1. Delete the phantom / failed server holding the name in the original
   region. Skip the delete if `show` returns `ResourceNotFound`:

   ```bash
   az postgres flexible-server show \
     -g rg-dev-data -n psql-dev-<hex> \
     --query "{name:name, state:state, location:location}" -o table

   az postgres flexible-server delete \
     -g rg-dev-data -n psql-dev-<hex> --yes
   ```

2. Force a fresh suffix and re-apply. `random_id.suffix` is keyed on
   `env`, so `-replace` regenerates it and the new server lands on
   `psql-dev-<newhex>` — sidestepping the 7-day soft-delete tombstone
   on the original name:

   ```bash
   terraform apply \
     -replace=module.postgresql.random_id.suffix \
     -var-file=../env.tfvars \
     -var-file=terraform.tfvars
   ```

### `psql: command not found` in the null_resource step

```
local-exec provisioner error
environment: line 79: psql: command not found
exit status 127
```

The `null_resource.pg_bootstrap` step shells out to `psql` (Postgres
client) to run `pgaadauth_create_principal` + per-DB grants. If the
runner doesn't have `psql` on PATH, the whole apply fails at that step
even though the server, admin binding, firewall rules, and databases
all provisioned cleanly.

Fix on Ubuntu-based WSL2 / Linux:

```bash
# Fast path — Ubuntu's default repos usually carry a recent-enough client
sudo apt update
sudo apt install -y postgresql-client

# Verify version >= 15 (the module targets PG 16 server-side)
psql --version
```

If the default repo ships < 15, add the PGDG apt repo and install
`postgresql-client-16` instead:

```bash
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc

sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
  https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list'

sudo apt update
sudo apt install -y postgresql-client-16
```

Then re-run `terraform apply`. The failed `null_resource.pg_bootstrap`
is tainted in state — the next apply destroys the tainted instance and
re-attempts the local-exec. No other resources need to be touched.

### `Invalid template interpolation value` from `templatefile()`

```
Call to function "templatefile" failed:
  Invalid template interpolation value; Cannot include the given value
  in a string template: string required, but have list of string.
```

Cause: an unescaped `${...}` somewhere inside
`modules/postgresql/scripts/pg-bootstrap.sh.tftpl` — `templatefile()`
processes `${...}` **everywhere** in the file, including shell comments
and prose. If the referenced name is a list (e.g. `${apps}`) or an
undefined identifier (e.g. `${...}` used as literal ellipsis in
documentation), the render fails.

Fix: escape every `${...}` that is meant to appear as literal text in
the rendered script — use `$${...}`, which templatefile() emits as
literal `${...}`. Only genuine substitution points and the
`%{ for ... }` / `%{ endfor }` loop directives should be left
unescaped.

## Notes

- SKU, PG version, storage size, backup retention, and network posture
  are hard-coded in the child module (`modules/postgresql/main.tf`).
  Change there if you need a bigger tier, HA, or the eventual VNet-only
  migration.
- **No region override** (removed in v0.4.2). PG Flex inherits
  `centralus` from the shared env.tfvars along with every other module.
  It used to pin `eastus2`, because the subscription is offer-restricted
  from PG Flex in the then-current `eastus`; `centralus` is not
  restricted, so the split is gone. See Troubleshooting →
  `LocationIsOfferRestricted` before moving the estate again.
- The runner's public IP is fetched fresh on every plan via
  `https://api.ipify.org`. Applying from a different location updates
  the firewall rule (a small diff every time you roam).
- The Entra admin group's display name is passed EXPLICITLY via
  `pg_entra_admin_group_name` in env.tfvars — no `data.azuread_group`
  lookup. The lookup requires `Directory.Read.All` / `Group.Read.All`
  on the Terraform SP, which a playground SP typically lacks (granting
  needs tenant admin consent).
- The null_resource `pg_bootstrap` re-runs only when its `triggers`
  change (server ID, uami_name, admin login, apps list). The script
  itself is idempotent, so triggered re-runs are safe.
- **Not consumed:** the master plan lists module 02 (network) and
  module 05 (Key Vault) as postgresql dependencies. Neither is used
  today — see `modules/postgresql/README.md` § Skipped dependencies.
