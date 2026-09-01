# Common gotchas

Things that have already cost time in this repo. `CLAUDE.md` lists the
silent and destructive ones as one-liners; the explanations are here.

- **Check a region before moving the estate to it**. The subscription is
  offer-restricted from provisioning PG Flexible Server in some regions, which
  is what forced module 09's old per-module override. Verify with
  `az postgres flexible-server list-skus --location <region>` before editing
  `location` in `env.tfvars`.
- **The state backend's region is independent of the estate's**, and changing it
  is destructive. `backend.hcl` has no region field, and the azurerm backend
  addresses state by RG + account + container name, so a state blob's region
  does not matter. But `location` is ForceNew on `azurerm_resource_group`:
  editing it in `bootstrap-backend/terraform.tfvars` plans a destroy of
  `rg-tfstate` and every state blob under it, and Azure cannot move a Storage
  Account between regions, so it would also need a new globally-unique name.
- **Backend blocks are empty**. `-backend-config=../backend.hcl` supplies
  literals at init time; `-backend-config="key=..."` supplies the per-module
  state path. If you edit `backend.hcl`, re-run `terraform init -reconfigure`
  in each module.
- **Key Vault soft-delete needs no manual purge**. Dev settings use
  `purge_protection_enabled = false` and `soft_delete_retention_days = 7`, but
  module 05's `features {}` leaves `key_vault.purge_soft_delete_on_destroy` at
  its default `true` — the provider purges during destroy. Running
  `az keyvault purge` afterwards fails with `DeletedVaultNotFound`, which reads
  as breakage but means it already worked.
- **Azure litters an action group into `rg-dev-observability`**. Creating an
  Application Insights component makes Azure also create
  `Application Insights Smart Detection`, which Terraform never owns. It
  survives module 12's destroy and then blocks module 01's RG delete via
  `prevent_deletion_if_contains_resources`. Recurs every teardown;
  `make destroy` sweeps it automatically, `make purge-orphans` does it alone.
  Delete by `--ids`, never `-n` — the name has spaces and az mis-parses it.
