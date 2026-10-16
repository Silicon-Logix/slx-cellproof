# Silicon LogiX / SLX CellProof
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

"""Review source attribution and inventory without importing application modules."""

from pathlib import Path
import argparse
import ast
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ASSET_PACK = "SLX_CellProof_RoboticWorkcell_3D_v0.1"
INVENTORY = "publication-inventory.json"
NOTICE = (
    "Silicon LogiX / SLX CellProof",
    "Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).",
    "Author: Marco Pezzullo",
    "License: Silicon LogiX Evaluation License 1.0. See LICENSE.",
)
IGNORED = {"build", "dist", "workspace", ".git", ".godot", "__pycache__"}
TEXT_SUFFIXES = {".md", ".txt", ".py", ".ps1", ".cmd", ".gd", ".cpp", ".hpp", ".in",
                 ".json", ".xml", ".urdf", ".svg", ".cfg", ".godot", ".tscn", ".slx", ".yml", ".gitignore", ".iss"}
TEXT_NAMES = {"CMakeLists.txt", ".gitignore", ".gitattributes", ".editorconfig", ".clang-format", "LICENSE"}
PUBLIC_ROOT_FILES = {"README.md", "LICENSE", "THIRD_PARTY_NOTICES.md", ".gitignore",
                     ".gitattributes", ".editorconfig", "CHANGELOG.md", "CONTRIBUTING.md", "SECURITY.md", "EXPORT-MANIFEST.json", INVENTORY}
PUBLIC_UI_FILES = {"app.gd", "core_client.gd", "workcell_view.gd", "slx_theme.gd", "product_dialogs.gd",
                   "cycle_inspector.gd", "cycle_timeline.gd", "inspector_archive.gd",
                   "project_controller.gd", "project_storage.gd", "update_manager.gd",
                   "project.godot", "main.tscn", "export_presets.cfg"}
PUBLIC_DOCS = {"API_SLX_V1.md", "USER_GUIDE.md", "URSIM.md", "VALIDATION.md", "ADVANCED_FEATURES.md", "INSTALLATION_AND_UPDATES.md"}
PUBLIC_DOCUMENTS = {"godot/content/license.txt", "godot/content/third-party-notices.txt",
                    "godot/content/user-guide.txt", "godot/content/api-reference.txt", "godot/content/advanced-services.json", "godot/content/CellProof-Update.ps1"}
PUBLIC_META = {".github/workflows/validate.yml", ".github/ISSUE_TEMPLATE/bug_report.yml",
               ".github/ISSUE_TEMPLATE/feature_request.yml", "tests/public_smoke.gd", "tests/projects_workflow.gd", "tests/ui_workflow.gd", "tests/update_workflow.gd",
               "installer/CellProof.iss", "scripts/build_installer.py", "scripts/audit_release.py", "scripts/verify-authenticode.ps1"}
TEXT_LICENSES = {"licenses/gcc/COPYING.LIB", "licenses/gcc/COPYING3.LIB",
                 "licenses/mingw-w64/direct-x-COPYING.lib"}
