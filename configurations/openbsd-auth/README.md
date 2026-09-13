# OpenBSD authentication tests

From the nixbsd repository root on an x86_64 Linux host:

```shell
nix run .#openbsd-auth.authTest --max-jobs 1 --cores 1
```

This uses a disposable headless VM to check SSH stop/start and password login,
`su`, password changes, and service users, groups, environment, working directory
and login-class limits. SSH is forwarded only on localhost.

Set `OPENBSD_VM_KEEP_TMP=1` to keep the disk and logs, or
`OPENBSD_VM_TIMEOUT=600` to increase the default 300-second test timeout.
