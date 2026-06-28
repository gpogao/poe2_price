> **本文件夹内容用于 vibe coding，AI 快速学习本项目基础内容，以及索引模块相关更改和知识，由 AI 自主维护，轻易勿动！**

---

# POE2 价格补丁工具

## 项目设计目的

POE2 价格补丁工具是一个用于 Path of Exile 2（流亡黯道2）的物品价格显示补丁生成和管理系统。该工具的主要功能是：

1. **自动获取物品价格**：从 poe2.science 等数据源获取游戏中物品的当前市场价格
2. **生成补丁文件**：将价格信息嵌入游戏数据文件中，使物品名称后显示价格（如 `Exalted Orb = 150D`）
3. **支持双平台**：兼容官方版（GGPK格式）和 Steam/Epic 版（Bundles2 格式）
4. **一键安装/还原**：用户可以通过脚本一键安装价格补丁或还原到原始状态

## 项目架构简介

### 1. 物价补丁（物价补丁）

项目核心模块，包含价格补丁的生成、安装、还原全部业务逻辑。

**目录结构：**
```
物价补丁/
├── tools/                           # 主工具目录
│   ├── update_price_patch.ps1        # 安装/更新价格补丁
│   ├── restore_price_patch.ps1       # 还原原始文件
│   ├── poe2_patch_common.ps1         # 公共函数库（模式检测、路径函数等）
│   ├── build_poe2scout_price_patch.py # 价格数据获取脚本
│   ├── poe2_name_price_patch.py      # 补丁生成脚本
│   ├── BundleExtractor/              # Steam 版文件提取工具
│   │   ├── BundleExtractor.exe       # 主程序（引用 build/BundleExtractor 项目）
│   │   └── oo2core.dll               # Oodle 解压缩库
│   └── GGPKExtractor/                # 官方版文件提取工具
│       ├── GGPKExtractor.exe         # 主程序
│       ├── LibGGPK3.dll              # GGPK 处理库
│       └── oo2core.dll               # Oodle 解压缩库
└── 一键安装特殊补丁工具/             # 发布打包工具
    ├── PatchBundledGGPK3.dll         # 官方版补丁安装工具
    ├── PatchBundledGGPK3.runtimeconfig.json
    ├── PatchBundle3.exe              # Steam 版补丁安装工具
    ├── PatchBundle3.dll
    ├── PatchBundle3.runtimeconfig.json
    ├── LibGGPK3.dll                  # GGPK 处理库
    ├── LibBundledGGPK3.dll           # 综合处理库
    ├── LibBundle3.dll                # Bundle 处理库
    ├── SystemExtensions.dll
    └── oo2core.dll                   # Oodle 解压缩库
```

