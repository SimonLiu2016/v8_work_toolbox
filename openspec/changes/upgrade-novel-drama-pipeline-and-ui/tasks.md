## 1. 弹窗交互重构与后台异步流式拉取

- [x] 1.1 在 `lib/tools/ai_video_studio/ui/novel_selector_dialog.dart` 中内联集成导入范围选择（单集扩写 vs 全季解构，目标集号输入），移除原有点击确认时的模态全屏加载圈
- [x] 1.2 重构 `_confirmSelection`，确认后立即关闭弹窗并返回包含轻量元数据与选择范围的 `NovelSelectionResult`，彻底消除二次范围确认弹窗
- [x] 1.3 改造 `novel_import_task_service.dart` 的 `submit` 与 `_run` 方法，支持传入章节索引并在后台按需异步流式加载文本，保障主线程 UI 保持 60fps 流畅

## 2. 流水线阶段与实时装配状态模型扩展

- [x] 2.1 在 `novel_import_task_service.dart` 中定义流水线 6 大阶段枚举 `PipelineStage`（文本切片、资产抽取、场次节拍、契约事实、五维拆镜、门禁质检）与状态推进机制
- [x] 2.2 扩展 `NovelImportTask` 数据模型，新增实时装配状态字段（`discoveredCharacters`、`discoveredScenes`、`discoveredProps`、`protectedUtteranceCount`、`liveLogs` 滚动日志流）
- [x] 2.3 在 `AiConstraintEngine` 执行各环节时通过回调或服务通知，向活跃任务实时灌注已发现资产与执行命令日志

## 3. 创意孵化看板流水线动态可视化升级

- [x] 3.1 在 `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart` 中用全新的 `_PipelineWorkflowCard` 替换简陋的单行转圈卡片
- [x] 3.2 实现 6 个核心阶段节点的横向时间轴，包含动态脉冲运行态指示、耗时统计与完成绿勾
- [x] 3.3 实现动态装配卡槽（Live Asset Slots），将解构出的角色卡、场景卡、道具卡及受保护台词即时以芯片徽章形式展现
- [x] 3.4 实现终端式实时动作日志流控制台（Live Action Stream Console），支持折叠与自动滚动

## 4. 两段式时序演变与音画分流编译器增强

- [x] 4.1 在 `lib/tools/ai_video_studio/services/prompt_assembler.dart` 中升级 `PhotorealisticPromptCompiler`，支持前半段机位/初始动势与后半段特写/反转演变的两段式时序编译
- [x] 4.2 确立并落地音画分流规则：在提示词中剥离开口台词，将对白明确标定为画外后期配音，将境界突破等数据标定为系统浮字特效，从提示词源头杜绝视频乱码
- [x] 4.3 在分镜看板卡片展开视图中直观呈现两段式提示词预览与音频分流标签

## 5. 原生批量出片与时间轴剪辑闭环

- [x] 5.1 在 `StoryboardBoard` 与 `DeliveryPanel` 中打通首帧批量生成与图生视频任务队列，实现应用内自动化出帧出片
- [x] 5.2 完善剪映导出中的前后剪辑手柄（Handles）与音轨微秒对齐

## 6. 构建验证与本地部署

- [x] 6.1 运行单元测试（`flutter test test/...`）与代码静态分析（`dart analyze`），确保 0 错误
- [x] 6.2 执行 `./scripts/deploy_local.sh` 编译 Release、签名、验证 AOT md5 并替换本机应用启动
