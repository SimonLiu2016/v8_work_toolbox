## Context

本变更是对 `merge-clean-builds-into-slimmer` 的补充修复。后者刚落地时 Tier A 发现机制有三个叠加缺陷（详见 proposal.md 的 Why），导致本机 `~/Workspace/ctf-gitlab/dc-promotion`（depth 4，含 `.git` + `pom.xml` + 112MB `target/`）完全漏扫。

`merge-clean-builds-into-slimmer` 尚未归档，本变更与它一起应用后再统一归档。

## Goals

- depth 4 的真实项目根不再漏扫
- 无 `.git` 的 Maven/Rust 项目不再漏扫
- 包管理器缓存不再被误判为项目根（降噪，不是性能前置条件）
- `~/Applications` 在本阶段剪枝但不影响已卸载残留检测

## Decisions

### D8: discoverMaxDepth 3 → 5

剪枝缓存后实测：

```
剪枝后 depth=3  →  54 根  /  1.2s
剪枝后 depth=4  → 557 根  /  8.1s   ← dc-promotion 在这层
剪枝后 depth=5  →  782 根  / 11.0s
```

depth 5 比 depth 4 只多 +225 根（+40%）但耗时 +2.9s。depth 5 已覆盖 99.7% 真实根（470/476，不含缓存），继续加深几乎不增收益。

**为什么不用 visit budget 替代 depth**：visit budget 是更正确的抽象（不猜深度、按实际成本限制），但 Tier A 的工作量瓶颈是 `listSync` 遍历的目录数而非访问次数，且 budget 数值同样需要校准。保持 depth 是最小改动，budget 留作后续改进。

### D9: 信号表补 pom.xml / Cargo.toml

纯加法，不影响任何既有行为。`pom.xml`（Maven）和 `Cargo.toml`（Rust）是常见构建系统，此前完全缺席。

### D10: 缓存剪枝与 artifactNames 分离

两个列表语义不同：
- `artifactNames`（Tier B）：命中即收集为产物候选，**可删除**
- `discoveryPruneDirs`（Tier A）：跳过不进入，**不是产物**

若混入 `artifactNames`，Tier B 会把 `.pub-cache` 等目录当作可删除产物——这是错误语义（删掉 `.pub-cache` 虽然安全但属于"全局缓存"而非"项目产物"，分类归属错误）。独立常量让语义清晰。

### D11: `~/Applications` 仅在 Tier A 剪枝

用户明确指示：应用或系统扫描时要扫到 `~/Applications`。已卸载残留检测（Tier 1/Orphaned app remnant detection）独立遍历 `~/Library/Application Support` / `Caches` / `Containers` 并对照 `/Applications` 和 `~/Applications` 中的已安装应用——该阶段不经过 `_walkDiscover`，不受本剪枝影响。

`~/Applications` 剪枝仅作用于 Tier A 的 `_walkDiscover`，避免 `.app` bundle 内的 manifest 文件（如 Flutter SDK 的 `package.json`）被误判为项目根。本机实测 `~/Applications` 含 33 个"根"。

## Risks / Trade-offs

- **[Tier A 耗时从 1.2s 增至约 11s]** → 仍在"数十秒"量级，且是阶段 4（渐进式，前 3 阶段已先上抛结果）。规格已将目标从"秒级"调整为"秒级至十余秒级"。
- **[Tier B 工作量增加]** → 根数从 46 增至约 782，但 Tier B 按根设预算（4s/根），且 782 根中大部分在剪枝后不会命中产物目录（只有真正的项目根才会）。实际 Tier B 耗时取决于命中数而非根数。
- **[缓存剪枝列表需维护]** → 新增包管理器时需同步更新。缓解：列表是单一常量，改动集中。
