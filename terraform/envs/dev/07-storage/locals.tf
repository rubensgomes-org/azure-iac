# envs/dev/<NN-module>/locals.tf
# -----------------------------------------------------------------------------
# Release stamp. See RELEASING.md and docs/PROVISIONING_PLAN.md section 16.
#
# The repo-root VERSION file is the single source of truth for the release
# number, and it is read HERE — directly from disk — rather than being threaded
# in as a `-var`. That way the stamp is identical no matter how terraform is
# invoked: `make apply`, CI, or a bare `terraform apply` typed by hand in this
# directory. A `-var` would have been silently omitted by the last of those and
# quietly mislabelled the estate.
#
# Path: this directory is terraform/envs/dev/<NN-module>/, so four levels up is
# the repo root. `path.root` is the module root terraform was invoked in, which
# for every root under envs/ is this directory.
#
# Consequence worth knowing before you plan: bumping VERSION immediately makes
# `terraform plan` show a pending `~ tags` update on every resource in all
# twelve modules. That diff is the intended signal — the code is at the new
# release, Azure is still labelled with the old one — and it clears on the next
# apply. Tag changes are in-place updates in azurerm; nothing is recreated.
# -----------------------------------------------------------------------------

locals {
  release = trimspace(file("${path.root}/../../../../VERSION"))
}
