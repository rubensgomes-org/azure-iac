#!/usr/bin/env bash
#
# Reset this repository's GitHub Actions *variables* to the values held by the
# current shell.
#
# Usage:
#   scripts/initvars.sh [-v|--verbose] [-h|--help]
#
# Examples:
#   scripts/initvars.sh              # prompt, then reset
#   scripts/initvars.sh --verbose    # same, narrating each step
#
# Requires: bash 4+ (associative arrays; macOS /bin/bash is 3.2, so this uses
# `env bash` to pick up a newer one from PATH) and an authenticated `gh`.

set -o errexit
set -o nounset
set -o pipefail

#######################################
# Interpreter guard.
#
# Associative arrays arrived in bash 4.0. macOS still ships 3.2 as /bin/bash,
# where `declare -A` fails at runtime with a misleading "invalid option"
# error. Fail here instead, with a message that says what to do.
#######################################
if (( BASH_VERSINFO[0] < 4 )); then
  echo "ERROR: bash 4+ required; running ${BASH_VERSION}." >&2
  echo "       On macOS: brew install bash" >&2
  exit 1
fi

#######################################
# Constants.
#######################################

# Exit codes, so a caller can tell the failures apart.
readonly EXIT_USAGE=2          # bad command line
readonly EXIT_MISSING_DEP=3    # gh not installed or not authenticated
readonly EXIT_MISSING_VALUE=4  # a required value is not in the environment
readonly EXIT_NO_REPO=5        # target repository could not be resolved
readonly EXIT_DECLINED=6       # user answered anything but Y at the prompt
readonly EXIT_GH_FAILED=7      # a `gh variable` call failed

# Set by parse_command_line(); consulted by log().
VERBOSE="false"

# Set by resolve_repository(); the OWNER/REPO every `gh` call targets.
TARGET_REPOSITORY=""

#######################################
# The Actions variables this script manages.
#
# Keys are the variable names exactly as they appear in the repository
# settings and in docs/INITIAL_SETUP.md. Values are resolved when this
# file is sourced: the shell environment first, then the literal documented in
# INITIAL_SETUP.md.
#
# An empty value means "no documented default, and nothing exported" — see
# REQUIRED_VARIABLE_SOURCES below and validate_variable_values().
#
# Bash does not preserve associative-array order, so ACTION_VARIABLE_ORDER
# below fixes it to INITIAL_SETUP.md's order. Keep the two in step.
#######################################
declare -Ar ACTION_VARIABLES=(
  # --- Azure service principal coordinates (no documented literal) ---------
  # INITIAL_SETUP.md derives ARM_* from AZURE_*, so accept either spelling.
  [AZURE_CLIENT_ID]="${AZURE_CLIENT_ID:-${ARM_CLIENT_ID:-}}"
  [AZURE_SUBSCRIPTION_ID]="${AZURE_SUBSCRIPTION_ID:-${ARM_SUBSCRIPTION_ID:-}}"
  [AZURE_TENANT_ID]="${AZURE_TENANT_ID:-${ARM_TENANT_ID:-}}"

  # --- Remote state backend coordinates -----------------------------------
  # These must keep matching terraform/envs/<env>/backend.hcl. Each root
  # declares the like-named variables as REQUIRED with no default, so a value
  # missing here does not silently aim `terraform init` at another
  # environment's storage account -- Terraform stops and names the variable.
  [TF_VAR_ENV]="${TF_VAR_env:-lab}"
  [TF_VAR_BACKEND_RESOURCE_GROUP_NAME]="${TF_VAR_backend_resource_group_name:-rg-rgomestfstate-lab}"
  [TF_VAR_STORAGE_ACCOUNT_ID]="${TF_VAR_storage_account_id:-strgomestfstate02}"
  [TF_VAR_CONTAINER_NAME]="${TF_VAR_container_name:-rgomes-lab-tfstate}"

  # --- Estate-wide Terraform inputs ---------------------------------------
  # NOT here: the environment. acr-create.yml, acr-destroy.yml and
  # destroy-all.yml each bind TF_VAR_env from their `environment_name` dispatch
  # input, so one run can target lab and the next dev. A repository variable
  # would pin every run to a single environment instead.
  [TF_VAR_LOCATION]="${TF_VAR_location:-centralus}"
  [TF_VAR_OWNER]="${TF_VAR_owner:-rubens.gomes@3cloudsolutions.com}"
  [TF_VAR_APPS]="${TF_VAR_apps:-[ \"api\", \"worker\" ]}"

  # CAF workload token. With `env`, this names every resource in the estate
  # (rg-rgomesapp-lab, kv-rgomes-lab, strgomesapplab, ...). It replaced the
  # former TF_VAR_PREFIX and TF_VAR_RG_SUFFIX pair, which split the same idea
  # across two variables that had to agree; see RETIRED_ACTION_VARIABLES below.
  # `rgomes` is every module's declared default and the fallback in the
  # workflows and the Makefile — three consumers, one value. Changing it
  # renames the entire estate (ForceNew).
  [TF_VAR_WORKLOAD]="${TF_VAR_workload:-rgomes}"

  # ACR is the estate's one name NOT composed from workload + env; it is
  # supplied verbatim. Follow the convention anyway: cr<workload><env>.
  [TF_VAR_ACR_NAME]="${TF_VAR_acr_name:-crrgomesdev01}"
  [TF_VAR_ACTION_GROUP_EMAIL]="${TF_VAR_action_group_email:-rubens.gomes@3cloudsolutions.com}"

  # PostgreSQL Entra admin group. The object ID is tenant-specific, so
  # INITIAL_SETUP.md shows a placeholder rather than a literal.
  [TF_VAR_PG_ENTRA_ADMIN_GROUP_OBJECT_ID]="${TF_VAR_pg_entra_admin_group_object_id:-}"
  [TF_VAR_PG_ENTRA_ADMIN_GROUP_NAME]="${TF_VAR_pg_entra_admin_group_name:-az-lab-pg-admins}"
)

