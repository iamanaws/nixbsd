#!/usr/bin/env bash
# Run inside the disposable OpenBSD VM, with the same store as the main test.
set -euo pipefail
test_dir=$(mktemp -d)
barrier=$(mktemp -d)
chmod 0777 "$barrier"
client_pid=
# shellcheck disable=SC2329
cleanup() {
  status=$?
  if ((status != 0)) && [[ -f "$test_dir/log" ]]; then
    cat "$test_dir/log" >&2
  fi
  if [[ -n "$client_pid" ]]; then
    kill "$client_pid" 2>/dev/null || true
    wait "$client_pid" 2>/dev/null || true
  fi
  rm -rf "$test_dir" "$barrier"
}
trap cleanup EXIT
timeout=$NIX_OPENBSD_TEST_COREUTILS/timeout
cat > "$test_dir/build.nix" <<'NIX'
{ probe, mode, release, nonce }:
derivation {
  name = "openbsd-pty-${mode}-${nonce}";
  system = "x86_64-openbsd";
  builder = builtins.storePath probe;
  args = [ mode release ];
}
NIX
instantiate() {
  nix-instantiate "$test_dir/build.nix" \
    --argstr probe "$NIX_OPENBSD_TEST_PTY_FIXTURES/bin/pty-probe" \
    --argstr mode "$1" --argstr release "$barrier/release" \
    --argstr nonce "$(basename "$test_dir")-$2"
}
build() {
  "$timeout" 45 nix-build "$1" --no-out-link --option substitute false \
    > "$test_dir/output" 2> "$test_dir/log"
}

# A C program must deliver a newline before it exits or explicitly flushes.
drv=$(instantiate live 0)
"$timeout" 45 nix-build "$drv" --no-out-link --option substitute false \
  > "$test_dir/output" 2> "$test_dir/log" &
client_pid=$!
seen=false
for _ in {1..100}; do
  if grep -q '^pty-live-ready$' "$test_dir/log"; then
    seen=true
    break
  fi
  "$NIX_OPENBSD_TEST_SLEEP" 0.1
done
if [[ $seen != true ]]; then
  cat "$test_dir/log" >&2
  echo 'C stdout was not delivered while the builder was running' >&2
  exit 1
fi
touch "$barrier/release"
wait "$client_pid"
client_pid=
test "$(cat "$(cat "$test_dir/output")")" = pty-ok
rm "$barrier/release"

# Exercise fast exits repeatedly, including preservation of the last log lines.
for i in {1..20}; do
  drv=$(instantiate fast "$i")
  build "$drv"
  test "$(cat "$(cat "$test_dir/output")")" = pty-ok
  drv=$(instantiate fail "$i")
  if build "$drv"; then
    echo 'Failing PTY builder unexpectedly succeeded' >&2
    exit 1
  fi
  grep -q 'exit code 23' "$test_dir/log"
  nix-store --read-log "$drv" > "$test_dir/saved-log"
  grep -qx 'pty-final-stdout' "$test_dir/saved-log"
  grep -qx 'pty-final-stderr' "$test_dir/saved-log"
done

# The PTY supervisor must preserve a signal exit, not convert it to success.
drv=$(instantiate signal 0)
if build "$drv"; then
  echo 'Signalled PTY builder unexpectedly succeeded' >&2
  exit 1
fi
grep -E 'signal 15|signal SIGTERM' "$test_dir/log"
nix-store --read-log "$drv" > "$test_dir/saved-log"
grep -qx 'pty-before-signal' "$test_dir/saved-log"

# Exceed the PTY buffer, then compare the complete saved stdout/stderr stream.
drv=$(instantiate burst 0)
build "$drv"
nix-store --read-log "$drv" > "$test_dir/saved-log"
for ((i = 0; i < 4096; i++)); do
  printf 'stdout-%04d\nstderr-%04d\n' "$i" "$i"
done > "$test_dir/expected-log"
cmp "$test_dir/expected-log" "$test_dir/saved-log"

# A killed builder must release the PTY so the following build can finish.
drv=$(instantiate live timeout)
if "$timeout" 30 nix-build "$drv" --no-out-link --option substitute false \
  --timeout 2 > "$test_dir/output" 2> "$test_dir/log"; then
  echo 'Timed out PTY builder unexpectedly succeeded' >&2
  exit 1
fi
grep -Fi 'timed out' "$test_dir/log"
build "$(instantiate fast after-timeout)"

# LD_PRELOAD affects this local-store client and its child, not the system daemon.
if [[ ${NIX_REMOTE:-} == local ]]; then
  drv=$(instantiate fast setup-failure)
  if "$timeout" 30 env LD_PRELOAD="$NIX_OPENBSD_TEST_PTY_FIXTURES/lib/setup-failure.so" \
    nix-build "$drv" --no-out-link --option substitute false \
    > "$test_dir/output" 2> "$test_dir/log"; then
    echo 'Injected child setup failure unexpectedly succeeded' >&2
    exit 1
  fi
  grep -F 'while setting up the build environment' "$test_dir/log"
  grep -E 'changing into .*Permission denied' "$test_dir/log"
fi
echo 'PTY terminal detection, live output, fast exits, logs and cleanup passed'
