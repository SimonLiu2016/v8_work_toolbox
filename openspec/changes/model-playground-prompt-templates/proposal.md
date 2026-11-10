# Proposal: 大模型试炼场重命名与提示词模板效果库 (第一阶段)

## Why

当前“Agnes 试炼场”底层已天然支持多供应商与多通道模型，原命名限制了多模型实验与对比的认知；同时在图像与视频生成中，缺乏具备直观视觉样例与技巧维度的提示词库，导致用户无法快速准确描述复杂的镜头运镜、多人打斗交互、粒子光效与特定画风。此外，不同模型对提示词语法和敏感度差异极大，亟需一套具备“多维度预置 + 模型特异性样张验证 + 人工打分筛选”的视觉提示词模板体系。

## What Changes

- **试炼场品牌与入口全面升级**：将“Agnes 试炼场”升级重命名为“大模型试炼场”，更新主工具箱注册入口、主程序多窗口子进程标题、工坊跳转按钮文案及路由描述。
- **提示词效果库 (Prompt Template Library) 核心底座**：
  - 构建涵盖 5 大体系、16 个主流视觉细分维度的出厂内置提示词模板（包含镜头运镜、武打动作、多人交互防串脸、物理粒子、光影氛围、艺术风格）。
  - 支持参数化占位符（如 `{subject}`, `{action}`, `{environment}`）与模型推荐参数（宽高比、时长、模式、特定负向避雷词）。
  - 支持持久化存储至应用全局共享目录（`~/Library/Application Support/V8WorkToolbox/prompt_templates/`），实现跨项目共享。
- **模型特异性评测与样片管理 (Model Benchmark Samples)**：
  - 数据模型支持记录特定模型、特定版本下的实测样张/样片（支持本地图片与视频播放）。
  - 支持人工 1~5 星打分评级、是否推荐标记、实测 Prompt 还原。
- **试炼场内效果库面板与对决模式原型**：
  - 在大模型试炼场内新增「提示词效果库」抽屉/浏览面板，支持按维度、标签、通道、模型过滤。
  - 支持一键将模板内容与推荐参数回填至试炼场输入控制台调试。
  - 支持“多模型对决”能力架构定义（同一提示词向 2~3 个模型分发评测对比）。

## Capabilities

### New Capabilities
- `prompt-template-library`: 图像与视频提示词模板库，提供结构化视觉维度分类（镜头/动态/特效/光影/风格）、参数占位符、模型特异性样片与打分评级、全局数据持久化管理。

### Modified Capabilities
- `agnes-playground`: 升级为“大模型试炼场”，更新全套文案与入口，集成提示词效果库抽屉面板，支持从模板一键载入与样片评测关联。

## Impact

- **UI / 界面**：
  - `lib/tools/agnes_playground/ui/playground_page.dart`：标题升级、新增提示词模板面板/抽屉、多模型并排对比支持扩展。
  - `lib/tools/registry.dart`：工具标题由 `Agnes 试炼场` 变更升级为 `大模型试炼场`，描述对齐多模型试炼定位。
  - `lib/main.dart`：子窗口 `Agnes 试炼场` 标题对齐升级。
  - `lib/tools/ai_video_studio/`：分镜看板与设置面板中跳转试炼场的按钮及引导文案对齐。
- **服务与存储**：
  - 新增 `lib/services/app_paths.dart` 全局路径 `sharedPromptTemplatesDir` 及 `catalog.json` / `benchmarks/` 存储。
  - 新增 `PromptTemplateStore` 单例，管理内置模板出厂加载、用户自建、模型样片索引与更新流。
- **资源文件**：
  - 引入出厂内置提示词资产预设包（`assets/prompt_templates/builtin_templates.json`）。
