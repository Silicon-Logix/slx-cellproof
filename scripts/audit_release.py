# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Exact inventory and provenance audit; optional externally anchored Ed25519 verification."""
from pathlib import Path, PurePosixPath
import argparse, hashlib, json, re, subprocess, zipfile

FORBIDDEN_PARTS={"private","internal","templates",".git","workspace","__pycache__","sdk","signing","generated"}
FORBIDDEN_EXT={".cpp",".h",".hpp",".a",".lib",".obj",".o",".pdb",".debug",".pem",".key",".secret",".blend"}
TEXT_LICENSES={"licenses/gcc/COPYING.LIB","licenses/gcc/COPYING3.LIB","licenses/mingw-w64/direct-x-COPYING.lib"}
PUBLIC_DOCS={"docs/API_SLX_V1.md","docs/USER_GUIDE.md","docs/URSIM.md","docs/VALIDATION.md","docs/ADVANCED_FEATURES.md","docs/INSTALLATION_AND_UPDATES.md","docs/images/workspace.png","docs/images/verification.png","docs/images/cycle-inspector.png"}

def safe_path(name):
    path=PurePosixPath(name)
    if not name or "\\" in name or ":" in name or name.startswith("/") or any(x in (".","..","") for x in name.split("/")):
        raise ValueError("Unsafe release path: "+name)
    if any(x.lower() in FORBIDDEN_PARTS for x in path.parts):
        raise ValueError("Internal release path: "+name)
    text_license=name in TEXT_LICENSES
    if path.suffix.lower() in FORBIDDEN_EXT and not text_license:
        raise ValueError("Source/debug/key material in runtime release: "+name)
    if not (name in {"CellProof.exe","CellProof.pck","README.md","LICENSE","THIRD_PARTY_NOTICES.md","CHANGELOG.md","CONTRIBUTING.md","SECURITY.md","release-manifest.json"} or name=="bin/slx-cellproof-core.exe" or name.startswith("licenses/") or name in PUBLIC_DOCS):
        raise ValueError("Outside runtime allowlist: "+name)

def verify_manifest(document, public_key=None, production=False):
    if document.get("algorithm")=="Ed25519":
        if not public_key:
            raise ValueError("A signed release requires an externally trusted public key")
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        key=bytes.fromhex(public_key.strip())
        payload=json.dumps(document["payload"],sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()
        Ed25519PublicKey.from_public_bytes(key).verify(bytes.fromhex(document["signature"]),payload)
    elif document.get("algorithm")!="UNSIGNED-DEVELOPMENT" or production:
        raise ValueError("Production requires an Ed25519 release manifest")
    manifest=document["payload"]
    if manifest.get("product")!="slx-cellproof" or manifest.get("purpose")!="release-manifest" or manifest.get("schema")!=1 or manifest.get("distribution")!="public":
        raise ValueError("Manifest product/purpose/profile mismatch")
    if manifest.get("release_channel") not in ("development-preview","production"):
        raise ValueError("Missing release channel")
    if production and manifest.get("release_channel")!="production":
        raise ValueError("Preview cannot be approved as production")
    if not isinstance(manifest.get("files"),dict) or not manifest["files"]:
        raise ValueError("Empty file inventory")
    for name,digest in manifest["files"].items():
        safe_path(name)
        if not re.fullmatch("[0-9a-f]{64}",digest):raise ValueError("Invalid file digest")
    return manifest

def audit_bytes(files, public_key=None, production=False):
    if "release-manifest.json" not in files:raise ValueError("Missing release manifest")
    manifest=verify_manifest(json.loads(files["release-manifest.json"]),public_key,production)
    actual=set(files)-{"release-manifest.json"}
    if actual!=set(manifest["files"]):raise ValueError("File inventory mismatch")
    for name,payload in files.items():
        safe_path(name)
        if name!="release-manifest.json" and hashlib.sha256(payload).hexdigest()!=manifest["files"][name]:
            raise ValueError("Modified release file: "+name)
        if name.endswith(".exe") and b"SLX_INTERNAL_PROJECT_CONNECTORS_V1" in payload:
            raise ValueError("Internal module marker in public executable")
        if name.endswith((".md",".json")):
            text=payload.decode("utf-8")
            if re.search(r"[A-Z]:[/\\]Users[/\\]|BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY",text):
                raise ValueError("Personal path or private key in release")
    return manifest

def audit_tree(root,public_key=None,production=False):
    root=Path(root).resolve()
    files={}
    for path in root.rglob("*"):
        if path.is_symlink() or path.is_junction():raise ValueError("Linked release path")
        if path.is_file():files[path.relative_to(root).as_posix()]=path.read_bytes()
    result=audit_bytes(files,public_key,production)
    if production:
        for name in ("CellProof.exe","bin/slx-cellproof-core.exe"):
            verify_script=Path(__file__).with_name("verify-authenticode.ps1")
            subprocess.run(["powershell.exe","-NoProfile","-File",str(verify_script),"-Path",str(root/name),"-Thumbprint",result["authenticode_thumbprint"]],check=True,capture_output=True)
    return result

def audit_zip(path,public_key=None,production=False):
    with zipfile.ZipFile(path) as archive:
        files={}
        for item in archive.infolist():
            if item.is_dir():continue
            if item.filename in files or item.file_size>512*1024*1024 or ((item.external_attr>>16)&0o170000)==0o120000:
                raise ValueError("Unexpected archive entry")
            safe_path(item.filename)
            files[item.filename]=archive.read(item)
    return audit_bytes(files,public_key,production)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("path",type=Path)
    parser.add_argument("--public-key",type=Path)
    parser.add_argument("--production",action="store_true")
    args=parser.parse_args()
    key=args.public_key.read_text().strip() if args.public_key else None
    result=(audit_zip if args.path.suffix==".zip" else audit_tree)(args.path,key,args.production)
    print("PASS: exact inventory, hashes, public boundary; channel="+result["release_channel"])

if __name__=="__main__":main()
