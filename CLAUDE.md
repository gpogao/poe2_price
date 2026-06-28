# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

POE2 物价补丁 — a Windows-only tool that annotates in-game item names in Path of Exile 2 with real-time market prices. It reads game data files, fetches prices from poe2scout (international) or poecurrency.top (China WeGame), patches `BaseItemTypes.datc64` / `Words.datc64` / `EndgameMaps.datc64`, and writes them back into the game. Supports three server variants: official standalone (GGPK), Steam/Epic (Bundles2), and China WeGame (Bundles2).

## Build & test commands

Everything runs on **Windows 10/11 x64**. Requires .NET 8 SDK and Python 3.10+.

```powershell
# Full release build (includes Word doc generation via python-docx)
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\make_release.ps1

# Skip Word doc generation
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\make_release.ps1 -SkipDoc

# Build just the BundleExtractor
dotnet publish build\BundleExtractor\BundleExtractor.csproj -c Release -r win-x64 -p:SelfContained=true -p:PublishSingleFile=true

# Dry-run the update script (no game file writes, useful for development)
powershell -NoProfile -ExecutionPolicy Bypass -File .\物价补丁\tools\update_price_patch.ps1 -Poe2Dir "<path>" -NoInstall -NoPoe2dbFallback
```

### Running tests

Tests are Python `unittest`-based, located in `tests/`. They import the source scripts directly via `importlib` — no package installation needed.

```powershell
# Run all tests
python -m pytest tests\ -v

# Run a single test file
python -m pytest tests\test_poecurrency_pricing.py -v

# Run a single test method
python -m pytest tests\test_poecurrency_pricing.py::PoecurrencyPricingTests::test_latest_buy_price_wins_over_avg_price -v

# Run tests without pytest (stdlib unittest)
python -m unittest discover -s tests -v
```

Tests are designed to run on any OS (not Windows-only) because they load and exercise the Python logic without touching game files or .NET tools.

## High-level architecture

The tool follows a **detect → extract → fetch → patch → install** pipeline:

```
poe2_patch_common.ps1          ← shared detection, path resolution, naming
    ├── update_price_patch.ps1  ← orchestrates the full update pipeline
    └── restore_price_patch.ps1 ← restores original game files
            │
            ├── GGPKExtractor.exe       ← extract from Content.ggpk (官服)
            ├── BundleExtractor.exe     ← extract from Bundles2 (Steam/国服)
            │
            ├── build_poe2scout_price_patch.py  ← fetch prices from APIs
            ├── poe2_name_price_patch.py        ← generate BaseItemTypes patch
            └── poe2_island_rumour_patch.py     ← generate EndgameMaps hints
            │
            ├── PatchBundledGGPK3.dll   ← write patches into GGPK
            └── PatchBundle3.exe        ← write patches into Bundles2
```

### PowerShell orchestration (`物价补丁/tools/`)

- **`poe2_patch_common.ps1`** — Shared module. Detects game installation type (GGPK vs Bundles2, China vs international) via `Get-Poe2InstallInfo`. Provides standard path/name functions using Unicode codepoint escaping to avoid encoding issues. **Every other script dot-sources this.**
- **`update_price_patch.ps1`** — Main entry point for applying the price patch. Steps: detect install → extract data files → run Python price/build scripts → write patches back. Accepts `-PatchScope`, `-IslandRumourHints`, `-SkipExtract`, `-NoInstall`, `-NoPoe2dbFallback`.
- **`restore_price_patch.ps1`** — Restores original files from backup zips. Bundles2 mode prefers a "physical restore" backup (`真实还原物价补丁.zip`) that captures actual bundle state before patching.

### Python scripts (`物价补丁/tools/`)

- **`build_poe2scout_price_patch.py`** — Fetches prices from the network. International: poe2scout API. China WeGame: poecurrency.top first, falls back to poe2scout. Handles D/E exchange rate derivation, `latest_buy1`/`latest_sell1` priority with geometric-mean fallback, and cross-source price blending (国服数据与国际服兜底). Writes a `poe2_price_data.json` consumed by the name-patch script.
- **`poe2_name_price_patch.py`** — Reads price JSON, rewrites `BaseItemTypes.datc64` and `Words.datc64` with price annotations appended to item display names. Currency prices go into BaseItemTypes; legendary items use a `[价格|传奇名]` format in Words that survives PoE Overlay II / 易刷 text parsing.
- **`poe2_island_rumour_patch.py`** — Optional: appends map-type hints to island rumour text in `EndgameMaps.datc64`. Maps known rumour rows (hardcoded indices per language) to hints like "金币图", "经验图", "传奇装备", "首领战", "地图/Boss". Supports 11 languages.

