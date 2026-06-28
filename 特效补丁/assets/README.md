# 特效补丁 Assets

This directory contains pre-modified game files extracted from a 易泥 (EasyFarm)
modified game state. These are used by `poe2_skill_effect_patch.py` when the
corresponding scopes are selected.

## Directory structure

```
assets/
├── fog/              ← 848 .env files + bloom shaders (去除迷雾)
├── viewdistance/     ← character.ot (调整视距 2x)
└── minimap/          ← minimap shaders (小地图全开)
```

Files preserve their original bundle paths:
```
assets/fog/metadata/environmentsettings/1_1_1.env
assets/viewdistance/metadata/characters/character.ot
assets/minimap/shaders/minimap_blending_pixel.hlsl
```

## How to populate

### Method 1: Extract from 易泥-modified game (recommended)

1. Apply 易泥 with all 4 options (去除迷雾 + 去除粒子 + 调整视距 + 小地图全开)
2. Run the extraction tool:
   ```powershell
   # Build AssetExtractor
   dotnet publish build\AssetExtractor\AssetExtractor.csproj -c Release -r win-x64 -p:SelfContained=true -p:PublishSingleFile=true

   # Extract fog assets
   .\build\AssetExtractor\bin\Release\net8.0\win-x64\AssetExtractor.exe `
       "D:\game\PathOfExile2\Bundles2\_.index.bin" `
       "特效补丁\assets\fog_paths.txt" `
       "特效补丁\assets\fog"

   # Extract viewdistance assets
   .\build\AssetExtractor\bin\Release\net8.0\win-x64\AssetExtractor.exe `
       "D:\game\PathOfExile2\Bundles2\_.index.bin" `
       "特效补丁\assets\viewdistance_paths.txt" `
       "特效补丁\assets\viewdistance"

   # Extract minimap assets
   .\build\AssetExtractor\bin\Release\net8.0\win-x64\AssetExtractor.exe `
       "D:\game\PathOfExile2\Bundles2\_.index.bin" `
       "特效补丁\assets\minimap_paths.txt" `
       "特效补丁\assets\minimap"
   ```

### Method 2: Use extract_assets.ps1 (one-step)

```powershell
.\特效补丁\tools\extract_assets.ps1 `
    -ModifiedIndex "D:\game\PathOfExile2\Bundles2\_.index.bin" `
    -OutputDir "特效补丁\assets"
```

This script uses BundleExtractor.exe to extract each file individually.

## Scopes

| Scope | Asset Dir | Files | Source |
|-------|-----------|-------|--------|
| `fog` | `assets/fog/` | 850 | 848 .env + 2 bloom .hlsl |
| `viewdistance` | `assets/viewdistance/` | 1 | character.ot |
| `minimap` | `assets/minimap/` | 2 | minimap shaders |
