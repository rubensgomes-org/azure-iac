# envs/dev/<NN-module>/locals.tf
# -----------------------------------------------------------------------------
# Release stamp.
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

# -----------------------------------------------------------------------------
# Common tags.
#
# `../tags.json` is the committed source of truth for the tag map applied
# across this environment, and it is read from disk here for the same reason
# VERSION is. `.gitignore` excludes `*.tfvars` and `*.tfvars.json`, so a shared
# tfvars file can never live in source control; reading a committed file makes
# the tags identical however terraform is invoked, with no `-var-file` to
# forget. JSON rather than HCL because Terraform has `jsondecode()` and no
# HCL-decode equivalent.
#
# `owner` is additionally exposed as a variable so a single operator can
# override that one key via `TF_VAR_owner` without restating the whole map.
# `coalesce` takes the first non-null, non-empty argument: the env var when
# set, the committed default otherwise, and never an empty tag. Preferred over
# a `var.owner == null ? {} : {...}` conditional, whose differing branch object
# types can fail Terraform's type unification.
#
# Merge order is deliberate: committed defaults first, then any caller `-var` /
# `-var-file` override, then `owner` and `release` last so neither can be
# silently shadowed by a caller-supplied map.
# -----------------------------------------------------------------------------

locals {
  release     = trimspace(file("${path.root}/../../../../VERSION"))
  common_tags = jsondecode(file("${path.root}/../tags.json"))
  owner       = coalesce(var.owner, local.common_tags.owner)

  tags = merge(local.common_tags, var.tags, {
    owner   = local.owner
    release = local.release
  })
}