# This is a deliberately bounded wording scan, followed by manual English review.
ITALIAN = re.compile(
    r"\b(?:programma|verifica modifica|riferimento|ricetta|attrezzaggio|giunto|"
    r"pezzo|guasto|misura fisica|sorgenti|simulazione|nominale|esegui|riprendi|"
    r"disconnetti|consenso|tavola ingresso|senza|conserva la posa|non valido)\b", re.I
)
PERSONAL_PATH = re.compile(r"[A-Z]:[/\\]Users[/\\]", re.I)
CREDENTIAL = re.compile(
    r"-----BEGIN (?:RSA |OPENSSH |EC |ENCRYPTED )?PRIVATE KEY-----|"
    r"\b(?:ghp_|github_pat_)[A-Za-z0-9_]{30,}|\bAKIA[A-Z0-9]{16}\b"
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def classify(name):
    if name == "godot/content/license.txt":
        return "license", "Silicon LogiX Evaluation License 1.0; complete legal text"
    if name == "godot/content/third-party-notices.txt":
        return "bundled-notices", "Verbatim third-party notices and legal terms; original attribution retained"
    if Path(name).suffix.lower() == ".ico":
        return "application-icon", "Copyright (c) 2026 Marco Pezzullo (Silicon LogiX); Silicon LogiX Evaluation License 1.0"
    if name.startswith("licenses/") or name.startswith(ASSET_PACK + "/third_party/"):
        return "upstream", "Original upstream notices; see THIRD_PARTY_NOTICES.md"
    if name == ASSET_PACK + "/robot/ur5e_nominal.urdf":
        return "derived-upstream", "Universal Robots BSD-3-Clause; original source notices retained"
    if name == ASSET_PACK + "/urdf/cellproof_workcell.urdf":
        return "mixed-workcell", "SLX assembly and Universal Robots BSD-3-Clause robot; see asset NOTICE.txt"
    if Path(name).suffix.lower() in {".glb", ".blend", ".stl", ".npz"}:
        return "binary-asset", "SLX scene/tooling or UR-derived geometry; see THIRD_PARTY_NOTICES.md and provenance"
    if Path(name).suffix.lower() == ".png":
        return "image-asset", "Silicon LogiX branding, UI capture or scene preview; UR model notices remain applicable"
    if name == "bin/slx-cellproof-core.exe":
        return "approved-core-binary", "Silicon LogiX Evaluation License 1.0; bundled runtime notices apply"
    if name.endswith("/LICENSE") or name == "LICENSE":
        return "license", "License text; retain verbatim"
    if Path(name).suffix.lower() == ".json" or Path(name).name == "SHA256SUMS.txt":
        return "structured-data", "SLX-authored or derived data; field provenance and third-party terms apply"
    return "authored", "Copyright (c) 2026 Marco Pezzullo (Silicon LogiX); Silicon LogiX Evaluation License 1.0"


def public_path_allowed(name):
    if name in PUBLIC_ROOT_FILES or name in PUBLIC_META or name in PUBLIC_DOCUMENTS or name in {"bin/slx-cellproof-core.exe", "examples/demo.slx",
                                           "scripts/audit_publication.py"}:
        return True
    if name.startswith("godot/"):
        return name[6:] in PUBLIC_UI_FILES or name in {"godot/assets/logo.png", "godot/assets/workcell.glb", "godot/assets/cellproof.svg", "godot/assets/cellproof.ico", "godot/assets/close.svg"}
    if name.startswith("docs/"):
        return name[5:] in PUBLIC_DOCS or name in {"docs/images/workspace.png", "docs/images/verification.png", "docs/images/cycle-inspector.png"}
    if name.startswith("licenses/"):
        suffix = Path(name).suffix.lower()
        return suffix not in {".exe", ".dll", ".py", ".ps1", ".cpp", ".hpp", ".a", ".lib",
                              ".key", ".secret", ".pem", ".pdb", ".debug", ".zip"} or name in TEXT_LICENSES
    return False


def source_files(root, public=False):
    """Reject links before descent; generated files are ignored only internally."""
    found = {}

    def visit(directory):
        for path in sorted(directory.iterdir()):
            name = path.relative_to(root).as_posix()
            # A public checkout can have its own Git metadata; it is never exported.
            if directory == root and path.name == ".git":
                continue
            if path.is_symlink() or path.is_junction():
                raise ValueError("Linked source path: " + name)
            if not public and (path.name in IGNORED or path.suffix in {".pyc", ".uid", ".import"}):
                continue
            if path.is_dir():
                if public and path.name.lower() in {"private", "internal", "templates", "build", "dist", ".git", "workspace", ".godot", "signing", "__pycache__"}:
                    raise ValueError("Internal/generated directory in public candidate: " + name)
                visit(path)
            elif path.is_file():
                if public and not public_path_allowed(name):
                    raise ValueError("Outside public source allowlist: " + name)
                if path.suffix.lower() in {".key", ".pem", ".secret", ".pdb", ".debug"}:
                    raise ValueError("Key/debug material in source tree: " + name)
                if name not in {INVENTORY, "EXPORT-MANIFEST.json"}:
                    found[name] = path

    visit(root)
    return found


def review_text(root, name, path, role):
    if role == "upstream":
        # Preserve attribution verbatim while still detecting misplaced secrets.
        if CREDENTIAL.search(path.read_bytes().decode("utf-8", errors="replace")):
            raise ValueError("Credential pattern in upstream directory: " + name)
        return
    if role in {"upstream", "derived-upstream", "binary-asset", "image-asset", "application-icon", "approved-core-binary"}:
        return
    if path.suffix not in TEXT_SUFFIXES and path.name not in TEXT_NAMES:
        raise ValueError("Unclassified format requiring review: " + name)
    text = path.read_text(encoding="utf-8")
    if "\ufffd" in text or "\x00" in text:
        raise ValueError("Invalid text content: " + name)
    if role in {"authored", "mixed-workcell"} and not all(item in text[:700] for item in NOTICE):
        raise ValueError("Missing/incorrect authored header: " + name)
    if "_IT." in name:
        raise ValueError("Legacy Italian filename: " + name)
    # The scanner's dictionary intentionally contains examples of the old wording.
    if name != "scripts/audit_publication.py" and ITALIAN.search(text):
        raise ValueError("Untranslated wording requiring review: " + name)
    if PERSONAL_PATH.search(text) or CREDENTIAL.search(text):
        raise ValueError("Personal path or credential pattern: " + name)
    if path.suffix == ".json":
        json.loads(text)
    elif path.suffix == ".py":
        ast.parse(text, filename=name)
    elif path.suffix in {".xml", ".urdf", ".svg"}:
        ET.fromstring(text)
    elif path.suffix == ".md":
        for target in re.findall(r"\[[^\]\n]*\]\(([^)]+)\)", text):
            target = target.strip("<>").split("#", 1)[0]
            if not target or "://" in target or target.startswith("mailto:"):
                continue
            # These templates become README.md at the root of the exported tree.
            base = root if name.startswith("docs/templates/") else path.parent
            linked = (base / target).resolve()
            if not linked.is_relative_to(root) or not linked.exists():
                raise ValueError("Broken/outside documentation link: " + name + " -> " + target)


def verify_upstream(root):
    descriptor = root / "licenses/ur5e-upstream.json"
    if not descriptor.exists():
        raise ValueError("Missing UR5e provenance")
    record = json.loads(descriptor.read_text(encoding="utf-8"))
    for name, expected in record["source_files"].items():
        path = root / "licenses/ur_description" / name
        if not path.is_file() or digest(path) != expected:
            raise ValueError("Upstream file changed or missing: " + name)
    moveit = json.loads((root / "licenses/ur_moveit_config/upstream.json").read_text(encoding="utf-8"))
    for name, expected in moveit["files"].items():
        path = root / "licenses/ur_moveit_config" / name
        if not path.is_file() or digest(path) != expected:
            raise ValueError("MoveIt notice/source changed or missing: " + name)


def verify_asset_records(root):
    assets = root / ASSET_PACK
    if not assets.exists():
        return
    manifest = json.loads((assets / "manifest.json").read_text(encoding="utf-8"))
    expected_sums = ""
    for record in manifest["files"]:
        path = (assets / record["path"]).resolve()
        if not path.is_relative_to(assets) or not path.is_file():
            raise ValueError("Invalid asset manifest path")
        if digest(path) != record["sha256"] or path.stat().st_size != record["size_bytes"]:
            raise ValueError("Asset manifest mismatch: " + record["path"])
        expected_sums += record["sha256"] + "  " + record["path"] + "\n"
    if (assets / "SHA256SUMS.txt").read_text(encoding="utf-8") != expected_sums:
        raise ValueError("Asset checksum list does not match its manifest")


def verify_bundled_documents(root):
    for name, source in {"license.txt": "LICENSE", "user-guide.txt": "docs/USER_GUIDE.md", "api-reference.txt": "docs/API_SLX_V1.md"}.items():
        bundled = root / "godot/content" / name
        if bundled.exists() and bundled.read_text(encoding="utf-8") != (root / source).read_text(encoding="utf-8"):
            raise ValueError("Bundled product document is stale: " + name)
    notices = root / "godot/content/third-party-notices.txt"
    if notices.exists():
        text = notices.read_text(encoding="utf-8")
        if not text.startswith((root / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")):
            raise ValueError("Bundled third-party overview is stale")
        for path in (root / "licenses").rglob("*"):
            if path.is_file() and ("LICENSE" in path.name.upper() or "COPYING" in path.name.upper() or "DISCLAIMER" in path.name.upper() or path.name == "godot-COPYRIGHT.txt"):
                if path.read_text(encoding="utf-8") not in text:
                    raise ValueError("Third-party legal text missing from the application: " + path.name)


def audit(root, public=False, write_inventory=False):
    root = Path(root).resolve()
    files = source_files(root, public)
    records = {}
    for name, path in files.items():
        role, rights = classify(name)
        review_text(root, name, path, role)
        records[name] = {"sha256": digest(path), "classification": role, "attribution": rights}
    verify_upstream(root)
    verify_asset_records(root)
    verify_bundled_documents(root)
    document = {"schema": "slx.publication-inventory/v1", "product": "slx-cellproof",
                "language": "en", "scope": "public-source" if public else "internal-checkout",
                "author": "Marco Pezzullo", "copyright": NOTICE[1],
                "license": "Silicon LogiX Evaluation License 1.0; third-party exceptions in file records",
                "files": records}
    inventory = root / INVENTORY
    if write_inventory:
        inventory.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    elif not inventory.exists() or json.loads(inventory.read_text(encoding="utf-8")) != document:
        raise ValueError("Publication inventory missing or stale; review changes before --write-inventory")
    if public:
        export = root / "EXPORT-MANIFEST.json"
        if not export.exists():
            if not write_inventory:
                raise ValueError("Missing public export manifest")
        else:
            manifest = json.loads(export.read_text(encoding="utf-8"))
            actual = {**{name: item["sha256"] for name, item in records.items()}, INVENTORY: digest(inventory)}
            if manifest.get("schema") != "slx.public-source/v1" or manifest.get("product") != "slx-cellproof" or manifest.get("files") != actual:
                raise ValueError("Public export inventory mismatch")
    return {"files": len(records), "authored_headers": sum(r["classification"] == "authored" for r in records.values()),
            "scope": document["scope"], "language": "en"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--public", action="store_true")
    parser.add_argument("--write-inventory", action="store_true")
    args = parser.parse_args()
    result = audit(args.root, args.public, args.write_inventory)
    print("PASS: publication attribution, text/syntax/provenance and inventory:", json.dumps(result))


if __name__ == "__main__":
    main()
