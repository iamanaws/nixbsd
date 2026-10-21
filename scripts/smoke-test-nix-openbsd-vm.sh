#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/nix-openbsd-https.XXXXXXXX")
server_pid=
# shellcheck disable=SC2329
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ ${OPENBSD_VM_KEEP_TMP:-0} == 1 ]]; then
    echo "HTTPS fixture logs: $work_dir" >&2
  else
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT
nix build --accept-flake-config --out-link "$work_dir/server" "$@" \
  "${OPENBSD_VM_FLAKE:-$repo_root}#openbsd-nix.nixTestServer"
"$work_dir/server/bin/serve-nix-openbsd-fixtures" "$work_dir/ready" > "$work_dir/server.log" 2>&1 &
server_pid=$!
for _ in {1..100}; do
  [[ -e "$work_dir/ready" ]] && break
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$work_dir/server.log" >&2
    exit 1
  fi
  sleep 0.1
done
test -e "$work_dir/ready"

export OPENBSD_VM_ATTRIBUTE=openbsd-nix
export OPENBSD_VM_TIMEOUT=${OPENBSD_VM_TIMEOUT:-600}
export OPENBSD_VM_PROBE="NIX_REMOTE=local smoke-test-nix-openbsd && NIX_REMOTE=daemon smoke-test-nix-openbsd && su - bestie -c 'NIX_REMOTE=daemon smoke-test-nix-openbsd' && id -un"
bash "$(dirname "${BASH_SOURCE[0]}")/smoke-test-openbsd-vm.sh" "$@"
