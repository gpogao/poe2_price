# POE2 技能特效简化 — 实现记录

**Goal:** 独立的特效简化工具 `特效补丁/`，通过空壳替换消除技能视觉特效

**Status:** 已实现

## 架构

```
特效补丁/
├── tools/
│   ├── update_effect_patch.ps1     ← 主入口（更新/还原)
│   ├── effect_patch_common.ps1     ← 共享函数
│   ├── poe2_skill_effect_patch.py  ← .pet/.epk/.trl 空壳生成
│   ├── PatchBundle3.exe            ← 写入 Bundle（需特殊编译）
│   └── StripAoEffects.exe          ← .ao 文件特效块清空（需编译）
├── empty_stubs/                    ← 空壳模板
├── paths/                          ← 特效文件路径（按 scope）
└── output/
```

## 修改机制

### .ao 文件 — StripAoEffects.exe
- 读取 UTF-16LE 文本，清空 `ParticleEffects`/`SoundEvents`/`AttachedAnimatedObject` 块
- 按 Bundle 分组批量处理

### .pet / .epk / .trl — poe2_skill_effect_patch.py
- `.pet` → 14B, `.epk` → 2B, `.trl` → 14B 空壳
- 打包 zip

### 写入 — PatchBundle3.exe (修改版)
- `LibBundle3/Index.cs:651`: `CUSTOM_BUNDLE_BASE_PATH = "ZZZZZZZZ/"`
- `ZZZZZZZZ` 字母序 > `Tiny.V*`，最高优先级

## 关键发现
1. PatchBundle3 硬编码了 `LibGGPK3/`，其字母序低于 `Tiny.V*`，导致原始特效覆盖补丁
2. 仅替换 `.pet`/`.epk` 不够，必须同时清空 `.ao` 中的 `ParticleEffects` 引用
3. 工作流：备份索引 → StripAoEffects → poe2_skill_effect_patch.py → PatchBundle3
