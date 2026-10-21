"""Build test-only TLS certificates, binary cache entries and Git repositories."""

import base64
import datetime
import hashlib
import ipaddress
import lzma
import os
from pathlib import Path
import subprocess
import sys

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.x509.oid import NameOID


def run(*args):
    return subprocess.check_output(args)


def key(name):
    # Public, deterministic test keys. Never use these outside the test VM.
    return ed25519.Ed25519PrivateKey.from_private_bytes(hashlib.sha256(name.encode()).digest())


def certificate(signing_key, name):
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)])
    return (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(subject)
        .public_key(signing_key.public_key())
        .serial_number(1)
        .not_valid_before(datetime.datetime(2020, 1, 1))
        .not_valid_after(datetime.datetime(2100, 1, 1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
        .add_extension(x509.SubjectAlternativeName([
            x509.IPAddress(ipaddress.ip_address("127.0.0.1")),
            x509.IPAddress(ipaddress.ip_address("10.0.2.2")),
        ]), critical=False)
        .sign(signing_key, None)
        .public_bytes(serialization.Encoding.PEM)
    )


out = Path(sys.argv[1])
out.mkdir()
tls_key = key("nix-openbsd-test-tls")
(out / "cert.pem").write_bytes(certificate(tls_key, "Nix OpenBSD test"))
(out / "untrusted.pem").write_bytes(certificate(key("untrusted"), "Untrusted test CA"))
(out / "key.pem").write_bytes(tls_key.private_bytes(
    serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
))
(out / "tls-probe").write_text("TLS verification must reject the wrong CA\n")
cache_key = key("nix-openbsd-test-cache")
public = base64.b64encode(cache_key.public_key().public_bytes_raw()).decode()
(out / "public-key").write_text(f"nix-openbsd-test:{public}\n")
cache = out / "cache"
(cache / "nar").mkdir(parents=True)
(cache / "nix-cache-info").write_text("StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 1\n")

for mode in ("local", "daemon-root", "daemon-user"):
    cases = out / mode
    cases.mkdir()
    for case in ("signed", "unsigned", "bad-signature", "corrupt"):
        name = f"nix-openbsd-test-{mode}-{case}"
        payload = Path("payload")
        payload.write_text(name + "\n")
        nar = Path("payload.nar")
        nar.write_bytes(run("nix-store", "--dump", str(payload)))
        digest = run("nix", "hash", "file", "--type", "sha256", "--base32", str(nar)).decode().strip()
        # Input-addressed test paths require a signature, unlike CA store paths.
        store_path = f"/nix/store/{digest[:32]}-{name}"
        (cases / f"{case}.path").write_text(store_path + "\n")
        fingerprint = f"1;{store_path};sha256:{digest};{nar.stat().st_size};".encode()
        signer = key("wrong-cache-key") if case == "bad-signature" else cache_key
        signature = base64.b64encode(signer.sign(fingerprint)).decode()
        compressed = lzma.compress(nar.read_bytes())
        (cache / "nar" / f"{name}.nar.xz").write_bytes(
            b"broken NAR" if case == "corrupt" else compressed
        )
        info = (
            f"StorePath: {store_path}\nURL: nar/{name}.nar.xz\nCompression: xz\n"
            f"NarHash: sha256:{digest}\nNarSize: {nar.stat().st_size}\nReferences: \n"
        )
        if case != "unsigned":
            info += f"Sig: nix-openbsd-test:{signature}\n"
        (cache / f"{digest[:32]}.narinfo").write_text(info)

os.environ.update(GIT_AUTHOR_DATE="2020-01-01T00:00:00Z", GIT_COMMITTER_DATE="2020-01-01T00:00:00Z")
run("git", "init", "-b", "main", "repo")
Path("repo/default.nix").write_text("42\n")
run("git", "-C", "repo", "add", ".")
run("git", "-C", "repo", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "fixture")
(out / "git-rev").write_bytes(run("git", "-C", "repo", "rev-parse", "HEAD"))
for mode in ("local", "daemon-root", "daemon-user"):
    target = out / "git" / mode
    run("git", "clone", "--bare", "repo", str(target))
    run("git", "--git-dir", str(target), "update-server-info")
