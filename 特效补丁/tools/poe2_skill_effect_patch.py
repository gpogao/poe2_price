#!/usr/bin/env python3
"""Build a PoE2 skill effect simplification patch zip.

Replaces particle effect templates (.pet), effect packs (.epk), and trail
effects (.trl) with minimal empty stubs so the game renders nothing for them.

Also supports asset-based modifications:
  - fog: modified .env + bloom shaders (from 易泥 去除迷雾)
  - viewdistance: modified character.ot (from 易泥 调整视距 2x)
  - minimap: modified minimap shaders (from 易泥 小地图全开)

These assets are pre-extracted from a 易泥-modified game state into
assets/<scope>/ and included verbatim in the patch zip.

Supports multiple scopes so users can choose which categories to simplify:
  spells, mtx, monsters, environment, other, fog, viewdistance, minimap, or all.
"""

from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

SCRIPT_DIR = Path(__file__).resolve().parent
PATCH_ROOT = SCRIPT_DIR.parent
STUBS_DIR = PATCH_ROOT / "empty_stubs"
PATHS_DIR = PATCH_ROOT / "paths"
ASSETS_DIR = PATCH_ROOT / "assets"

SCOPE_FILES = {
    "spells": "paths_spells.txt",
    "mtx": "paths_mtx.txt",
    "monsters": "paths_monsters.txt",
    "environment": "paths_environment.txt",
    "other": "paths_other.txt",
}

# Asset-based scopes: files are pre-extracted and stored in assets/<dir>/
ASSET_SCOPES: dict[str, str] = {
    "fog": "fog",
    "viewdistance": "viewdistance",
    "minimap": "minimap",
}

# scopes that use path lists + stubs (particle removal)
PARTICLE_SCOPES = tuple(SCOPE_FILES.keys())

ALL_SCOPES = PARTICLE_SCOPES + tuple(ASSET_SCOPES.keys())

STUB_EXTENSIONS = {
    ".pet": "empty.pet",
    ".trl": "empty.trl",
    ".epk": "empty.epk",
}


def _load_stubs() -> dict[str, bytes]:
    stubs: dict[str, bytes] = {}
    for ext, filename in STUB_EXTENSIONS.items():
        stub_path = STUBS_DIR / filename
        if stub_path.is_file():
            stubs[ext] = stub_path.read_bytes()
    return stubs


def _read_paths(scope: str) -> list[str]:
    path_file = PATHS_DIR / SCOPE_FILES[scope]
    if not path_file.is_file():
        raise FileNotFoundError(
            f"Path list for scope '{scope}' not found: {path_file}"
        )
    paths: list[str] = []
    with open(path_file, encoding="utf-8") as fh:
        for line in fh:
            stripped = line.strip()
            if stripped:
                paths.append(stripped)
    return paths


def _stub_for_path(path: str, stubs: dict[str, bytes]) -> bytes | None:
    path_lower = path.lower()
    for ext, data in stubs.items():
        if path_lower.endswith(ext):
            return data
    # Skip .ao and other types we don't have stubs for yet
    return None


def _collect_asset_files(scope: str) -> list[Path]:
    """Return sorted list of asset files for an asset-based scope."""
    asset_dir = ASSETS_DIR / ASSET_SCOPES[scope]
    if not asset_dir.is_dir():
        return []
    files: list[Path] = []
    for p in sorted(asset_dir.rglob("*")):
        if p.is_file():
            files.append(p)
    return files


