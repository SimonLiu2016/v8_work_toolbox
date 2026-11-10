# Design: 大模型试炼场重命名与提示词模板效果库

## Context

现有试炼场（`lib/tools/agnes_playground/`）已具备基于 `AiConfigStore` 的通用 Provider 与模型调度能力，但前端展示层与入口处处带有 "Agnes" 品牌烙印；同时，用户在图像与视频生成中缺乏直观的镜头运镜、武打动作、粒子光效、画风等维度的标准化提示词模版与模型实测样片。

本设计聚焦于第一阶段落地：完成试炼场品牌与入口对齐为「大模型试炼场」，建立全局视觉提示词模板体系（`VisualPromptTemplate`）与模型实测样张持久化底座（`PromptTemplateStore`），并在试炼场中集成模板抽屉与样片查验交互。

## Goals / Non-Goals

**Goals:**
- **全局品牌重命名**：工具中心（`registry.dart`）、独立窗口（`main.dart`）、试炼场主页（`playground_page.dart`）及工坊跳转统一升级为「大模型试炼场」。
- **提示词效果库领域模型与持久化**：
  - 设计包含 5 大体系、16 个细分维度的出厂预置模板数据集（`builtin_templates.json`）。
  - 实现基于应用支持目录（`AppPaths.sharedPromptTemplatesDir`）的全局单例 `PromptTemplateStore`，支持出厂自愈、用户自建、模型样张持久化与 Stream 响应。
- **模板与样片交互组件**：
  - 在试炼场控制台提供「提示词模板」抽屉面板，支持分类筛选、占位符高亮提示、一键应用至输入框。
  - 支持查看模板针对不同模型（如 Agnes Video、Kling、Runway 等）的实测样片、评分与评测参数。
- **对决模式 (Arena) 架构抽象**：为后续多模型并发跑测提供统一的 Draft 分发与多卡片渲染接口。

**Non-Goals:**
- **自动化海量爬虫抓取**：不自动抓取外部提示词网站，优先保证出厂预置的工业级精选品质与本地安全。
- **分镜看板深层全节点改造**：工坊分镜制作的深度一键套用归入第二阶段，第一阶段先在试炼场内实现完整闭环。

## Decisions

### 1. 全局应用级存储目录（Decoupled Global Storage）
- **选择**：模板元数据 `catalog.json` 与实测多媒体样张存放在 `~/Library/Application Support/V8WorkToolbox/prompt_templates/`。
- **考量**：提示词效果库与特定视频项目无关，属于全局创作者资产。避免项目切换导致样片重新跑测或丢失。
- **备选方案**：存储在工坊工程目录下。缺点：跨工程无法复用，项目体积膨胀。

### 2. 既有历史记录存储平滑兼容
- **选择**：保持底层存储目录 `tools/agnes_playground/turns/` 与 `PlaygroundStore` 历史文件路径不变，仅在前端展示层、窗口名、注册名做全面升级为「大模型试炼场」。
- **考量**：避免文件迁移导致用户已有的历史调用快照、脱敏请求体和产物索引失效。

### 3. 出厂内置资产与本地自愈合并策略
- **选择**：在 Flutter `assets/prompt_templates/builtin_templates.json` 打包出厂预置。首次启动或检测到出厂版本升级时，`PromptTemplateStore` 执行增量合并：追加新的内置模板，保留用户对既有模板的手工调整与实测样片（Benchmark）。
- **备选方案**：完全只读内置资产。缺点：无法记录针对特定模型的实测样张与评分。

### 4. 动态占位符解析规范
- **选择**：采用通用花括号标记，如 `{subject}`（主体）、`{action}`（动作）、`{environment}`（环境）。在 UI 渲染时自动以高亮 Chip/标签提示用户，载入时保留占位符以便快速定位修改。

## Architecture & Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     大模型试炼场 (Playground Page)               │
├───────────────────────────────┬─────────────────────────────────┤
│ 输入控制台 (Prompt & Media)   │ 提示词模板抽屉 (Template Drawer) │
│ - 提示词编辑框 (Prompt)       │ - 5大维度分类过滤               │
│ - 供应商与模型选择 (Provider) │ - 模板卡片瀑布流                │
│ - 参数吸附面板 (Ratio/Mode)   │ - 模型实测样片播放器 (Benchmark)│
│                               │ - 一键载入至控制台 [ Apply ]    │
└───────────────────────────────┴─────────────────────────────────┘
                                ▲
                                │ Stream / CRUD
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│               PromptTemplateStore (全局单例管理器)              │
├─────────────────────────────────────────────────────────────────┤
│ - assets/builtin_templates.json (出厂内置资产)                  │
│ - AppPaths.sharedPromptTemplatesDir (本地持久化 catalog.json)   │
│ - benchmarks/{template_id}/{model}.(jpg|mp4) (实测样张文件)     │
└─────────────────────────────────────────────────────────────────┘
```

## Risks / Trade-offs

- **[Risk] 视频样片占用过多本地存储空间**
  - → **Mitigation**: 限制样片仅在人工点击「设为标准样例」时才持久化保存（或仅存压缩后的 MP4/缩略图），并提供「清理无效样张」功能。
- **[Risk] 模板推荐参数与目标模型能力冲突**
  - → **Mitigation**: 模板中的推荐宽高比和时长仅作为期望值，在载入试炼场时统一交由 `MediaCapabilityResolver` 自动做边界约束与档位吸附。

## Migration Plan

1. 创建全局路径常量 `AppPaths.sharedPromptTemplatesDir`。
2. 引入 `VisualPromptTemplate` 及 `TemplateModelBenchmark` 模型。
3. 编排并放置出厂预置模板数据 `assets/prompt_templates/builtin_templates.json`，在 `pubspec.yaml` 中注册 asset。
4. 实现 `PromptTemplateStore` 单例，管理全局模板增删改查及自愈。
5. 升级 `lib/tools/registry.dart`、`lib/main.dart` 以及各引用处的名称为「大模型试炼场」。
6. 在试炼场主界面集成模板面板与交互按钮。
7. 执行 `./scripts/deploy_local.sh` 编译验证并更新本机应用。
