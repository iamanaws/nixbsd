"""Host-side authentication checks; only the disposable VM is modified."""

import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def main():
    runner, ssh, askpass, native_id = sys.argv[1:]
    work = Path(tempfile.mkdtemp(prefix="nixbsd-openbsd-auth."))
    vm = None
    try:
        (work / "runtime").mkdir()
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        env = os.environ | {
            "NIX_DISK_IMAGE": str(work / "disk.qcow2"),
            "NIX_EFI_VARS": str(work / "efi.fd"),
            "TMPDIR": str(work / "runtime"),
            "USE_TMPDIR": "1",
            "QEMU_NET_OPTS": f"hostfwd=tcp:127.0.0.1:{port}-:22",
        }
        with (work / "console.log").open("wb", buffering=0) as log:
            vm = subprocess.Popen(
                [runner], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, env=env,
            )
            deadline = time.monotonic() + int(os.environ.get("OPENBSD_VM_TIMEOUT", "300"))
            buffer = b""

            def expect(pattern, timeout=60):
                nonlocal buffer
                until = min(deadline, time.monotonic() + timeout)
                regex = re.compile(pattern.encode())
                while time.monotonic() < until:
                    match = regex.search(buffer)
                    if match:
                        output = buffer[:match.end()]
                        buffer = buffer[match.end():]
                        return output.decode(errors="replace")
                    if select.select([vm.stdout], [], [], 1)[0]:
                        chunk = os.read(vm.stdout.fileno(), 65536)
                        if not chunk:
                            raise RuntimeError("VM exited before completing the test")
                        log.write(chunk)
                        buffer += chunk
                raise RuntimeError(f"Timed out waiting for {pattern!r}")

            def send(line):
                vm.stdin.write((line + "\n").encode())
                vm.stdin.flush()

            def command(line):
                # Split the marker so the echoed command cannot count as success.
                send(line + "; printf '\\nCOMMAND_%s:%s\\n' DONE \"$?\"")
                output = expect(r"\r?\nCOMMAND_DONE:[0-9]+\r?\n")
                if not output.rstrip().endswith("COMMAND_DONE:0"):
                    raise RuntimeError(f"Guest command failed: {line}\n{output}")
                return output

            expect(r"login:", 300)
            send("root")
            expect(r"Password:")
            send("toor")
            expect(r"root@[^\r\n]*#")
            print("Serial root login passed", flush=True)

            command('test "$(cat /tmp/service-probe-result)" = SERVICE_PROBE_OK')
            print("Service user, groups, environment, directory and limits passed", flush=True)
            command("/etc/rc.d/argument_probe check && /etc/rc.d/argument_probe stop && ! /etc/rc.d/argument_probe check")
            command("/etc/rc.d/argument_probe start && sleep 1 && /etc/rc.d/argument_probe check")
            print("Service process matching with command-line arguments passed", flush=True)
            command("cd /tmp && su -s /bin/sh nobody -c 'test \"$(id -un)\" = nobody'")
            output = command("! su -s /bin/sh nobody -c 'su root -c id' </dev/null")
            if "not in group wheel" not in output:
                raise RuntimeError("su did not reject the non-wheel user as expected")

            command("/etc/rc.d/sshd check && /etc/rc.d/sshd stop && ! /etc/rc.d/sshd check")
            command("/etc/rc.d/sshd start && sleep 1 && /etc/rc.d/sshd check")
            print("SSH service stop/start passed", flush=True)

            send("su - bestie")
            expect(r"bestie@[^\r\n]*\$")
            command("! passwd root")
            send("passwd bestie")
            expect(r"Old password:")
            send("toor")
            expect(r"New password:")
            send("VmTest-New9!")
            expect(r"Retype new password:")
            send("VmTest-New9!")
            expect(r"bestie@[^\r\n]*\$")
            command('test "$?" = 0')

            send("su - root")
            expect(r"Password:")
            send("incorrect-test-password")
            expect(r"Sorry")
            expect(r"bestie@[^\r\n]*\$")
            send("su - root")
            expect(r"Password:")
            send("toor")
            expect(r"root@[^\r\n]*#")
            command('test "$(id -u)" = 0')
            print("su password authentication and wheel restriction passed", flush=True)

            result = subprocess.run(
                [ssh, "-F", "/dev/null", "-p", str(port),
                 "-o", "StrictHostKeyChecking=no",
                 "-o", f"UserKnownHostsFile={work}/known_hosts",
                 "-o", "GlobalKnownHostsFile=/dev/null",
                 "-o", "ConnectTimeout=15", "-o", "NumberOfPasswordPrompts=1",
                 "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no",
                 "bestie@127.0.0.1",
                 f'test "$({native_id} -un)" = bestie && {native_id} -Gn | grep -w wheel'],
                env=os.environ | {"SSH_ASKPASS": askpass, "SSH_ASKPASS_REQUIRE": "force"},
                stdin=subprocess.DEVNULL, capture_output=True, text=True,
                timeout=max(1, min(45, deadline - time.monotonic())),
            )
            (work / "ssh.log").write_text(result.stdout + result.stderr)
            if result.returncode:
                raise RuntimeError(f"SSH login using the changed password failed:\n{result.stderr}")
            print("SSH login using the changed password passed", flush=True)
            print("OpenBSD authentication and service tests passed.", flush=True)
    except Exception:
        if (work / "console.log").exists():
            print((work / "console.log").read_text(errors="replace")[-12000:], file=sys.stderr)
        raise
    finally:
        if vm is not None and vm.poll() is None:
            vm.terminate()
            try:
                vm.wait(timeout=15)
            except subprocess.TimeoutExpired:
                vm.kill()
                vm.wait()
        if os.environ.get("OPENBSD_VM_KEEP_TMP") == "1":
            print(f"OpenBSD authentication test files: {work}", file=sys.stderr)
        else:
            shutil.rmtree(work)


if __name__ == "__main__":
    # Unwind through finally on interruption, terminating only this test's VM.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    main()
