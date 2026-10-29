#!/usr/bin/env bash
## SPDX-License-Identifier: MIT
##
## Prints the short code appended to resource names for an Azure
## region, read from terraform/modules/region-code/region-codes.json.
##
## Requirements:
##  1) GNU bash version 4.2 or higher.
##  2) jq.
##
## Author: Rubens Gomes
## NOTE:   Initial implementation was generated with AI assistance
##         and subsequently reviewed and approved by the author.


#####################################################################
## GLOBAL CONSTANTS #################################################

# shell script program name
declare PRG
PRG="$(
  basename -- "${0}" || {
    printf "failed to determine the program basename." >&2
    exit 1
  }
)"
readonly PRG

# region-to-code map shared with modules/region-code
declare CODES_FILE
CODES_FILE="$(
  cd -- "$(dirname -- "${0}")/.." && pwd
)/terraform/modules/region-code/region-codes.json"
readonly CODES_FILE

# extra tools required by this script to run.
readonly -a REQUIRED_TOOLS=("jq")


#####################################################################
## FUNCTIONS ########################################################

#####################################################################
## Prints help to stdout.
## Globals:
##  PRG
## Arguments:
##  none.
## Returns:
##   0 always
#####################################################################
help() {
  cat <<HELP

"${PRG}" prints the short region code used in resource names.

Usage:
  ${PRG} <location>
  ${PRG} -h | --help

location (**required**):
  Azure region name, e.g. "eastus2" or "East US 2".

Exits 1 when the region has no code in:
  ${CODES_FILE}

HELP
}

#####################################################################
## Prints usage to stderr.
## Globals:
##  PRG
## Arguments:
##  none.
## Returns:
##   2 always
#####################################################################
usage() {
  cat <<USAGE
Usage:  ${PRG} <location>
More information with: "${PRG} -h"
USAGE

  return 2
} >&2

#####################################################################
## Checks required tools.
## Globals:
##  REQUIRED_TOOLS
## Arguments:
##  None
## Returns:
##   0 if okay, 127 if a tool is missing.
#####################################################################
check_required_tool() {
  local tool

  for tool in "${REQUIRED_TOOLS[@]}"; do

    if ! command -v "${tool}" >/dev/null 2>&1; then
      printf "%s: missing required tool [%s].\n" \
        "${PRG}" "${tool}" >&2
      return 127
    fi

  done

}

#####################################################################
## Prints the code for a region.
## Globals:
##  CODES_FILE
##  PRG
## Arguments:
##  $1 - Azure region name.
## Returns:
##   0 if found; 1 otherwise.
#####################################################################
print_region_code() {
  local -r location="${1}"
  local normalized="${location// /}"
  normalized="${normalized,,}"

  if [[ ! -f "${CODES_FILE}" ]]; then
    printf "%s: missing [%s].\n" "${PRG}" "${CODES_FILE}" >&2
    return 1
  fi

  local code
  code="$(
    jq -r --arg region "${normalized}" '.[$region] // empty' \
      "${CODES_FILE}"
  )" || return

  if [[ -z "${code}" ]]; then
    printf "%s: no code for region [%s]; see %s.\n" \
      "${PRG}" "${location}" "docs/NAMING.md#region-codes" >&2
    return 1
  fi

  printf "%s\n" "${code}"
}

#####################################################################
## Main function.
## Globals:
##  None
## Arguments:
##  Bash shell CLI input arguments.
## Returns:
##   0 if okay; something else if fails.
#####################################################################
main() {
  set -o errexit -o nounset -o pipefail

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    help
    return 0
  fi

  if [[ $# -ne 1 || -z "${1// /}" ]]; then
    usage
    return
  fi

  check_required_tool || return
  print_region_code "${1}"
}

#####################################################################
## ------------------------------------------------------------------
## -------------------- >>> Main Program Body <<< -------------------
## ------------------------------------------------------------------

main "$@"
