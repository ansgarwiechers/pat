#!/bin/bash

# Copyright (C) 2022 Ansgar Wiechers <ansgar.wiechers@planetcobalt.net>
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.

# NOTE: Change these if you installed Puppet in a different path.
puppet_dir='/opt/puppetlabs'
agent_lockfile="${puppet_dir}/puppet/cache/state/agent_disabled.lock"

PATH="${PATH}:${puppet_dir}/bin"
LANG='C'
LC_ALL='C'

# error handling
error_handler() {
  echo "Unexpected error ${1} in ${2}, line ${3}, ${4}(): ${5}"
  exit "${1:-1}"
}
set -eETuo pipefail
trap 'error_handler "$?" "$0" "$LINENO" "${FUNCNAME[0]:-@}" "$BASH_COMMAND"' ERR

# == functions ================================================================

msg() {
  if [ -n "${1:-}" ]; then
    echo -e "$1"
  fi
}

warn() {
  msg "${1:-}" 1>&2
}

fail() {
  warn "${1:-}"
  exit "${2:-1}"
}

join() {
  local IFS="${1:-,}"
  shift
  [ "$#" -lt 1 ] || echo "$*"
}

is_disabled() {
  [ -f "$agent_lockfile" ]
}

# NOTE: This function is for disabling/enabling scheduled puppet runs along with
#       the agent itself. At my workplace we're using cron for scheduled runs.
#       If you don't do scheduled runs you can leave this as it is, because a
#       missing cron job will be simply ignored. However, if you use a different
#       cron job or an entirely different scheduling method you'll have to
#       modify this function accordingly.
scheduled_runs() {
  local puppet_cronjob='/etc/cron.d/puppet'
  case "${1:-}" in
    enable)
      if [ -f "${puppet_cronjob}.disabled" ] && [ ! -f "$puppet_cronjob" ]; then
        mv -f "${puppet_cronjob}.disabled" "$puppet_cronjob"
      fi
      ;;
    disable)
      if [ -f "$puppet_cronjob" ]; then
        mv -f "$puppet_cronjob" "${puppet_cronjob}.disabled"
      fi
      ;;
    *)
      fail "invalid argument: ${1:-}"
      ;;
  esac
}

# == argument parsing =========================================================

print_usage() {
  local scriptname="$(basename "$0")"
  cat <<EOF

Wrapper for the Puppet agent to provide a more convenient way of invoking
frequently used agent operations like enabling/disabling the agent or doing
dry-runs.

Usage: ${scriptname} [-n] [-f] [-v] [TAG ...]
       ${scriptname} -d [-f] [-u NAME] [REASON]
       ${scriptname} -e [-r]
       ${scriptname} -s
       ${scriptname} -h

       -h       Print this help.

       -d       Disable the Puppet agent.
       -e       Enable the Puppet agent.
       -f       Force agent run when the agent is disabled or force replacement
                of an already existing disable reason.
       -n       Do a dry-run (noop).
       -r       Run agent after enabling it.
       -s       Show agent status.
       -u NAME  Name to display along with disable reason. The parameter is
                mandatory unless the environment variable ADMIN_NAME is defined.
                If both the parameter and the environment variable are set, the
                parameter value takes precedence.
       -v       Verbose mode (run agent with --debug).

Without parameters a regular Puppet agent run is performed (puppet agent --test).

If the agent is disabled, it will be temporarily re-enabled for a dry-run or a
forced (live) run, and then disabled again with the same reason as before.

Disabling the agent also disables the Puppet agent cron job. Enabling the agent
restores a disabled Puppet agent cron job.

EOF
  exit "${1:-0}"
}

while getopts ':defhnrsu:v' OPT; do
  case "$OPT" in
    d) disable='y';;
    e) enable='y';;
    f) force='y';;
    h) print_usage;;
    n) noop='y';;
    r) run_after_enable='y';;
    s) show_status='y';;
    u) user="$OPTARG";;
    v) verbose='y';;
    [?]) warn "Not implemented: -${OPTARG}"; print_usage 1;;
    [:]) warn "Argument required: -${OPTARG}"; print_usage 1;;
  esac
done
shift $((OPTIND-1))

# Combinations of the options -d, -e, -n and -s are not allowed.
modetest="${disable:-}${enable:-}${noop:-}${show_status:-}"
if [ "${#modetest}" -gt 1 ]; then
  print_usage 1
fi

if [ "${disable:-}" = '' ] && [ "${enable:-}" = '' ] && [ "${show_status:-}" = '' ]; then
  action='test'
elif [ "${disable:-}" = 'y' ]; then
  user="${user:-${ADMIN_NAME:-}}"
  if [ -z "$user" ]; then
    print_usage 1
  fi
  action='disable'
  if [ "$#" -gt 0 ]; then
    reason="$*"
  fi
elif [ "${enable:-}" = 'y' ]; then
  action='enable'
elif [ "${show_status:-}" = 'y' ]; then
  action='status'
fi

# == main =====================================================================

if [ ! -x "$(command -v puppet)" ]; then
  fail 'Command not found: puppet. Is the Puppet agent installed?'
fi
if [ ! -x "$(command -v jq)" ]; then
  fail 'Command not found: jq. Please install the jq utility.'
fi

case "$action" in
  disable)
    full_reason="[${user} $(date +'%F')]${reason:+ }${reason:-}"
    scheduled_runs disable
    if ! is_disabled; then
      puppet agent --disable "$full_reason"
    elif [ "${force:-}" = 'y' ]; then
      # replace reason
      jq -r '.disabled_message="'"$full_reason"'"' "$agent_lockfile" >"${agent_lockfile}.tmp"
      mv -f "${agent_lockfile}.tmp" "$agent_lockfile"
    else
      msg "Puppet agent is already disabled: $(jq -r '.disabled_message' "$agent_lockfile")"
    fi
    ;;
  enable)
    puppet agent --enable
    scheduled_runs enable
    if [ "${run_after_enable:-}" = 'y' ]; then
      puppet agent --test || exit_status="${?:-1}"
    fi
    ;;
  status)
    if is_disabled; then
      reason="$(jq -r '.disabled_message' "$agent_lockfile" || true)"
      if [ -n "$reason" ]; then
        reason=" (${reason})"
      fi
      agent_status="disabled${reason}"
    else
      agent_status="enabled"
    fi
    echo "Puppetserver: $(grep -oP '^\s*server\s*=\s*\K.*' /etc/puppetlabs/puppet/puppet.conf 2>/dev/null || true)"
    echo "Puppet Agent: ${agent_status}"
    ;;
  test)
    declare -a agent_args=(
      --test
    )
    if [ "${noop:-}" = 'y' ]; then
      agent_args+=( --noop )
    fi
    if [ "${verbose:-}" = 'y' ]; then
      agent_args+=( --debug )
    fi
    if [ "$#" -gt 0 ]; then
      agent_args+=( --tags "$(join ',' "$@")" )
    fi
    if is_disabled; then
      reason="$(jq -r '.disabled_message' "$agent_lockfile")"
      if [ "${noop:-}" = 'y' ] || [ "${force:-}" = 'y' ]; then
        puppet agent --enable
        puppet agent "${agent_args[@]}" || exit_status="${?:-1}"
        puppet agent --disable "$reason"
        scheduled_runs disable
      elif [ "${noop:-}" != 'y' ]; then
        fail 'No dry-run and agent disabled. Use -f if you want to run the agent anyway.'
      fi
    else
      puppet agent "${agent_args[@]}" || exit_status="${?:-1}"
    fi
    ;;
esac

exit "${exit_status:-0}"