- **Several documented `az` flags don't exist**. `az postgres flexible-server
  list --show-deleted` is not a real command (no `list-deleted` either) and
  used to fail silently into a `|| true` that reported success. Verify az
  invocations actually work before trusting them in a recipe.
- **PostgreSQL Entra-only auth**. The Terraform SP must be a member of the
  Entra group referenced by `pg_entra_admin_group_object_id` in `env.tfvars`.
  Without membership, module 09's data-plane step (registering the shared
  UAMI as a PG role) fails.
- **Destroy order matters**. Delegated subnets (`snet-app`, `snet-pg`) will
  refuse to destroy while their delegated resources exist. Always tear down
  container-apps → CAE → PG before networking.
- **Never put `$(MAKE)` inside a multi-command recipe line**. GNU Make executes
  any recipe line containing `$(MAKE)` even under `-n`. Because `destroy` is
  one backslash-continued logical line, a `$(MAKE)` in it made `make -n destroy`
  run the whole teardown for real. Shared shell logic goes in a `define`
  variable inlined into the recipe (see `SWEEP_ORPHANS`). A `$(MAKE)` on its
  own recipe line — as in `reprovision` — is fine: the sub-make inherits `-n`.
- **No GNU coreutils on macOS**. Neither `tac` nor `timeout` exists here. The Makefile's
  destroy loop used to build its module list with `... | tac`, which returned
  empty on darwin, iterated zero times, and reported success having destroyed
  nothing — surfacing only as a baffling `DeletedVaultNotFound` from the purge
  step that follows. Reversal is now done in pure Make. Don't reintroduce
  shell-level GNU-only tools (`tac`, `seq`, `readlink -f`, `xargs -r`,
  `sed -i` without a suffix) in Makefile recipes.
- **PG child-resource deletes time out at 30 minutes**. Destroying module 09
  routinely stalls, then fails on all five children at once (2 firewall rules,
  2 databases, the Entra admin) with `HTTP response was nil` or
  `context deadline exceeded`. Azure serializes control-plane ops on the
  server, so the parallel deletes queue past the provider's default 30m
  timeout. Deleting the *server* cascades to every child — so
  `az postgres flexible-server delete -g rg-dev-data -n <name> --yes`, then
  re-run the destroy and it no-ops. See `docs/PROVISIONING_PLAN.md` §15.
- **A failed module aborts `make destroy` entirely**. The loop runs under
  `set -e`; everything below the failing module is left untouched. The loop is
  idempotent and resumable — fix the module, re-run `make destroy`.
- **A `VERSION` bump makes every module show a pending tag diff**. Each module
  root stamps `release = local.release` (read from `VERSION`) into `var.tags`,
  so right after `make release-minor`, `terraform plan` reports a `~ tags`
  update on every resource in all twelve modules. That is the intended drift
  signal — code at the new release, Azure still labelled with the old one —
  not a bug. It clears on the next `make apply`. Tag changes are in-place
  updates in `azurerm`; a version bump never recreates a resource.
- **"Not authorized or project not found ... check the `SONAR_TOKEN`" from the
  release workflow is usually NOT a token problem.** `release.yml` fires on a
  tag push, so `GITHUB_REF` is `refs/tags/vX.Y.Z`; the scanner auto-detects
  GitHub Actions and submits the analysis as a SHORT-lived branch of that name.
  The submit succeeds, then the gate lookup
  (`api/qualitygates/project_status?analysisId=...`) 403s, because short-lived
  branch gate status is not readable on this plan — and the scanner reports
  that as a credentials error. `release.yml` passes
  `args: -Dsonar.branch.name=main` to prevent it. Diagnose this class of
  failure by reading the DEBUG log for the `api/ce/submit` URL and checking
  whether `characteristic=branch=` says anything other than `main`, and by
  hitting `api/qualitygates/project_status?analysisId=<id>` anonymously — if it
  403s without a token, no token change will fix it.
- **`sonar.branch.name=main` IS pinned in `sonar-project.properties`**, and all
  three callers (`main-verify.yml`, `release.yml`, `make sonar`) pass the
  scanner no arguments at all. `main` is the only branch, so there is one
  correct value. The pin is load-bearing for `release.yml`: it fires on a tag
  ref, which without it is submitted as a short-lived branch whose gate lookup
  403s on this plan — that is what cost the v0.3.0 release. It was briefly
  removed for the PR-only model (v0.4.0–v0.4.2), when a global pin would have
  made every PR analysis overwrite main's; restore the per-caller arguments
  only if pull requests ever come back.
- **`make sonar` refuses to run off `main`**, because it would publish that
  branch's code as main's analysis.
- **Nothing scans between commits unless you ask.** The tag gate
  (`release.yml`) scans automatically; `main-verify.yml` is dispatch-only. To
  scan before tagging, either run `make sonar` locally or dispatch
  `main-verify.yml` — the dispatch is usually better, since it runs natively on
  Linux. On Apple Silicon the
  scanner image runs emulated and blames through JGit rather than the git CLI —
  measured at minutes for ~144 files against ~1s for native `git blame`, and
  worse once `main` has merge commits for JGit to walk both parents of.
  `SCM blame is in progress..` means it is working, not hung. Let CI do it.
- **`make sonar` stopping dead at "SCM Publisher N source files to be
  analyzed" — with no "blame is in progress" line — is a different thing: a
  git ownership problem, not a slow scan.** The scanner container runs as uid
  1000 while the bind-mounted tree belongs to the host user, so git rejects the
  repo with *detected dubious ownership* and the SCM publisher falls back off
  the native blame path onto its own history walk — which, on an amd64 image
  emulated on Apple Silicon over a macOS bind mount, looks exactly like a hang.
  The `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` trio in the
  `sonar` recipe sets `safe.directory` through the environment and fixes it.
  Do not reach for `sonar.scm.disabled=true` instead: every quality-gate
  condition is a `new_*` metric, and those are attributed from blame data, so
  disabling SCM changes which findings the gate counts. CI is unaffected —
  it runs natively on Linux against its own checkout.
- **`make sonar` dirties the tree, and `release-check` fails on a dirty tree.**
  The scanner writes `.scannerwork/` at the repo root. It is gitignored, so this
  only bites if that entry is ever removed — the symptom is a `make release-*`
  that aborts complaining about uncommitted changes right after a scan.
- **`make validate` breaks `terraform output`**. Validate inits with
  `-backend=false`, leaving every module's `.terraform/` pointed at an empty
  local backend. Any later `terraform output` returns nothing until the
  directory is re-init'd against the azurerm backend. `.terraform/terraform.tfstate`
  is present only when a directory is init'd against the real backend — use it
  to tell the two states apart.
