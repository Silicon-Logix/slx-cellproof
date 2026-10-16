# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Build a per-user installer from an already audited immutable runtime."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
from audit_release import audit_tree

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--compiler", type=Path, default=ROOT / "build/tools/inno/ISCC.exe")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--test-app-id")
    parser.add_argument("--public-key", type=Path)
    parser.add_argument("--signtool", type=Path)
    parser.add_argument("--certificate-thumbprint")
    args = parser.parse_args()
    key = args.public_key.read_text().strip() if args.public_key else None
    manifest = audit_tree(args.runtime, key)
    version = manifest["version"]
    production = manifest["release_channel"] == "production"
    if production and not (args.signtool and args.certificate_thumbprint):
        raise RuntimeError("A production installer requires its real publisher certificate")
    if args.certificate_thumbprint and not re.fullmatch(r"[0-9a-fA-F]{40}", args.certificate_thumbprint):
        raise RuntimeError("Invalid publisher certificate thumbprint")
    name = f"slx-cellproof-{version}-windows-x64-setup" + ("-qa" if args.test_app_id else "")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    executable = output / (name + ".exe")
    if executable.exists():
        raise RuntimeError("Installer candidates are immutable; choose a fresh output folder")
    command = [str(args.compiler.resolve()), "/Qp", "/DRuntimeDir=" + str(args.runtime.resolve()),
               "/DAppVersion=" + version, "/DOutputDir=" + str(output), "/DOutputName=" + name]
    if args.test_app_id:
        command.append("/DAppId=" + args.test_app_id)
        command.append("/DAppMutexName=Local\\" + args.test_app_id + ".Running")
    if production:
        command += ["/DSignedRelease", "/Sslxsign=$q" + str(args.signtool.resolve()) + "$q sign /sha1 " +
                    args.certificate_thumbprint + " /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $f"]
    command.append(str(ROOT / "installer/CellProof.iss"))
    subprocess.run(command, check=True, timeout=180)
    if production:
        subprocess.run([str(args.signtool), "verify", "/pa", str(executable)], check=True)
    digest = hashlib.sha256(executable.read_bytes()).hexdigest()
    document = {"product": "slx-cellproof", "version": version, "release_channel": manifest["release_channel"],
                "installer": executable.name, "sha256": digest, "runtime_manifest_sha256":
                hashlib.sha256((args.runtime / "release-manifest.json").read_bytes()).hexdigest(),
                "publisher_signed": production, "compiler_version": "Inno Setup 6.7.3"}
    (output / (name + ".json")).write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    print("Installer:", executable)
    print("SHA256:", digest)


if __name__ == "__main__":
    main()