# Presentation order. Mirrors docs/INITIAL_SETUP.md so a reader can diff
# the two by eye.
declare -ar ACTION_VARIABLE_ORDER=(
  AZURE_CLIENT_ID
  AZURE_SUBSCRIPTION_ID
  AZURE_TENANT_ID
  TF_VAR_BACKEND_RESOURCE_GROUP_NAME
  TF_VAR_STORAGE_ACCOUNT_ID
  TF_VAR_CONTAINER_NAME
  TF_VAR_LOCATION
  TF_VAR_OWNER
  TF_VAR_APPS
  TF_VAR_WORKLOAD
  TF_VAR_ACR_NAME
  TF_VAR_ACTION_GROUP_EMAIL
  TF_VAR_PG_ENTRA_ADMIN_GROUP_OBJECT_ID
  TF_VAR_PG_ENTRA_ADMIN_GROUP_NAME
)

# Variables this script used to manage and no longer does. The delete phase
# sweeps these alongside ACTION_VARIABLE_ORDER; the create phase ignores them,
# so a repository provisioned before the CAF rename ends up with neither.
#
# Leaving them behind would be worse than untidy: TF_VAR_PREFIX and
# TF_VAR_RG_SUFFIX are still valid `TF_VAR_*` spellings, and a stale value of
# either is silently ignored by Terraform (no variable declares them any more)
# while still looking authoritative to whoever reads the repository's variable
# list. Delete them so the list matches the code.
declare -ar RETIRED_ACTION_VARIABLES=(
  TF_VAR_PREFIX
  TF_VAR_RG_SUFFIX
)

# Variables with no documented literal, mapped to the shell variable to
# export. Used only to make validate_variable_values()'s error actionable.
declare -Ar REQUIRED_VARIABLE_SOURCES=(
  [AZURE_CLIENT_ID]="AZURE_CLIENT_ID (or ARM_CLIENT_ID)"
  [AZURE_SUBSCRIPTION_ID]="AZURE_SUBSCRIPTION_ID (or ARM_SUBSCRIPTION_ID)"
  [AZURE_TENANT_ID]="AZURE_TENANT_ID (or ARM_TENANT_ID)"
  [TF_VAR_PG_ENTRA_ADMIN_GROUP_OBJECT_ID]="TF_VAR_pg_entra_admin_group_object_id"
)

