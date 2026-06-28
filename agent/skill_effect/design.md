# POE2 特效补丁 — 设计文档

## 架构

独立工具 `特效补丁/`，与 `物价补丁/` 完全隔离。

```
特效补丁/
├── tools/
│   ├── update_effect_patch.ps1     ← 主入口（更新/还原）
│   ├── effect_patch_common.ps1      ← 共享函数（游戏检测、运行时解析）
│   ├── poe2_skill_effect_patch.py   ← 空壳 zip 生成
│   ├── PatchBundle3.exe             ← 编译自 LibGGPK3（写入 Bundle）
│   ├── StripAoEffects.exe           ← 编译自 LibGGPK3（清空 .ao 特效块）
│   └── fix_bundle_path.py          ← （废弃）曾用于 LibGGPK3→TinyBndl 重命名
├── empty_stubs/                     ← .pet/.epk/.trl 空壳模板
├── paths/                           ← 按 scope 分类的特效文件路径
└── output/
    ├── backup/_.index.bin           ← 首次安装时备份
    └── 特效补丁.zip                 ← 生成的补丁包
```

## 修改机制

### 1. `.ao` 文件 — StripAoEffects.exe (C#)
- 读取每个 `.ao` 的 UTF-16LE 文本
- 清空 `ParticleEffects { ... }` → `ParticleEffects {}`
- 清空 `SoundEvents { ... }` → `SoundEvents {}`
- 清空 `AttachedAnimatedObject { ... }` → `AttachedAnimatedObject {}`
- 按 Bundle 分组处理，每个 Bundle 只打开一次

### 2. `.pet` / `.epk` / `.trl` 文件 — poe2_skill_effect_patch.py
- `.pet` → 14 字节空壳 (`\r\n 0\r\n `)
- `.epk` → 2 字节空壳 (` `)
- `.trl` → 14 字节空壳
- 打包为 zip

### 3. 写入 — PatchBundle3.exe
- 使用修改版 LibBundle3（`CUSTOM_BUNDLE_BASE_PATH = "ZZZZZZZZ/"`）
- 写入 `Bundles2/ZZZZZZZZ/0.bundle.bin`
- `ZZZZZZZZ` 按字母序排在 `Tiny.V*` 之后，优先级最高

## 关键发现

### PatchBundle3 的问题
LibBundle3 硬编码了 `CUSTOM_BUNDLE_BASE_PATH = "LibGGPK3/"`（`Index.cs:651`）。
`LibGGPK3` 按字母序排在 `Tiny.V*` 之前，导致原始特效覆盖我们的空壳。
修改为 `"ZZZZZZZZ/"` 后优先级最高。

### `.ao` 是特效的关键入口
仅替换 `.pet`/`.epk`/`.trl` 不够——`.ao` 文件中的 `ParticleEffects` 块引用了这些文件。
即使 `.pet` 是空的，只要 `.ao` 还在引用，引擎可能走默认渲染路径。
易泥同时处理 `.ao` + `.pet`/`.epk`/`.trl`。

## Scope 分类

基于易泥实际修改的 35,251 个路径：

| Scope | 路径模式 | 文件数 |
|-------|---------|--------|
| spells | `metadata/effects/spells/` | 11,699 |
| mtx | `metadata/effects/microtransactions/` | 8,846 |
| monsters | `metadata/particles/monster_effects/` + `metadata/monsters/` | 6,196 |
| environment | `metadata/effects/environment/` + `metadata/terrain/` + `metadata/environmentsettings/` | 3,287 |
| other | 其他 | 5,223 |
| **fog** (new) | 848 `.env` + 2 bloom `.hlsl` | 850 |
| **viewdistance** (new) | `character.ot` | 1 |
| **minimap** (new) | 2 minimap `.hlsl` | 2 |

## 易泥四个选项完整覆盖

| 易泥选项 | 文件类型 | 数量 | 改动方式 | 我们的实现 |
|---------|---------|------|---------|-----------|
| **去除迷雾** | `.env` + bloom `.hlsl` | 850 | 定向修改 .env 雾参数 + shader | `assets/fog/` → zip 直接复制 |
| **去除粒子** | `.ao` + `.pet` + `.epk` + `.trl` | 34,398 | .ao 清空特效块 + 空壳替换 | ✅ Stripper + stubs |
| **调整视距 2x** | `character.ot` | 1 | 参数微调 | `assets/viewdistance/` → zip 直接复制 |
| **小地图全开** | minimap `.hlsl` | 2 | shader 修改 | `assets/minimap/` → zip 直接复制 |

### 非粒子文件的处理
- 不能简单替换为空壳，需要定向修改内容
- 方案：从易泥修改后的游戏提取文件 → 存放 `assets/<scope>/` → build_patch 时按原路径写入 zip
- 提取工具：`build/AssetExtractor/` (C#) 或 `特效补丁/tools/extract_assets.ps1`
