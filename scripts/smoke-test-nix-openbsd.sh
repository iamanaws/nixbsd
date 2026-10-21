#!/usr/bin/env bash
# Run inside the disposable openbsd-nix VM, as root or a daemon client.
set -euo pipefail

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
test_shell=${NIX_OPENBSD_TEST_SHELL:-$(command -v bash)}

test "$(uname -s)" = OpenBSD
test "$(uname -r)" = 7.9
test "$(nix --version)" = "nix (Nix) $NIX_OPENBSD_TEST_VERSION"
printf 'Testing Nix %s with %s store as UID %s\n' "$NIX_OPENBSD_TEST_VERSION" "${NIX_REMOTE:-auto}" "$(id -u)"
"$NIX_OPENBSD_TEST_IFCONFIG" lo0 | grep -F 'inet 127.0.0.1'
test "$(nix-instantiate --eval --strict --expr 'builtins.currentSystem')" = '"x86_64-openbsd"'
test "$(nix-instantiate --eval --strict --expr "builtins.foldl' (a: b: a + b) 0 [ 1 2 3 ]")" = 6

# Use unique derivations so every run exercises builder startup and log output.
cat > "$test_dir/build.nix" <<'NIX'
{ shell, nonce, fail ? false }:
derivation {
  name = "openbsd-nix-smoke-${nonce}";
  system = builtins.currentSystem;
  builder = shell;
  args = [ "-c" (if fail then "echo expected-builder-failure >&2; exit 23" else ''
    test "$EUID" -ne 0 || exit 24
    echo builder-stderr >&2
    printf 'openbsd-nix-ok\n' > "$out"
  '') ];
}
NIX

for i in 1 2 3; do
  output=$(nix-build "$test_dir/build.nix" --no-out-link \
    --option substitute false --argstr shell "$test_shell" \
    --argstr nonce "$(basename "$test_dir")-$i")
  test "$(cat "$output")" = openbsd-nix-ok
  nix-store --verify-path "$output"
done

native_drv=$(nix-instantiate "$NIX_OPENBSD_TEST_NATIVE" --argstr shell "$test_shell" \
  --argstr compiler "$NIX_OPENBSD_TEST_COMPILER" --argstr libc "$NIX_OPENBSD_TEST_LIBC" \
  --argstr coreutils "$NIX_OPENBSD_TEST_COREUTILS" --argstr nonce "$(basename "$test_dir")")
nix-store --query --references "$native_drv" > "$test_dir/native-inputs"
grep -Fx "$(dirname "$(dirname "$NIX_OPENBSD_TEST_COMPILER")")" "$test_dir/native-inputs"
grep -Fx "$NIX_OPENBSD_TEST_LIBC" "$test_dir/native-inputs"
native_output=$(nix-build "$native_drv" --no-out-link --option substitute false)
test "$(cat "$native_output/build-uid")" -ne 0
test "$("$native_output/bin/openbsd-native-c")" = openbsd-native-c-ok
nix-store --verify-path "$native_output"
echo 'Native C compilation, linking and execution passed'

"$test_shell" "$NIX_OPENBSD_TEST_PTY"

if nix-build "$test_dir/build.nix" --no-out-link --option substitute false \
  --argstr shell "$test_shell" --argstr nonce "$(basename "$test_dir")-failure" \
  --arg fail true > "$test_dir/failure.log" 2>&1; then
  echo 'A failing builder unexpectedly succeeded' >&2
  exit 1
fi
grep -F 'expected-builder-failure' "$test_dir/failure.log"
grep -E 'exit code 23|exit status 23' "$test_dir/failure.log"

printf 'store-roundtrip\n' > "$test_dir/input"
stored=$(nix-store --add "$test_dir/input")
nix-store --dump "$stored" > "$test_dir/input.nar"
nix-store --restore "$test_dir/restored" < "$test_dir/input.nar"
cmp "$test_dir/input" "$test_dir/restored"

for archive in "$NIX_OPENBSD_TEST_ARCHIVES"/fixture.tar.*; do
  test "$(nix-instantiate --eval --strict --expr "import (builtins.fetchTarball \"file://$archive\")")" = 42
done

mode=local
if [[ ${NIX_REMOTE:-} == daemon ]]; then
  if [[ $EUID == 0 ]]; then mode=daemon-root; else mode=daemon-user; fi