#######################################
# Writes a verbose log line to stdout. No-op unless --verbose was given.
# Globals:
#   VERBOSE
# Arguments:
#   Message to log.
# Outputs:
#   Writes the message to stdout, prefixed and timestamped.
#######################################
log() {
  if [[ "${VERBOSE}" == "true" ]]; then
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
  fi
}

#######################################
# Writes an unconditional status line to stdout.
# Arguments:
#   Message to print.
# Outputs:
#   Writes the message to stdout.
#######################################
info() {
  printf '%s\n' "$*"
}

#######################################
# Writes an error to stderr and exits.
# Arguments:
#   $1: exit code.
#   $2..: message lines, one per argument.
# Outputs:
#   Writes the message to stderr.
# Returns:
#   Never returns; exits with $1.
#######################################
die() {
  local exit_code="$1"
  shift
  local line
  for line in "$@"; do
    printf 'ERROR: %s\n' "${line}" >&2
  done
  exit "${exit_code}"
}

#######################################
# Prints usage to stdout.
# Outputs:
#   Writes the usage block to stdout.
#######################################
usage() {
  cat <<'USAGE_EOF'
Usage: initvars.sh [-v|--verbose] [-h|--help]

Deletes every GitHub Actions repository variable listed in
docs/INITIAL_SETUP.md, then recreates it from the current shell
environment. Actions *secrets* are not touched.

Options:
  -v, --verbose   Narrate every step, including each delete and create.
  -h, --help      Print this help and exit.
USAGE_EOF
}

