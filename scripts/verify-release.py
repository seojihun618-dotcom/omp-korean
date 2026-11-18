import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

root = Path(__file__).resolve().parent.parent
manifest = json.loads((root / "release.json").read_text(encoding="utf-8"))
catalogs = {}
for language in ["en", "ko"]:
    pairs = json.loads((root / "locales" / (language + ".json")).read_text(encoding="utf-8"), object_pairs_hook=list)
    assert isinstance(pairs, list) and all(isinstance(pair, tuple) and len(pair) == 2 for pair in pairs), language
    assert len(pairs) == len({key for key, value in pairs}), language + " has duplicate keys"
    assert all(isinstance(value, str) for key, value in pairs), language + " has non-string values"
    catalogs[language] = dict(pairs)
assert catalogs["en"].keys() == catalogs["ko"].keys(), "Catalog keys differ"
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
archive = root / "release" / manifest["archive"]
with archive.open("rb") as stream:
    archive_hash = hashlib.file_digest(stream, "sha256").hexdigest()
assert (root / "release/SHA256SUMS").read_text(encoding="utf-8").strip() == archive_hash + "  " + archive.name
assert json.loads((root / "release/release.json").read_text(encoding="utf-8")) == manifest
results = []
with tempfile.TemporaryDirectory(prefix="omp-release-proof-") as temp:
    package = Path(temp)
    with zipfile.ZipFile(archive) as zipped:
        names = zipped.namelist()
        assert len(names) == len(set(names)), "Duplicate ZIP members"
        for name in names:
            assert "\\" not in name and ":" not in name and not name.startswith("/")
            assert ".." not in Path(name).parts
        for name in ["README.md", "LICENSE", "THIRD-PARTY-NOTICES.txt", "locales/en.json", "locales/ko.json"]:
            assert zipped.read(name) == (root / name).read_bytes(), name
        for lang in ["en", "ko"]:
            assert zipped.read("update/locales/" + lang + ".json") == zipped.read("locales/" + lang + ".json")
        members = {name: hashlib.sha256(zipped.read(name)).hexdigest() for name in names}
        zipped.extractall(package)
    env = os.environ.copy()
    env.pop("PI_PROFILE", None)
    env["PI_CODING_AGENT_DIR"] = str(package / "isolated-agent")
    env["PI_NATIVES_DIR"] = str(package / "isolated-natives")
    env["OMP_LOCALE_DIR"] = str(package / "locales")
    env["PATH"] = str(package) + os.pathsep + env["PATH"]
    catalog = (package / "locales/ko.json").read_bytes()
    scenarios = [("version", None, ["--version"], catalog, "omp/" + manifest["upstreamVersion"], False)]
    for language in [None, "", "en", "fr", "ko", "ko-KR"]:
        scenarios.append(("help-" + str(language), language, ["--help"], catalog, "사용법" if language in ["ko", "ko-KR"] else "USAGE", False))
    for language in ["en", "ko"]:
        scenarios.append(("smoke-" + language, language, ["--smoke-test"], catalog, "smoke-test: ok", False))
    for label, malformed in [("json", "{broken"), ("null", "null"), ("non-string", '{"Ready":false}'), ("placeholder", '{"Ready":"REJECTED_PACK_SECRET_{99}"}')]:
        scenarios.append(("invalid-" + label, "ko", ["--help"], malformed.encode("utf-8"), "USAGE", True))
    scenarios.append(("external-pack", "ko", ["--help"], b'{"USAGE":"RELEASE_EXTERNAL_PACK_PROOF"}', "RELEASE_EXTERNAL_PACK_PROOF", False))
    scenarios.append(("bom-pack", "ko", ["--help"], b'\xef\xbb\xbf{"USAGE":"RELEASE_BOM_PACK_PROOF"}', "RELEASE_BOM_PACK_PROOF", False))
    scenarios.append(("license", "en", ["--license"], catalog, "OMP License and Third-Party Notices", False))
    scenarios.append(("update-check", "en", ["update", "--check"], catalog, "Localized installed version: " + manifest["upstreamVersion"] + "; upstream stable:", False))
    update_inventory = None
    for label, language, args, pack, expected, diagnostic in scenarios:
        (package / "locales/ko.json").write_bytes(pack)
        before = {path.relative_to(package).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None for path in package.rglob("*") if path.relative_to(package).parts[0] not in ["isolated-agent", "isolated-natives"]}
        selected = env.copy()
        if language is None:
            selected.pop("OMP_LANG", None)
        else:
            selected["OMP_LANG"] = language
        result = subprocess.run([str(package / "omp.exe"), *args], cwd=package, env=selected, capture_output=True, timeout=180)
        stdout = result.stdout.decode("utf-8", errors="replace")
        stderr = result.stderr.decode("utf-8", errors="replace")
        (output / (label + ".stdout.log")).write_bytes(result.stdout)
        (output / (label + ".stderr.log")).write_bytes(result.stderr)
        assert result.returncode == 0, (label, result.returncode, stderr)
        assert expected in stdout, (label, expected)
        if label.startswith("help-"):
            assert all(flag in stdout for flag in ["--offline", "KIRO_API_KEY", "OTARI_BASE_URL", "KEENABLE_API_KEY"]), label
            if language in ["ko", "ko-KR"]:
                assert "기본 제공 도구 (--tools에 지정할 이름)" in stdout and "보조 서비스를 활성 모델의 제공업체로 제한" in stdout, label
        if diagnostic:
            assert "using English" in stderr and "{99}" not in stderr and "broken" not in stderr and "REJECTED_PACK_SECRET" not in stderr, label
        after = {path.relative_to(package).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None for path in package.rglob("*") if path.relative_to(package).parts[0] not in ["isolated-agent", "isolated-natives"]}
        assert before == after, (label, "Packaged files changed")
        if label == "update-check":
            update_inventory = {"before": before, "after": after}
        results.append({"name": label, "language": language, "args": args, "exit": result.returncode, "managedFilesUnchanged": True})
    (output / "proof.json").write_text(json.dumps({"version": manifest["version"], "archiveSha256": archive_hash, "members": members, "commands": results, "updateInventory": update_inventory}, indent=2), encoding="utf-8")
command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(root / "scripts/test-installer.ps1"), "-ArchivePath", str(archive), "-ChecksumPath", str(root / "release/SHA256SUMS"), "-ManifestPath", str(root / "release/release.json")]
result = subprocess.run(command, cwd=root, capture_output=True, timeout=900)
(output / "installer.stdout.log").write_bytes(result.stdout)
(output / "installer.stderr.log").write_bytes(result.stderr)
assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
(output / "delivery.json").write_text(json.dumps({"version": manifest["version"], "archiveSha256": archive_hash, "binaryScenarios": len(results), "installerExit": result.returncode}, indent=2), encoding="utf-8")
print(json.dumps({"version": manifest["version"], "binaryScenarios": len(results), "installer": "PASS", "sha256": archive_hash}))
