#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
timeout_seconds=${OPENBSD_VM_TIMEOUT:-300}
vm_attribute=${OPENBSD_VM_ATTRIBUTE:-openbsd-base}
probe_command=${OPENBSD_VM_PROBE:-id -u}
success_pattern=${OPENBSD_VM_SUCCESS_PATTERN:-$'\r0\r'}
failure_pattern=${OPENBSD_VM_FAILURE_PATTERN:-}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/nixbsd-openbsd-smoke.XXXXXXXX")
log_file="$work_dir/console.log"
input_fifo="$work_dir/console.in"
vm_pid=

# Invoked by the EXIT/INT/TERM trap below.
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "$vm_pid" ]] && kill -0 "$vm_pid" 2>/dev/null; then
    kill "$vm_pid" 2>/dev/null || true
    wait "$vm_pid" 2>/dev/null || true
  fi
  if [[ ${OPENBSD_VM_KEEP_TMP:-0} == 1 ]]; then
    echo "OpenBSD VM smoke-test files: $work_dir" >&2
  else
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$work_dir/runtime"
mkfifo "$input_fifo"
exec {vm_input_fd}<>"$input_fifo"
nix build \
  --accept-flake-config \
  --out-link "$work_dir/result" \
  "$@" \
  "${OPENBSD_VM_FLAKE:-$repo_root}#$vm_attribute.vm"

runner="$work_dir/result/bin/run-nixbsd-$vm_attribute-vm"
if [[ ! -x "$runner" ]]; then
  echo "OpenBSD VM runner not found: $runner" >&2
  exit 1
fi

(
  export NIX_DISK_IMAGE="$work_dir/openbsd-smoke.qcow2"
  export NIX_EFI_VARS="$work_dir/openbsd-smoke-efi-vars.fd"
  export TMPDIR="$work_dir/runtime"
  export USE_TMPDIR=1
  exec "$runner"
) <"$input_fifo" >"$log_file" 2>&1 &
vm_pid=$!

deadline=$((SECONDS + timeout_seconds))
login_sent=false
password_sent=false
probe_sent=false
while ((SECONDS < deadline)); do
  if [[ "$probe_sent" == true ]] && grep -Eq "$success_pattern" "$log_file"; then
    echo "OpenBSD VM probe passed ($vm_attribute)."
    exit 0
  fi
  if [[ "$probe_sent" == true && -n "$failure_pattern" ]] && grep -Eq "$failure_pattern" "$log_file"; then
    echo "OpenBSD VM probe reported failure ($vm_attribute)." >&2
    break
  fi
  if [[ "$login_sent" == false ]] && grep -Eq '(^|[[:space:]])login:' "$log_file"; then
    printf 'root\n' >&"$vm_input_fd"
    login_sent=true
  elif [[ "$password_sent" == false ]] && grep -q 'Password:' "$log_file"; then
    printf 'toor\n' >&"$vm_input_fd"
    password_sent=true
  elif [[ "$probe_sent" == false && "$password_sent" == true ]] && grep -q 'root@' "$log_file"; then
    printf '%s\n' "$probe_command" >&"$vm_input_fd"
    probe_sent=true
  fi
  if ! kill -0 "$vm_pid" 2>/dev/null; then
    wait "$vm_pid" || status=$?
    echo "OpenBSD VM exited before reaching login (status ${status:-0})." >&2
    break
  fi
  sleep 1
done

echo "OpenBSD VM did not complete its probe within ${timeout_seconds}s." >&2
echo "Console output:" >&2
printf '%s\n' "-----" >&2
cat "$log_file" >&2
printf '%s\n' "-----" >&2
exit 1