#######################################
# Parses the command line into globals.
# Globals:
#   VERBOSE (written)
# Arguments:
#   The script's own "$@".
# Returns:
#   0 on success; exits EXIT_USAGE on an unknown flag.
#######################################
parse_command_line() {
  while (( $# > 0 )); do
    case "$1" in
      -v | --verbose)
        VERBOSE="true"
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "${EXIT_USAGE}" "unknown argument: $1"
        ;;
    esac
    shift
  done
}

#######################################
# Verifies `gh` is installed and authenticated.
# Returns:
#   0 when usable; exits EXIT_MISSING_DEP otherwise.
#######################################
require_github_cli() {
  log 'Checking for the gh CLI.'
  if ! command -v gh > /dev/null 2>&1; then
    die "${EXIT_MISSING_DEP}" \
      'the gh CLI is not installed or not on PATH.' \
      'Install it: https://cli.github.com/'
  fi

  log 'Checking that gh is authenticated.'
  if ! gh auth status > /dev/null 2>&1; then
    die "${EXIT_MISSING_DEP}" \
      'gh is not authenticated.' \
      'Run: gh auth login'
  fi
}

#######################################
# Resolves the repository every `gh` call will target.
#
# Prefers GH_REPO (which `gh` itself honours) and otherwise asks `gh` to read
# the git remote. Resolving it explicitly means the value can be shown at the
# prompt, so a run against the wrong repository is caught before it deletes
# anything.
# Globals:
#   TARGET_REPOSITORY (written)
# Returns:
#   0 on success; exits EXIT_NO_REPO when no repository can be determined.
#######################################
resolve_repository() {
  if [[ -n "${GH_REPO:-}" ]]; then
    TARGET_REPOSITORY="${GH_REPO}"
    log "Repository taken from GH_REPO: ${TARGET_REPOSITORY}"
    return 0
  fi

  log 'GH_REPO is unset; resolving the repository from the git remote.'
  if ! TARGET_REPOSITORY="$(gh repo view --json nameWithOwner \
      --jq '.nameWithOwner' 2>/dev/null)"; then
    die "${EXIT_NO_REPO}" \
      'could not determine the target repository.' \
      'Run from inside the clone, or export GH_REPO=OWNER/REPO.'
  fi

  if [[ -z "${TARGET_REPOSITORY}" ]]; then
    die "${EXIT_NO_REPO}" \
      'the git remote resolved to an empty repository name.' \
      'Export GH_REPO=OWNER/REPO and retry.'
  fi

  log "Repository resolved from the git remote: ${TARGET_REPOSITORY}"
}

#######################################
# Fails if any managed variable resolved to an empty value.
#
# Only the entries in REQUIRED_VARIABLE_SOURCES can be empty — every other
# key carries a documented literal — but the check is written over the whole
# map so a future key without a default cannot slip through.
# Globals:
#   ACTION_VARIABLES, ACTION_VARIABLE_ORDER, REQUIRED_VARIABLE_SOURCES
# Returns:
#   0 when every value is set; exits EXIT_MISSING_VALUE otherwise.
#######################################
validate_variable_values() {
  local -a missing_names=()
  local variable_name

  log 'Validating that every managed variable resolved to a value.'
  for variable_name in "${ACTION_VARIABLE_ORDER[@]}"; do
    if [[ -z "${ACTION_VARIABLES[${variable_name}]}" ]]; then
      missing_names+=("${variable_name}")
    fi
  done

  if (( ${#missing_names[@]} == 0 )); then
    log 'All values present.'
    return 0
  fi

  {
    printf 'ERROR: %d variable(s) have no value.\n' "${#missing_names[@]}"
    printf 'Export the shell variable named below and retry:\n'
    for variable_name in "${missing_names[@]}"; do
      printf '  %-38s <- %s\n' "${variable_name}" \
        "${REQUIRED_VARIABLE_SOURCES[${variable_name}]:-${variable_name}}"
    done
    printf 'See docs/INITIAL_SETUP.md for where each value comes from.\n'
  } >&2
  exit "${EXIT_MISSING_VALUE}"
}

#######################################
# Prints the gh/git environment this run will act under.
#
# Shown before the prompt so the operator can confirm the host, repository and
# identity before anything is deleted.
# Globals:
#   TARGET_REPOSITORY
# Outputs:
#   Writes the environment block to stdout.
#######################################
print_gh_environment() {
  local -ar reported_variables=(
    GH_HOST
    GH_REPO
    GITHUB_USER
    GIT_AUTHOR_EMAIL
    GIT_COMMITTER_EMAIL
    GIT_AUTHOR_NAME
  )
  local variable_name

  info 'GitHub environment'
  info '------------------'
  for variable_name in "${reported_variables[@]}"; do
    printf '  %-20s %s\n' "${variable_name}" \
      "${!variable_name:-<unset>}"
  done
  printf '  %-20s %s\n' 'target repository' "${TARGET_REPOSITORY}"
  info ''
}

#######################################
# Prints the variables that will be deleted and recreated.
#
# Values are shown so a wrong one is caught at the prompt rather than after
# the fact. None of these are secrets — GitHub renders repository variables in
# plain text in the settings UI and in workflow logs.
# Globals:
#   ACTION_VARIABLES, ACTION_VARIABLE_ORDER
# Outputs:
#   Writes the variable table to stdout.
#######################################
print_planned_variables() {
  local variable_name

  info "Actions variables to reset (${#ACTION_VARIABLE_ORDER[@]}):"
  for variable_name in "${ACTION_VARIABLE_ORDER[@]}"; do
    printf '  %-38s = %s\n' "${variable_name}" \
      "${ACTION_VARIABLES[${variable_name}]}"
  done
  info ''
}

#######################################
# Prompts for confirmation and exits unless the answer is exactly Y or y.
# Globals:
#   TARGET_REPOSITORY
# Outputs:
#   Writes the prompt to stdout.
# Returns:
#   0 when confirmed; exits EXIT_DECLINED otherwise.
#######################################
confirm_or_exit() {
  local answer=""

  printf 'Delete and recreate these variables on %s? [Y/n] ' \
    "${TARGET_REPOSITORY}"

  # `read` returns non-zero at EOF (a piped or non-interactive run). Guard it
  # so `set -e` does not abort before the declined message is printed.
  if ! read -r answer; then
    answer=""
  fi

  if [[ "${answer}" != "Y" && "${answer}" != "y" ]]; then
    info 'Declined. Nothing was changed.'
    exit "${EXIT_DECLINED}"
  fi
  info ''
}

#######################################
# Lists the variable names that currently exist on the repository.
# Globals:
#   TARGET_REPOSITORY
# Outputs:
#   Writes one variable name per line to stdout.
# Returns:
#   0 on success; exits EXIT_GH_FAILED if the listing fails.
#######################################
list_remote_variable_names() {
  if ! gh variable list --repo "${TARGET_REPOSITORY}" \
      --json name --jq '.[].name' 2>/dev/null; then
    die "${EXIT_GH_FAILED}" \
      "could not list Actions variables on ${TARGET_REPOSITORY}." \
      'Check that the token carries the admin:repo scope.'
  fi
}

#######################################
# Deletes every managed variable that currently exists on the repository.
#
# Only variables present remotely are deleted: `gh variable delete` exits
# non-zero on an unknown name, and a partially-populated repository is the
# normal case (INITIAL_SETUP.md lists more variables than a repository
# provisioned before the list grew).
#
# RETIRED_ACTION_VARIABLES are swept here as well, so a repository provisioned
# before a variable was retired loses it on the next run. They are absent from
# the create phase, which is what makes the delete stick.
#
# Variables outside both lists are left alone — this script owns its map, not
# the whole namespace.
# Globals:
#   ACTION_VARIABLE_ORDER, RETIRED_ACTION_VARIABLES, TARGET_REPOSITORY
# Outputs:
#   Writes progress to stdout.
# Returns:
#   0 on success; exits EXIT_GH_FAILED on the first failed delete.
#######################################
delete_action_variables() {
  local remote_names
  local variable_name
  local deleted_count=0
  local skipped_count=0

  log "Listing existing variables on ${TARGET_REPOSITORY}."
  remote_names="$(list_remote_variable_names)"

  info 'Deleting Actions variables...'
  for variable_name in "${ACTION_VARIABLE_ORDER[@]}" "${RETIRED_ACTION_VARIABLES[@]}"; do
    # Exact line match, so TF_VAR_APPS never matches TF_VAR_APPS_EXTRA.
    if ! grep -Fxq "${variable_name}" <<< "${remote_names}"; then
      log "  skip   ${variable_name} (not present on the repository)"
      (( ++skipped_count ))
      continue
    fi

    log "  delete ${variable_name}"
    if ! gh variable delete "${variable_name}" \
        --repo "${TARGET_REPOSITORY}" > /dev/null 2>&1; then
      die "${EXIT_GH_FAILED}" \
        "failed to delete ${variable_name} on ${TARGET_REPOSITORY}."
    fi
    (( ++deleted_count ))
  done

  info "  deleted ${deleted_count}, skipped ${skipped_count} (absent)"
}

#######################################
# Creates every managed variable from the resolved map.
#
# `gh variable set` is an upsert, so this also repairs a run interrupted
# between the delete and create phases.
# Globals:
#   ACTION_VARIABLES, ACTION_VARIABLE_ORDER, TARGET_REPOSITORY
# Outputs:
#   Writes progress to stdout.
# Returns:
#   0 on success; exits EXIT_GH_FAILED on the first failed create.
#######################################
create_action_variables() {
  local variable_name
  local variable_value
  local created_count=0

  info 'Creating Actions variables...'
  for variable_name in "${ACTION_VARIABLE_ORDER[@]}"; do
    variable_value="${ACTION_VARIABLES[${variable_name}]}"

    log "  create ${variable_name}=${variable_value}"
    if ! gh variable set "${variable_name}" \
        --repo "${TARGET_REPOSITORY}" \
        --body "${variable_value}" > /dev/null 2>&1; then
      die "${EXIT_GH_FAILED}" \
        "failed to set ${variable_name} on ${TARGET_REPOSITORY}."
    fi
    (( ++created_count ))
  done

  info "  created ${created_count}"
}

#######################################
# Entry point.
# Arguments:
#   The script's own "$@".
#######################################
main() {
  parse_command_line "$@"

  log 'Starting initvars.sh'
  require_github_cli
  resolve_repository
  validate_variable_values

  print_gh_environment
  print_planned_variables
  confirm_or_exit

  delete_action_variables
  create_action_variables

  info ''
  info "Done. ${#ACTION_VARIABLE_ORDER[@]} variables reset on" \
    "${TARGET_REPOSITORY}."
  info 'Actions secrets were not touched.'
}

main "$@"