fi
fixtures=$NIX_OPENBSD_TEST_NETWORK
cache=https://10.0.2.2:18443/cache
signed=$(cat "$fixtures/$mode/signed.path")
test ! -e "$signed"
nix-store --realise "$signed" --option substituters "$cache" \
  --option require-sigs true --option fallback false --option max-jobs 0
test "$(cat "$signed")" = "nix-openbsd-test-$mode-signed"
nix-store --verify-path "$signed"
for case in unsigned bad-signature corrupt; do
  path=$(cat "$fixtures/$mode/$case.path")
  test ! -e "$path"
  if nix-store --realise "$path" --option substituters "$cache" \
    --option require-sigs true --option fallback false --option max-jobs 0 \
    > "$test_dir/$case.log" 2>&1; then
    echo "Accepted invalid cache entry: $case" >&2
    exit 1
  fi
  test ! -e "$path"
  if [[ $case == corrupt ]]; then
    grep -Ei 'decompress|xz|lzma|compression|NAR|archive' "$test_dir/$case.log"
  else
    grep -Ei 'signature|not signed' "$test_dir/$case.log"
  fi
done
if NIX_SSL_CERT_FILE="$fixtures/untrusted.pem" nix-instantiate --eval --strict \
  --expr 'builtins.fetchurl "https://10.0.2.2:18443/tls-probe"' \
  > "$test_dir/tls.log" 2>&1; then
  echo 'Accepted an untrusted TLS certificate' >&2
  exit 1
fi
grep -Ei 'certificate|SSL peer' "$test_dir/tls.log"
rev=$(cat "$fixtures/git-rev")
test "$(nix-instantiate --eval --strict --expr \
  "import (builtins.fetchGit { url = \"https://10.0.2.2:18443/git/$mode\"; rev = \"$rev\"; })")" = 42
echo 'HTTPS, signatures and Git tests passed'

# A barrier requires three builders to overlap, rather than merely finish.
barrier=$(mktemp -d)
chmod 0777 "$barrier"
trap 'rm -rf "$test_dir" "$barrier"' EXIT
cat > "$test_dir/concurrent.nix" <<'NIX'
{ shell, sleep, barrier, nonce }:
map (i: derivation {
  name = "openbsd-concurrent-${nonce}-${toString i}";
  system = builtins.currentSystem;
  builder = shell;
  args = [ "-c" ''
    test "$EUID" -ne 0 || exit 24
    echo "$EUID" > ${barrier}/ready-${toString i}
    for attempt in {1..60}; do
      ready=(${barrier}/ready-*)
      if (( ''${#ready[@]} == 3 )); then
        echo "$EUID" > "$out"
        exit 0
      fi
      ${sleep} 1
    done
    echo 'Concurrent builders did not reach the barrier' >&2
    exit 25
  '' ];
}) [ 1 2 3 ]
NIX
nix-build "$test_dir/concurrent.nix" --no-out-link --option substitute false \
  --max-jobs 3 --argstr shell "$test_shell" --argstr sleep "$NIX_OPENBSD_TEST_SLEEP" \
  --argstr barrier "$barrier" --argstr nonce "$(basename "$test_dir")"
test "$(sort -u "$barrier"/ready-* | wc -l | tr -d ' ')" = 3
rm -rf "$barrier"
echo 'Concurrent builds passed with three distinct build users'

# Collect only inside the disposable VM. A rooted path must survive collection.
current_system=$(readlink -f /run/current-system)
booted_system=$(readlink -f /run/booted-system)
printf 'rooted-%s\n' "$test_dir" > "$test_dir/rooted"
printf 'unrooted-%s\n' "$test_dir" > "$test_dir/unrooted"
rooted=$(nix-store --add "$test_dir/rooted")
unrooted=$(nix-store --add "$test_dir/unrooted")
nix-store --realise "$rooted" --add-root "$test_dir/gc-root" --indirect
nix-store --gc > "$test_dir/gc.log" 2>&1
test -x "$current_system/sw/bin/nix"
test -d "$booted_system"
test -e "$rooted"
test ! -e "$unrooted"
rm "$test_dir/gc-root"
nix-store --gc >> "$test_dir/gc.log" 2>&1
test ! -e "$rooted"
echo 'Garbage collection and GC roots passed'
echo 'Nix OpenBSD smoke tests passed'
