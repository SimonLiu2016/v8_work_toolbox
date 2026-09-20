# Tasks: merge-clean-builds-into-slimmer

## 1. 模型与扫描服务骨架

- [x] 1.1 `slimmer_models.dart`：`SlimmerCategory` 新增 `projectArtifacts`（项目构建产物），描述文案明确"逐项目"与 `buildCache`（跨项目共享缓存）的范围差异
- [x] 1.2 `SlimCandidateItem` 新增聚合所需字段：产物明细列表（path + size + 类型）、`scanIncomplete` 标记（扫描超时/未完整）、技术栈标识；`copyWith` 与构造参数同步补齐，既有调用点不受影响
- [x] 1.3 新增 `lib/tools/slimmer/project_artifact_detector.dart`，先落空实现（返回空列表），确认 `DiskScannerService` 第 4 阶段接入点可编译
- [x] 1.4 `disk_scanner_service.dart`：接入第 4 阶段（Tier A → Tier B 顺序），复用既有 `notify(stage: 4, ...)` 进度上报与阶段 3 的 yield 节奏；阶段 1–3 行为不变

## 2. Tier A：浅层项目根发现

- [x] 2.1 实现 Tier A：`HOME` 下 `maxDepth 3` 遍历，按 manifest 信号识别项目根（`.git`、`package.json`、`pubspec.yaml`、`build.gradle`、`build.gradle.kts`、`Podfile`、`CMakeLists.txt`、`go.mod`），去重后返回根路径集合
- [x] 2.2 Tier A 剪枝：不下降进 `~/Library`（阶段 1 已覆盖全局缓存）、`node_modules`、`.git`、`build`、`dist`、`.gradle` 等已知产物目录自身；MUST 排除 `HOME` 自身作为根（实测：裸 `~/package.json` 会让 `HOME` 吞掉全部其他根）
- [x] 2.3 Tier A 非阻塞：复用 `_calcDirSize` 的分批 yield 节奏，遍历期间 UI 帧率不塌
- [x] 2.4 本机实测基线已校准（2026-09-14）：提议的 Tier A 全量运行 2.5 秒，产出 672 个根、去嵌套后 670 个；670 个根中 160 个（24%）在根目录层即直接命中产物 → Tier B 工作量不会因剪枝而可忽略，预算必须真实生效。若实现期数字偏离此基线 >30%，需说明原因

## 3. Tier B：产物收集与门控

- [x] 3.1 实现 Tier B：对每个项目根做剪枝遍历收集产物目录（`node_modules`、`build`、`dist`、`.gradle`、`.dart_tool`、`.git` 除外、`target`、`cmake-build-debug`、`out`、`__pycache__`），命中判定受 `artifactOptions` 开关控制
- [x] 3.2 manifest 门控：产物命中 MUST 位于被识别的项目根内；裸顶层同名目录（如 `~/node_modules`）不产出候选项
- [x] 3.3 剪枝：遍历不下降进 `.git` 与已命中的产物目录自身，避免重复计数与体积热点
- [x] 3.4 预算：单根时间预算 + 产物数量上限；超预算的根标记 `scanIncomplete` 并上抛已发现部分，不中断后续根，不静默丢弃
- [x] 3.5 产物类型聚合：按类型统计命中数与大小，生成条目 `subtitle` 构成摘要（如"23 个产物目录 · node_modules ×5 / build ×8"）
- [x] 3.6 技术栈推导：按最具体信号优先级（`build.gradle`/`.gradle` > `pubspec.yaml`/`.dart_tool` > `package.json`/`node_modules` > 兜底"其他"）为每个根归类，无信号根归入"其他构建产物"

## 4. 阈值、稳定身份与分类

- [x] 4.1 列表呈现阈值：仅呈现"≥1 个命中且合计 ≥10MB"的项目根，小根不计入释放空间汇总
- [x] 4.2 稳定身份键：聚合项 `id` 使用项目根路径，使 `getSlimerKeepList`（以 path 为键）按根粒度生效
- [x] 4.3 验证保留清单跨扫描生效：取消勾选 → 重扫 → 同根自动未勾选并标记保留

## 5. UI：分组呈现与可展开明细

- [x] 5.1 项目产物按技术栈分组呈现：组为列表行（根数 + 聚合大小），展开显示组内项目根条目
- [x] 5.2 复用 `_buildCategoryTabs` 的 `ChoiceChip` 体系做技术栈筛选；`projectArtifacts` 与 `buildCache` 两个分类可独立筛选且互不混入
- [x] 5.3 项目根条目可展开查看该根内的每个产物目录 path 与 size
- [x] 5.4 `scanIncomplete` 条目显示"扫描超时 / 未完整"标记，已发现部分照常可见
- [x] 5.5 列表行数实测：本机 670 根场景下列表高度不失控（组行数而非 670 行）

