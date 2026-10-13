#!/usr/bin/env bash
## SPDX-License-Identifier: MIT
##
## Prints whether each given Azure RBAC role grants control-plane
## (actions) and data-plane (dataActions) permissions.
##
## Requirements:
##  1) Bash functions libraries installed at "${HOME}/lib/sh-lib".
##  2) GNU bash version 4.2 or higher.
##  3) Azure CLI (az), signed in.
##  4) getopt from util-linux 2.30.2 or higher.
##
## This project's source code and documentation were generated with
## the assistance of Artificial Intelligence (AI). For more
## information, please refer to the `AI_DISCLAIMER.md` document
## located in the project's root directory.
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

# minimum Bash major / minor version required
# shellcheck disable=SC2034
readonly BASH_MAJOR_VERSION="4"
# shellcheck disable=SC2034
readonly BASH_MINOR_VERSION="2"

# Set to TRUE when debugging code using bassupport-pro.  This is
# required to bypass trap handlers which crashes code when running
# from debugger
readonly IS_DEBUGGER=FALSE

# output column widths
[[ -z "${ROLE_COLUMN_WIDTH:-}" ]] && readonly ROLE_COLUMN_WIDTH=40
[[ -z "${CONTROL_COLUMN_WIDTH:-}" ]] \
  && readonly CONTROL_COLUMN_WIDTH=13

# extra tools required by this script to run.
[[ ! -v REQUIRED_TOOLS ]] && readonly -a REQUIRED_TOOLS=(
  "az"
  "getopt"
)

#####################################################################
## INCLUDES #########################################################

[[ -d "${HOME}/lib/sh-lib" ]] || {
  printf "missing %s\n" "${HOME}/lib/sh-lib" >&2
  exit 1
}

# -------------------- >>> Import Basic Libraries <<< ---------------

# logging message library
# shellcheck source=/dev/null
source "${HOME}/lib/sh-lib/msg_lib.sh" || exit

# operating system library
# shellcheck source=/dev/null
source "${HOME}/lib/sh-lib/os_lib.sh" || exit

# bash library
# shellcheck source=/dev/null
source "${HOME}/lib/sh-lib/sh_lib.sh" || exit


#####################################################################
## GLOBAL VARIABLES #################################################

# Role names given on the command line
declare -a g_role_names=()


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
  cat <<EOF

"${PRG}" prints whether each Azure RBAC role grants control-plane
(actions) and data-plane (dataActions) permissions.

Usage:
  ${PRG} [options] <role-name> [<role-name> ...]

General Non Argument Options:

  -d, --debug                  prints debug messages
  -h, --help                   prints this help
  -q, --quiet                  prints only error|fatal messages
  -v, --verbose                adds extra details to messages
  -x, --trace                  traces commands

role-name (**required**):
  An Azure RBAC role name, quoted when it has spaces, for example
  "Foundry User". Unknown roles are reported to stderr.

Example:
  ${PRG} "Foundry User" "Contributor" "Storage Blob Data Reader"

EOF
}

#####################################################################
## Prints usage to stderr.
## Globals:
##  PRG
## Arguments:
##  none.
## Exits:
##   2 always
#####################################################################
usage() {
  cat <<EOF
Usage:  ${PRG} [options] <role-name> [<role-name> ...]
More information with: "${PRG} -h"
EOF

  # return an error status
  return 2
} >&2

#####################################################################
## Initializes global variables to their initial state. That is,
## reset them.
## Globals:
##  g_role_names
## Arguments:
##  None
#  Returns:
##   0 if okay; something else if fails.
#####################################################################
reset_globals() {
  g_role_names=()
}