def build_patch(
    scopes: list[str],
    output_zip: Path,
    report: Path | None = None,
) -> None:
    stubs = _load_stubs()
    asset_scopes_requested = [s for s in scopes if s in ASSET_SCOPES]
    particle_scopes = [s for s in scopes if s in PARTICLE_SCOPES]

    if not particle_scopes and not asset_scopes_requested:
        raise RuntimeError("No valid scopes requested")

    if particle_scopes and not stubs:
        raise RuntimeError("No stub files found in " + str(STUBS_DIR))

    output_zip.parent.mkdir(parents=True, exist_ok=True)

    stubbed_count = 0
    skipped_count = 0
    asset_count = 0
    by_scope: dict[str, int] = {s: 0 for s in scopes}

    # ── Collect particle paths ──
    seen: set[str] = set()
    all_particle_paths: list[str] = []
    for scope in particle_scopes:
        for path in _read_paths(scope):
            if path not in seen:
                seen.add(path)
                all_particle_paths.append(path)

    # Build reverse lookup: path -> scope
    path_scope: dict[str, str] = {}
    for scope in particle_scopes:
        for path in _read_paths(scope):
            if path not in path_scope:
                path_scope[path] = scope

    with zipfile.ZipFile(
        output_zip, "w", compression=zipfile.ZIP_DEFLATED
    ) as zf:
        # ── Write particle stubs ──
        for path in all_particle_paths:
            entry_name = path.replace("\\", "/")
            stub = _stub_for_path(path, stubs)
            if stub is not None:
                zf.writestr(entry_name, stub)
                stubbed_count += 1
                scope_name = path_scope.get(path, "unknown")
                by_scope[scope_name] = by_scope.get(scope_name, 0) + 1
            else:
                skipped_count += 1

        # ── Write asset-based files (fog, viewdistance, minimap) ──
        for scope in asset_scopes_requested:
            asset_files = _collect_asset_files(scope)
            if not asset_files:
                print(f"  WARNING: no assets found for scope '{scope}' "
                      f"in {ASSETS_DIR / ASSET_SCOPES[scope]}")
                continue

            asset_dir = ASSETS_DIR / ASSET_SCOPES[scope]
            for file_path in asset_files:
                entry_name = str(file_path.relative_to(asset_dir)).replace("\\", "/")
                zf.write(file_path, entry_name)
                asset_count += 1
                by_scope[scope] = by_scope.get(scope, 0) + 1

    info = {
        "output_zip": str(output_zip),
        "scopes": scopes,
        "total_paths": len(all_particle_paths) + asset_count,
        "stubbed": stubbed_count,
        "skipped": skipped_count,
        "asset_files": asset_count,
        "by_scope": by_scope,
    }

    if report:
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(
            json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    print(f"skill effect patch: {stubbed_count} stubbed, "
          f"{asset_count} assets, {skipped_count} skipped")
    for scope in sorted(by_scope):
        print(f"  {scope}: {by_scope[scope]}")
    print(f"written: {output_zip}")


def clean_patch(
    scopes: list[str],
    output_zip: Path,
    report: Path | None = None,
) -> None:
    """Remove effect stub entries from an existing patch zip."""
    if not output_zip.is_file():
        print(f"patch zip not found, nothing to clean: {output_zip}")
        return

    particle_scopes = [s for s in scopes if s in PARTICLE_SCOPES]
    asset_scopes_to_clean = [s for s in scopes if s in ASSET_SCOPES]

    # ── Collect paths to remove ──
    paths_to_remove: set[str] = set()
    for scope in particle_scopes:
        for path in _read_paths(scope):
            paths_to_remove.add(path.replace("\\", "/"))

    for scope in asset_scopes_to_clean:
        asset_files = _collect_asset_files(scope)
        asset_dir = ASSETS_DIR / ASSET_SCOPES[scope]
        for file_path in asset_files:
            entry = str(file_path.relative_to(asset_dir)).replace("\\", "/")
            paths_to_remove.add(entry)

    if not paths_to_remove:
        print("no paths to clean")
        return

    removed = 0
    import tempfile
    import os

    with zipfile.ZipFile(output_zip, "r") as zf:
        entries_before = len(zf.infolist())
        keep = [
            info
            for info in zf.infolist()
            if info.filename.replace("\\", "/") not in paths_to_remove
        ]
        if len(keep) == entries_before:
            print(f"no matching entries found in {output_zip}")
            return

        removed = entries_before - len(keep)
        fd, temp_name = tempfile.mkstemp(
            prefix="effect_clean_", suffix=".zip", dir=str(output_zip.parent)
        )
        os.close(fd)
        Path(temp_name).unlink(missing_ok=True)
        try:
            with zipfile.ZipFile(
                temp_name, "w", compression=zipfile.ZIP_DEFLATED
            ) as out:
                for info in keep:
                    out.writestr(info, zf.read(info.filename))
            Path(temp_name).replace(output_zip)
        finally:
            try:
                Path(temp_name).unlink()
            except FileNotFoundError:
                pass

    print(
        f"effect stubs cleaned: {removed} removed, "
        f"{entries_before - removed} remaining in {output_zip}"
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a PoE2 skill effect simplification patch zip."
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    build = sub.add_parser("build", help="add effect stubs to a patch zip")
    build.add_argument(
        "--scope",
        default="all",
        help="Effect categories to simplify: all, or comma-separated: "
        "easyfarm,spells,mtx,monsters,environment,other,fog,viewdistance,minimap",
    )
    build.add_argument(
        "--output-zip", type=Path, default=Path("特效补丁.zip")
    )
    build.add_argument("--report", type=Path)

    clean = sub.add_parser(
        "clean", help="remove effect stubs from a patch zip"
    )
    clean.add_argument(
        "--scope",
        default="all",
        help="Effect categories to clean: all, or comma-separated",
    )
    clean.add_argument(
        "--output-zip", type=Path, default=Path("特效补丁.zip")
    )
    clean.add_argument("--report", type=Path)

    return parser.parse_args(argv)


META_SCOPES: dict[str, list[str]] = {
    "easyfarm": ["fog", "viewdistance", "minimap"],
}


def _resolve_scopes(scope_arg: str) -> list[str]:
    arg = scope_arg.strip().lower()
    if arg == "all":
        return list(ALL_SCOPES)
    requested = [s.strip().lower() for s in arg.split(",") if s.strip()]
    resolved: list[str] = []
    for s in requested:
        if s in META_SCOPES:
            resolved.extend(META_SCOPES[s])
        elif s not in ALL_SCOPES:
            raise ValueError(
                f"Unknown scope '{s}'. Valid: all, easyfarm, "
                f"{', '.join(ALL_SCOPES)}"
            )
        else:
            resolved.append(s)
    return resolved


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    scopes = _resolve_scopes(args.scope)
    if args.cmd == "build":
        build_patch(
            scopes=scopes,
            output_zip=args.output_zip,
            report=args.report,
        )
    elif args.cmd == "clean":
        clean_patch(
            scopes=scopes,
            output_zip=args.output_zip,
            report=args.report,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