**工具来源：**
- 所有工具均来自 [LibGGPK3](https://github.com/aianlinb/LibGGPK3) 社区项目
- 工具已预置在项目中，无需额外下载
- 如需更新工具，请从 LibGGPK3 发布页获取最新版本

**工作流程：**
```
┌─────────────────────────────────────────────────────────────┐
│ 1. 模式检测                                                 │
│    官方版：检测 Content.ggpk 存在 → GGPK 模式               │
│    Steam版：检测 Bundles2\_.index.bin 存在 → Bundles2 模式  │
├─────────────────────────────────────────────────────────────┤
│ 2. 提取游戏数据                                             │
│    GGPK模式：GGPKExtractor.exe 从 Content.ggpk 提取         │
│    Bundles2模式：BundleExtractor.exe 从 bundle 提取         │
├─────────────────────────────────────────────────────────────┤
│ 3. 生成补丁                                                 │
│    Python 脚本获取价格 → 修改 BaseItemTypes.datc64           │
├─────────────────────────────────────────────────────────────┤
│ 4. 安装补丁                                                 │
│    GGPK模式：PatchBundledGGPK3.dll 写入 Content.ggpk        │
│    Bundles2模式：PatchBundle3.exe 写入 bundle 文件           │
└─────────────────────────────────────────────────────────────┘
```

### 2. build/BundleExtractor（Bundle 提取工具）

独立的 C# 项目，为支持 Steam/Epic 版本（Bundles2 格式）而开发，位于 `build/` 目录下。

| 项目 | 说明 |
|------|------|
| **功能** | 从 Steam 版 `.bundle.bin` 文件中提取指定文件 |
| **依赖** | LibBundle3.dll（社区开源库）、oo2core.dll（Oodle 压缩） |
| **部署** | 编译后复制到 `物价补丁/tools/` 供主项目调用 |
| **源码** | `build/BundleExtractor/Program.cs` |
| **发布** | `build/BundleExtractor/publish/BundleExtractor.exe` |

### 3. 特效补丁（特效补丁）

独立的特效简化工具，与物价补丁完全隔离。

| 文件 | 说明 |
|------|------|
| **tools/update_effect_patch.ps1** | 一键更新/还原入口（8个 scope） |
| **tools/effect_patch_common.ps1** | 共享函数（游戏检测、运行时解析） |
| **tools/poe2_skill_effect_patch.py** | 补丁 zip 生成（空壳 + 资产文件） |
| **tools/StripAoEffects.exe** | 清空 .ao 文件特效引用 |
| **tools/PatchBundle3.exe** | 写入 ZZZZZZZZ/ bundle（修改版 LibBundle3） |
| **tools/extract_assets.ps1** | 从易泥提取 fog/viewdistance/minimap 资源 |
| **assets/** | 预修改文件 (fog: 850, viewdistance: 1, minimap: 2) |
| **empty_stubs/** | .pet/.epk/.trl 空壳模板（14/2/14 字节） |
| **paths/** | 按 scope 分类的特效文件路径（来自易泥分析） |

技术要点：
- 修改了 `LibBundle3/Index.cs:651` 的 `CUSTOM_BUNDLE_BASE_PATH` 从 `"LibGGPK3/"` 改为 `"ZZZZZZZZ/"`，确保补丁 bundle 按字母序优先级最高
- 8 个 scope：5 个粒子类 (spells/mtx/monsters/environment/other) + 3 个资产类 (fog/viewdistance/minimap)
- 资产类 scope 对应易泥的 去除迷雾/调整视距/小地图全开，使用 `build/AssetExtractor` 提取

### 4. Agent（AI 助手目录）

AI 助手学习项目结构和变更记录的专用目录。

| 文件 | 说明 |
|------|------|
| **index.md** | 项目主索引文档，概述设计目的和架构模块 |
| **skill_effect/** | 特效补丁设计文档和分析数据 |
| **模块子目录/** | 变更记录 |

### 5. build（构建工具目录）

发布打包相关的 C# 项目，用于生成独立 exe 启动器。

| 项目 | 说明 |
|------|------|
| **BundleExtractor** | Steam 版 bundle 文件提取工具 |
| **AssetExtractor** | 批量提取特效资产（fog/viewdistance/minimap） |
| **PayloadPacker** | 加密 payload.zip → payload.enc（嵌入 exe） |
| **Poe2PatchLauncher** | 独立 exe 启动器，解密并运行嵌入的脚本 |

**发布流程：**
```
1. PayloadPacker.exe 加密 物价补丁.zip → payload.enc
2. Poe2PatchLauncher.exe 嵌入 payload.enc
3. 用户运行 exe → 自动解密 → 提取脚本 → 执行 PowerShell
```

### 5. .gitignore（版本控制忽略规则）

控制 Git 忽略的文件和目录，避免上传不必要的文件。

| 忽略内容 | 说明 |
|----------|------|
| `build/**/bin/` | 编译输出目录 |
| `build/**/obj/` | 编译中间文件 |
| `build/**/publish/` | 发布输出目录 |
| `物价补丁/output/` | 运行时输出（提取的 datc64 等） |
| `物价补丁/*.zip` | 运行时生成的补丁文件 |
| `*.tmp`, `*.log` | 临时文件 |

---

## 重要规则

**模块变更记录规范**：每当对架构中的任意模块进行增删改操作时，必须在 `agent` 文件夹下找到对应模块的子文件夹（通过 `index.md` 中的模块名称定位），并在该文件夹内新建一个以 `YYYY-MM-DD-变更摘要.md` 格式命名的变更记录文件。