#####################################################################
## Parses user's command line input option arguments.
## Globals:
##  g_role_names
## Arguments:
##  Bash shell CLI input arguments.
#  Returns:
##   0 if okay; something else if fails.
#####################################################################
parse_options() {
  reset_globals

  local temp

  if ! temp=$(
    getopt \
      --o 'dhqvx' \
      --long 'debug,help,quiet,trace,verbose' \
      --name "${PRG}" \
      -- "${@}"
  ); then
    msg::error "failed to parse CLI input arguments."
    usage
    return 2
  fi

  eval set -- "${temp}"
  local quiet=FALSE

  while true; do

    case "${1}" in

      ########## --debug ############################################
      '-d' | '--debug')
        if [[ "${quiet}" == TRUE ]]; then
          msg::warn "-q option has been passed, and it overrides -d"
        else
          msg::enable_debug
        fi
        shift
        continue
        ;;

      ########## --help #############################################
      '-h' | '--help')
        help
        exit 0
        ;;

      ########## --quiet ############################################
      '-q' | '--quiet')
        quiet=TRUE
        msg::enable_quiet
        shift
        continue
        ;;

      ########## --verbose ##########################################
      '-v' | '--verbose')
        msg::enable_verbose
        shift
        continue
        ;;

      ########## --trace ############################################
      '-x' | '--trace')
        msg::enable_tracing
        shift
        continue
        ;;

      ########## -- #################################################
      '--')
        shift
        break
        ;;

      ########## * ##################################################
      *)
        msg::arg_error "invalid option [%s].\n" "${1}"
        usage
        return 2
        ;;

    esac
  done

  if (( ${#} == 0 )); then
    msg::error "missing [%s] argument.\n" "<role-name>"
    usage
    return 2
  fi

  g_role_names=("${@}")
  msg::debug "%s completed successfully.\n" "${FUNCNAME[0]}"
}

#####################################################################
## Checks required tool.
## Globals:
##  REQUIRED_TOOLS
## Arguments:
##  None
## Returns:
##   0 if okay, something else if fails.
#####################################################################
check_required_tool() {
  msg::debug "entering %s:%s\n" "${FUNCNAME[0]}" "${LINENO}"

  local tool

  for tool in "${REQUIRED_TOOLS[@]}"; do

    if ! os::is_installed "${tool}"; then
      msg::warn "Missing a required tool [%s].\n" "${tool}"
      return 127
    fi

  done

}

#####################################################################
## Prints one aligned output row to stdout.
## Globals:
##  ROLE_COLUMN_WIDTH
##  CONTROL_COLUMN_WIDTH
## Arguments:
##  $1 role name, $2 control-plane value, $3 data-plane value.
## Returns:
##   0 always
#####################################################################
print_row() {
  printf "%-${ROLE_COLUMN_WIDTH}s %-${CONTROL_COLUMN_WIDTH}s %s\n" \
    "${1}" "${2}" "${3}"
}

#####################################################################
## Prints the control-plane and data-plane flags of one role.
## Globals:
##  None
## Arguments:
##  $1 role name.
## Returns:
##   0 if found; 1 if the role does not exist; az status on error.
#####################################################################
print_role_planes() {
  local -r role_name="${1}"
  # an object, not a list, so tsv prints one tab-separated row
  local -r query="[0].{role: roleName,
    control: length(permissions[0].actions) > \`0\`,
    data: length(permissions[0].dataActions) > \`0\`}"
  local result

  result="$(
    az role definition list \
      --name "${role_name}" \
      --query "${query}" \
      -o tsv
  )" || return

  if [[ -z "${result}" ]]; then
    msg::warn "role not found [%s].\n" "${role_name}"
    return 1
  fi

  local name control data
  IFS=$'\t' read -r name control data <<< "${result}"
  print_row "${name}" "${control}" "${data}"
}

#####################################################################
## Prints the plane flags of every role, continuing past unknown
## roles.
## Globals:
##  None
## Arguments:
##  Role names.
## Returns:
##   0 if every role was found; 1 otherwise.
#####################################################################
print_all_roles() {
  local missing_count=0
  local role_name

  print_row "ROLE" "CONTROL_PLANE" "DATA_PLANE"

  for role_name in "${@}"; do

    if ! print_role_planes "${role_name}"; then
      missing_count=$(( missing_count + 1 ))
    fi

  done

  (( missing_count == 0 ))
}

#####################################################################
## Catches and handles signals defined in the "trap" command.
## Globals:
##  FUNCNAME
##  LINENO
## Arguments:
##  $1 signal name.
## Exits:
##   exit status code based on signal being handled.
#####################################################################
signal_handler() {
  local -r rc=$?
  msg::debug "entering %s:%s\n" "${FUNCNAME[0]}" "${LINENO}"

  local -r signal="${1:-}"
  msg::debug "handling signal [%s].\n" "${signal}"

  # disables following signals to avoid looping
  trap - ERR
  trap - EXIT
  trap - HUP  # signal 1
  trap - INT  # signal 2
  trap - QUIT # signal 3
  trap - TERM # signal 15

  local exit_code

  case "${signal}" in
    HUP)
      msg::warn \
        "the shell controlling terminal was hung: %s\n" \
        "SIGHUP"
      exit_code=129 # 1+128
      ;;
    INT)
      msg::warn \
        "execution interrupted by the user (control-c): %s\n" \
        "SIGINT"
      exit_code=130 # 2+128
      ;;
    QUIT)
      msg::warn \
        "execution interrupted due to unexpected event: %s\n" \
        "SIGQUIT"
      exit_code=131 # 3+128
      ;;
    TERM)
      msg::warn "someone asked the current execution to stop: %s\n" \
        "SIGTERM"
      exit_code=143 # 15+128
      ;;
    ERR)
      msg::warn "execution interrupted by Bash ERR signal: %s\n" \
        "SIGERR"
      exit_code=${rc}
      ;;
    EXIT)
      msg::debug "handling %s event\n" "SIGEXIT"
      exit_code=${rc}
      ;;
    *)
      msg::warn "unexpected signal: %s\n" "${signal}"
      ;;
  esac

  if [[ -n "${exit_code:-}" ]]; then
    exit "${exit_code}"
  fi

  exit
}

#####################################################################
## Main function.
## Globals:
##  IS_DEBUGGER
##  PRG
##  g_role_names
## Arguments:
##  Bash shell CLI input arguments.
## Returns:
##   0 if okay; something else if fails.
#####################################################################
main() {
  reset_globals

  # --------------- >>> Check Required Tools <<< --------------------

  check_required_tool || return

  # --------------- >>> Parse CLI Input Arguments <<< ---------------

  parse_options "$@" || return

  msg::debug "Bash version: %s\n" "${BASH_VERSION}"
  msg::info "Running %s\n" "${PRG}"

  # --------------- >>>  Basic Shell Init / Trap Handlers <<< -------

  # bassupport-pro debugger crashes if following code is run
  if [[ "${IS_DEBUGGER}" != TRUE ]]; then
    sh::init || return
    local -ar signals=("ERR" "HUP" "INT" "TERM" "QUIT" "EXIT")
    sh::curry_trap_command "signal_handler" "${signals[*]}" || return
  fi

  # --------------- >>> Print Script State  <<<  --------------------

  msg::debug "[%s]: %s\n" "IS_DEBUGGER" "${IS_DEBUGGER}"
  msg::debug "[%s]: %s\n" "PRG" "${PRG}"
  msg::debug "[%s]: %s\n" "g_role_names" "${g_role_names[*]}"

  # --------------- >>> Print Role Planes  <<< ----------------------

  print_all_roles "${g_role_names[@]}"
}

#####################################################################
## ------------------------------------------------------------------
## -------------------- >>> Main Program Body <<< -------------------
## ------------------------------------------------------------------

if ! main "$@"; then
  printf "\n%s failed!\n" "${PRG}" >&2
  exit 1
fi