## 6. 回收策略统一

- [x] 6.1 构建产物走既有废纸篓回收 + 物理校验流程，与其余候选项完全一致
- [x] 6.2 移除原 `clean-builds` 的永久删除路径（`delete(recursive: true)`），确认瘦身内不存在任何不可逆删除入口
- [x] 6.3 确认 root 属主/`~/Library/Containers` 场景下既有失败诊断与"授权管理员清理"对聚合项同样生效

## 7. 配置迁移

- [x] 7.1 `settings_store.dart`：迁移链路追加一步——`config/clean-builds.json` → 瘦身配置键（`configs` watchlist + `artifactOptions`），复制而非移动、原文件保留、只执行一次、不覆盖瘦身键中用户已有修改
- [x] 7.2 watchlist 根豁免 manifest 门控并强制进入 Tier B（D2 的逃生口）
- [x] 7.3 瘦身工具设置区呈现"额外项目根"配置，并说明"未在工作区内的产物需手动添加项目根"
- [x] 7.4 配置损坏/缺失时回退默认并给出可感知提示，不阻塞启动（沿用 settings-storage 既有容错）

## 8. 工具合并与注册表清理

- [x] 8.1 删除 `lib/tools/registry.dart` 中 `CleanBuildsToolDefinition` 类、注册表条目与 `clean_builds_tool.dart` import
- [x] 8.2 删除 `lib/clean_builds_tool.dart`
- [x] 8.3 最近使用重定向：历史 `clean-builds` 标识读取时映射为 `smart-disk-slimmer`，不显示空条目、不崩溃
- [x] 8.4 全局搜索确认无 `clean-builds` / `CleanBuilds` 的悬空引用（保留项：`settings_store.dart` 迁移表项、既有测试夹具字符串）

## 9. 规格同步：移除硬编码工具枚举

- [x] 9.1 `app-shell` 规格移除"现有 8 个工具（…清理构建产物）"硬编码枚举，改为"工具集以注册表为唯一来源"
- [x] 9.2 校验 `openspec validate --strict` 全绿

## 10. 测试

- [x] 10.1 Tier A：manifest 识别正确、`maxDepth 3` 边界、剪枝生效、去重（含嵌套根去重：`A` 是 `A/B` 的父目录时只保留 `A`）
- [x] 10.1a Tier A 退化用例：`HOME` 自身含 manifest 信号时不作为根返回，其下其他根不被吞掉（本机真实用例：裸 `~/package.json`）
- [x] 10.2 Tier B 门控：裸顶层 `~/node_modules` 不产出候选项（本机真实存在的误报场景）
- [x] 10.3 Tier B 预算：构造超预算根，断言 `scanIncomplete` 标记存在、已发现部分可见、后续根继续扫描
- [x] 10.4 聚合与阈值：命中 <10MB 的根不入列表、不计入释放汇总；条目 subtitle 构成摘要正确
- [x] 10.5 技术栈归类：`.gradle` 优先于 `pubspec.yaml` 的优先级顺序；无信号根归入"其他"
- [x] 10.6 分类筛选：`projectArtifacts` 与 `buildCache` 互斥筛选正确
- [x] 10.7 回收：构建产物经废纸篓且物理校验通过才移除 UI；不存在永久删除路径
- [x] 10.8 配置迁移：`clean-builds.json` 内容复制到瘦身键、原文件保留、只执行一次、不覆盖用户新设置
- [x] 10.9 最近使用重定向：含 `clean-builds` 的历史记录解析为 `smart-disk-slimmer`
- [x] 10.10 跑通既有测试（disk_slimmer / disk_slimmer_hardening_verify / admin_privilege_cleaner / settings_store / slimmer_dialog_contrast），确认无回归

## 11. 部署与真机验证

- [x] 11.1 `flutter build macos --release` 并替换 `/Applications/V8WorkToolbox.app`
- [x] 11.2 真机验证：扫描出项目产物分组、旧 watchlist 生效、废纸篓回收可逆、`clean-builds.json` 仍在磁盘
- [x] 11.3 侧边栏确认"清理构建产物"已消失、"包与构建"分类仅剩 KMA 包生成（空置分类问题不在本变更范围，仅记录）

## 12. 范围裁剪记录

- [x] 12.1 `ToolCategory.build` 空置问题：不做 —— 合并后仅剩 KMA 包生成，是否调整分类归属属独立的产品决策，本变更只记录为后续事项
- [x] 12.2 全盘"深度模式"开关：不做 —— 明确 Non-Goal；若日后需要，独立变更引入
- [x] 12.3 跨机器/多用户发现缓存共享：不做 —— 单机工具，无此需求
- [x] 12.4 无 manifest 且非 watchlist 根的产物发现：不做 —— 当前接受漏报（D2 代价），watchlist 为逃生口；若实测漏报比例高再立独立变更
