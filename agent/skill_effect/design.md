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
