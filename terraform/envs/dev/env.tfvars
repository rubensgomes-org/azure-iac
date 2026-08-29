# -----------------------------------------------------------------------------
# terraform/envs/dev/env.tfvars
# -----------------------------------------------------------------------------
# Shared variable values for every module root under envs/dev/<NN-module>/.
# Passed to terraform explicitly on every plan/apply/destroy:
#
#   terraform plan  -var-file=../env.tfvars -var-file=terraform.tfvars ...
#   terraform apply -var-file=../env.tfvars -var-file=terraform.tfvars ...
#
# Values here are consumed by variables declared in each module's variables.tf.
# Module-specific overrides live in that module's own terraform.tfvars (loaded
# second so it wins on conflict).
#
# See docs/PROVISIONING_PLAN.md sections 6 and 7 for the full context.
# -----------------------------------------------------------------------------

# Environment name. Used in every resource name (rg-<env>-<purpose>, ca-<env>-<app>,
# etc.) and as a tag. Change to "prod" for a prod env root (envs/prod/env.tfvars).
env = "dev"

# Azure region where every module in this env deploys. Single-region on purpose;
# multi-region is out of scope for this playground.
#
# Moved from `eastus` to `centralus` in v0.4.2. Two things to know before
# changing it again:
#   - `location` is ForceNew on every azurerm resource, and no resource name in
#     this repo embeds the region, so on an APPLIED estate `terraform plan` shows
#     `-/+ destroy and then create` on everything with no name diff to warn you.
#     Combined with `make apply`'s `-auto-approve`, that turns a routine apply
#     into a full teardown. Always `make plan-<module>` first.
#   - PostgreSQL Flexible Server is offer-restricted in `eastus` on this
#     subscription. Any future region must be checked with
#     `az postgres flexible-server list-skus --location <region>` before it is
#     set here — see 09-postgresql/terraform.tfvars.
location = "centralus"

# Short organisation / owner token that anchors globally-unique names.
# Example: Key Vault name pattern is `kv-<env>-<prefix>-<random>` → `kv-dev-rubens-a7f2`.
prefix = "rubens"

# -----------------------------------------------------------------------------
# Microservice applications
# -----------------------------------------------------------------------------
# Each entry:
#   - drives one PostgreSQL database in the shared PG Flexible Server
#     (created in module 09)
#   - drives one Container App in the ACA environment (created in module 11)
#
# All apps share ONE User-Assigned Managed Identity (id-dev-app, created in
# module 04). Adding a name here → next `terraform apply` on the affected
# modules creates that app's DB and Container App. Removing a name → apply will
# DESTROY that app's DB (and Container App). Consider blue/green before removal.
#
# TODO: replace ["api", "worker"] with your actual microservice names before
# module 09 (postgresql) applies.
apps = ["api", "worker"]

# -----------------------------------------------------------------------------
# PostgreSQL Entra admin group (module 09 dependency)
# -----------------------------------------------------------------------------
# Object ID (NOT display name) of the Entra ID group whose members are the
# PostgreSQL Flexible Server administrators. Server has Entra-only auth
# (password auth disabled). Group members can connect as Postgres admin using
# their own Entra token — the Terraform SP MUST be a member so it can register
# the shared UAMI as an in-DB AAD principal during apply.
#
# How to create + fetch the object ID (run from an INTERACTIVE az login,
# not the Terraform SP session — the SP typically lacks Directory.Read
# scopes needed to resolve members):
#   az ad group create --display-name "az-dev-pg-admins" \
#                      --mail-nickname "az-dev-pg-admins"
#
#   # Terraform SP object_id ≠ ARM_CLIENT_ID (application/clientId).
#   # Resolve first, then add:
#   SP_OBJECT_ID=$(az ad sp show --id "$ARM_CLIENT_ID" --query id -o tsv)
#   az ad group member add --group "az-dev-pg-admins" \
#                          --member-id "$SP_OBJECT_ID"
#
#   az ad group member add --group "az-dev-pg-admins" \
#                          --member-id "$(az ad signed-in-user show --query id -o tsv)"
#
#   az ad group show --group "az-dev-pg-admins" --query id -o tsv
#
# TODO: replace the placeholder below with the object ID before module 09
# applies. Leaving it as "REPLACE_ME" is safe until you reach module 09;
# earlier modules do not reference this variable.
# pg_entra_admin_group_object_id = "REPLACE_ME"
pg_entra_admin_group_object_id = "5b010ef4-5f5f-487f-ac90-7fc17bda0ac9"

# Display name of the SAME Entra group referenced by
# pg_entra_admin_group_object_id. Passed to the AAD administrator resource
# as `principal_name` and used as the PGUSER value in the psql bootstrap.
#
# Why keep this as a separate variable instead of looking it up from the
# object ID via `data.azuread_group`? The lookup requires
# `Directory.Read.All` / `Group.Read.All` on the Terraform SP — a
# playground SP typically doesn't hold either, and granting them needs
# tenant admin consent. Passing the name explicitly avoids that
# escalation.
#
# Fetch once from an INTERACTIVE az login session:
#   az ad group show \
#     --group "<pg_entra_admin_group_object_id>" \
#     --query displayName -o tsv
pg_entra_admin_group_name = "az-dev-pg-admins"

# -----------------------------------------------------------------------------
# Common resource tags
# -----------------------------------------------------------------------------
# Applied to every resource in every module via `tags = var.tags` (optionally
# merged with a module-local map). Keeps cost tracking, ownership, and
# environment labelling consistent across the estate.
#
# NOTE: every resource also carries a `release` tag that is deliberately NOT in
# this map. It is computed, not configured — each module root reads the
# repo-root VERSION file (see <NN-module>/locals.tf) and merges
# `release = local.release` in here. Setting it by hand would let the label
# drift from the actual git tag. See RELEASING.md.
tags = {
  managedBy   = "terraform"
  environment = "dev"
  owner       = "rubens"
  costCenter  = "learning"
  project     = "azure-iac"
}