### .NET tools (`build/`)

- **`Poe2PatchLauncher`** — The `一键更新物价补丁.exe` / `一键还原物价补丁.exe` that end users run. Embeds an encrypted `payload.enc` (AES-GCM, key derived from a fixed seed). At runtime: decrypts payload → extracts zip to temp dir → launches `powershell.exe -File <script>`. Detects update vs restore mode from the exe filename. Sets `POE2_PATCH_RELEASE=1` so scripts know they're running in release mode.
- **`PayloadPacker`** — Build-time tool: reads `payload.zip` (the PowerShell + Python scripts + BundleExtractor binaries) and encrypts it into `payload.enc` for embedding.
- **`BundleExtractor`** — Standalone tool using LibBundle3 to extract virtual files from `Bundles2\_.index.bin`. Used at runtime by the PowerShell scripts to pull game data files.

### Release packaging (`build/make_release.ps1`)

The release build assembles a self-contained `物价补丁` folder:
1. Builds docs (Word `.docx` via `create_release_doc.py`)
2. Copies restore seed zips from `restore-seeds/` (local-only, not committed)
3. Publishes BundleExtractor from source
4. Packs payload scripts → `payload.zip` → `payload.enc` via PayloadPacker
5. Publishes `Poe2PatchLauncher` as a self-contained single-file exe (with embedded `payload.enc`)
6. Assembles the release folder with launcher exes, restore seeds, extractors, patch tools, and bundled .NET 8 + Python 3.10 runtimes
7. Validates the assembled folder, then copies to workspace output

### CI/CD (`.github/workflows/build-release.yml`)

GitHub Actions on `windows-latest`. Triggers: push to `main`, version tags (`v*`), or manual `workflow_dispatch`. Runs `make_release.ps1 -SkipDoc`, zips the output, uploads as artifact, and creates/updates a GitHub release.

## Key design conventions

### Price display strategy
- **Currency/普通物品**: Price appended directly into the target-language `BaseItemTypes.datc64` display name field.
- **Legendary items**: Written into `Words.datc64` using `[价格|传奇名]` format. PoE Overlay II and 易刷 strip the `[价格|...]` prefix when parsing Ctrl+C text, so the `name` query field stays clean while the price still shows in-game.
- Items below 1E threshold are not annotated. Prices below 0.1D are displayed in E instead.

### China vs international pricing
- **China WeGame**: `poecurrency.top/api/summary?version=2` first. Recognizes `currency_unit` (`e`/`d`). Uses `latest_buy1`/`latest_sell1` with geometric mean when spread ≤5x, otherwise takes the lower side. Falls back to `buy_avg`/`sell_avg` when latest prices are missing. Missing items fall back to poe2scout international prices.
- **International**: poe2scout API directly.
- **D/E rate**: Always derived live from the data source's "Divine Orb" / "神圣石" price — never hardcoded.

### Restore safety (Bundles2)
Bundles2 mode generates two restore zips:
- `还原物价补丁.zip` — resource-level backup (BaseItemTypes, Words datc64 content).
- `真实还原物价补丁.zip` — physical file backup of `_.index.bin` + related index files + `LibGGPK3/` directory. Preferred for restoration; restores the actual bundle state before patching.

Restore zip generation refuses to include `Words.datc64` that already contains price markers (any legacy format).

### Patch scope
Controlled by `-PatchScope` (CLI) or UI checkbox. `all` (default), `currency`, `uniques`, or `none`. The `currency` scope cleans old legendary price markers from Words; `uniques` scope preserves a clean BaseItemTypes baseline.

### Release mode detection
Scripts check `$env:POE2_PATCH_RELEASE -eq "1"` to know they're running inside the launcher. In release mode, bundled .NET/Python runtimes in `tools/dotnet-runtime/` and `tools/python/` are used instead of system-installed ones.

## File naming conventions

