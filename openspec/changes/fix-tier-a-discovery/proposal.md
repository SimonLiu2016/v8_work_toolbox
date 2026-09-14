## Why

`merge-clean-builds-into-slimmer` 刚落地后，本机实测发现 Tier A 项目根发现有三个叠加缺陷导致漏扫：

1. `discoverMaxDepth = 3` 够不到 depth 4 的真实项目根。实测 `dc-promotion`（`~/Workspace/ctf-gitlab/dc-promotion`）位于 depth 4，含 `.git` + `pom.xml` + 112MB `target/`，完全漏掉。
2. `manifestSignals` 缺 `pom.xml`（Maven）和 `Cargo.toml`（Rust），无 `.git` 的 Maven/Rust 项目漏掉。
3. 包管理器缓存目录（`.pub-cache`、`.npm`、`.yarn`、`.cache`、`.cargo`、`.rustup`、`.local`）未剪枝，被误判成项目根——depth 5 实测 1846 个"根"中超过 1000 个来自包缓存。

本机实测各深度耗时与根数：

```
未剪枝缓存:                     剪枝缓存后:
  depth=3 →  46 根  /  1.2s      depth=3 →  54 根  /  1.2s
  depth=4 → 543 根  /  8.7s      depth=4 → 557 根  /  8.1s
  depth=5 → 1846 根 / 18.6s      depth=5 →  782 根 / 11.0s
```

关键发现：缓存剪枝后根数 -58% 但耗时仅 -41%，且 depth 4 剪枝前后根数几乎相同（543 vs 557）——根数爆炸的主要来源是 depth 4 的**真实项目目录**（`~/Documents/ctf_new/*`、`~/Workspace/*`），不是包缓存。缓存剪枝仍是必要的降噪手段，但不是让"秒级"成立的前置条件。

`merge-clean-builds-into-slimmer` 尚未归档，本变更作为其补充修复落地于同一变更集内。

## What Changes

- `discoverMaxDepth`: 3 → 5（剪枝后覆盖 99.7% 真实根，本机 depth 5 仅 +225 根相对 depth 4 但根数已收敛）
- `manifestSignals`: 新增 `pom.xml`、`Cargo.toml`（无 `.git` 的 Maven/Rust 项目不再漏扫）
- Tier A 剪枝列表：新增包管理器缓存目录（`.pub-cache`、`.npm`、`.yarn`、`.cache`、`.cargo`、`.rustup`、`.local`）——这些是下载缓存不是用户项目，不应被识别为项目根
- Tier A 剪枝列表：新增 `~/Applications`——用户明确指示"应用或系统扫描时要扫到"，但构建产物扫描不需要（`.app` bundle 内的 manifest 文件如 Flutter SDK 会被误判）
- 缓存剪枝与 `artifactNames` 分离：`artifactNames` 是 Tier B 的产物名（删得掉的产物目录），缓存剪枝是 Tier A 的发现排除（不该被发现的目录）。语义不同，独立常量

**BREAKING**: 无。本变更只增不减，不影响既有扫描路径。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `disk-analyzer`: "Project build artifact discovery with manifest gating" 需求的 manifest 信号清单扩充（`pom.xml`、`Cargo.toml`），剪枝清单扩充（缓存目录 + `~/Applications`），发现深度边界调整
- `disk-scanner-async`: "项目根发现的预算边界" 需求的发现深度从 3 调整为 5，剪枝范围扩充

## Impact

- 代码：`lib/tools/slimmer/project_artifact_detector.dart`（信号表 + 剪枝列表 + 深度常量）
- 行为：Tier A 发现根数从 46 增至约 782（剪枝后），耗时从 1.2s 增至约 11s；Tier B 工作量相应增加
- 回归面：`~/Applications` 的剪枝仅作用于 Tier A（构建产物发现），不影响 Tier 1 的已卸载残留检测（该阶段独立遍历 `~/Library/Application Support`/`Caches`/`Containers`）
- 性能：本机实测剪枝后 depth 5 为 11s。若实测偏离 >30% 需说明原因（对应 tasks.md 第 15 行的基线校准要求）