PowerShell uses Unicode codepoint escapes (`[char]0xNNNN`) for Chinese filenames in `poe2_patch_common.ps1` to avoid encoding corruption across different systems. Python scripts use plain Chinese characters since they declare UTF-8 encoding.


## 特效补丁 (`特效补丁/`)

A standalone tool (separate from `物价补丁/`) that simplifies POE2 skill visual effects by replacing effect files with empty stubs.

### Architecture
```
特效补丁/
├── tools/
│   ├── update_effect_patch.ps1     ← One-click update/restore
│   ├── effect_patch_common.ps1     ← Shared helpers (game detection, runtimes)
│   ├── poe2_skill_effect_patch.py  ← Generate patch zip (stubs + assets)
│   ├── PatchBundle3.exe            ← Patched LibBundle3 (writes to ZZZZZZZZ/)
│   ├── StripAoEffects.exe          ← Strips ParticleEffects from .ao files
│   └── extract_assets.ps1          ← Extract non-particle assets from 易泥
├── assets/                         ← Pre-modified files for fog/viewdistance/minimap
│   ├── fog/          (850 files: .env + bloom .hlsl)
│   ├── viewdistance/ (1 file: character.ot)
│   └── minimap/      (2 files: minimap .hlsl)
├── empty_stubs/                    ← .pet/.epk/.trl empty templates
├── paths/                          ← Particle path lists by scope
└── output/
```

### Modification mechanism
1. **`.ao` files**: `StripAoEffects.exe` empties `ParticleEffects`/`SoundEvents` blocks (UTF-16LE text parsing)
2. **`.pet`/`.epk`/`.trl` files**: `poe2_skill_effect_patch.py` writes 2-14 byte stubs into a zip
3. **`.bundle.bin` creation**: Modified `PatchBundle3.exe` (with `CUSTOM_BUNDLE_BASE_PATH = "ZZZZZZZZ/"` in `LibBundle3/Index.cs`) creates a bundle that sorts after `Tiny.V*` alphabetically for highest priority
4. **Non-particle assets** (fog/viewdistance/minimap): Pre-modified files stored in `assets/<scope>/` are included verbatim in the patch zip. These are extracted from a 易泥-modified game state using `AssetExtractor` (build/) or `extract_assets.ps1`.

### Scopes (8总)
- **Particle (stub-based, 5)**: `all`, `spells`, `mtx`, `monsters`, `environment`, `other`
- **Asset-based (3)**: `fog` (去除迷雾), `viewdistance` (调整视距 2x), `minimap` (小地图全开)
- Asset scopes require pre-extracted files in `assets/<scope>/` before they can take effect.

### Key changes from LibGGPK3
- `LibBundle3/Index.cs:651` — `CUSTOM_BUNDLE_BASE_PATH` changed from `"LibGGPK3/"` to `"ZZZZZZZZ/"` for alphabetical priority over `Tiny.V*`
- `LibGGPK3/Examples/StripAoEffects/` — Custom tool to empty ParticleEffects/SoundEvents blocks in .ao files
- `build/AssetExtractor/` — NEW: batch extraction tool for pulling non-particle assets from modified game state

### Build
```powershell
# Build modified PatchBundle3 (from LibGGPK3 repo)
dotnet publish LibGGPK3\Examples\PatchBundle3\PatchBundle3.csproj -c Release -r win-x64 --sc -p:PublishSingleFile=true

# Build StripAoEffects
dotnet publish LibGGPK3\Examples\StripAoEffects\StripAoEffects.csproj -c Release -r win-x64 --sc -p:PublishSingleFile=true

# Build AssetExtractor (for extracting fog/viewdistance/minimap assets)
dotnet publish build\AssetExtractor\AssetExtractor.csproj -c Release -r win-x64 --sc -p:PublishSingleFile=true
```

## Important constraints

- **Windows-only**: The .NET tools (GGPKExtractor, BundleExtractor, PatchBundle3, PatchBundledGGPK3) and PowerShell scripts only run on Windows. Python tests can run cross-platform.
- **Restore seeds are local**: `restore-seeds/` contains clean game data zips needed for building releases. These are not committed to git.
- **Non-commercial license**: This project is NOT open source for commercial use. See `使用许可.md` for full terms.
- **Modifies game files**: This tool writes to game data files and carries ban risk. All user-facing docs include this warning.
