## 1. 底层水合与服务增强：跨重启还原任务记录

- [x] 1.1 `lib/tools/ai_video_studio/services/novel_import_task_service.dart`：实现 `hydrateFromLedger()`，从 `VideoTaskLedger` 自动加载 `adapterId == 'novel-import'` 的所有条目，水合还原至 `_tasks` 列表，并将残留未完成项转换为中断态并记录原因。
- [x] 1.2 `lib/tools/ai_video_studio/ui/studio_shell.dart`：在 `_bootstrap` 启动流程中调用 `hydrateFromLedger()`，确保打开或重开工坊时历史与最近任务立即可见。
- [x] 1.3 `test/tools/ai_video_studio/`：补充单元测试验证任务持久化与水合还原（包含完成态与中断态的恢复验证）。

## 2. 顶栏任务中心常驻与抽屉全景升级

- [x] 2.1 `lib/tools/ai_video_studio/ui/studio_shell.dart`：重构顶栏任务入口为常驻按钮 `NovelTaskCenterButton`，移除 `count == 0` 时隐藏的限制；支持根据状态显示空闲图标、运行中微动角标及中断提示。
- [x] 2.2 `lib/tools/ai_video_studio/ui/novel_task_drawer.dart`：升级任务管理抽屉，增加「全部 / 进行中 / 已完成 / 已中断」分类标签页，显示任务详细耗时、所属剧集、模式与产物统计。
- [x] 2.3 `lib/tools/ai_video_studio/ui/novel_task_drawer.dart`：实现动作闭环，为已完成任务提供【定位剧集查看产物】跳转，为中断/失败任务提供【重试】，并提供【清理历史记录】功能。

## 3. 创意孵化面板常驻任务态与产物卡片

- [x] 3.1 `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`：重构任务查找逻辑，自动匹配当前选中剧集的正在执行或最近完成/中断任务。
- [x] 3.2 `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`：实现已完成状态的产物概览卡片（展示已生成的集数、角色数、场景数统计，提供「前往 IP 主库」与「重新导入」）。
- [x] 3.3 `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`：实现中断/失败状态的告警卡片（展示中断原因与「一键重试」按钮）。

## 4. 窗口关闭拦截保护

- [x] 4.1 `lib/tools/ai_video_studio/ui/studio_shell.dart`：注册 `WindowListener` 监听窗口关闭事件 `onWindowClose()`。
- [x] 4.2 当存在正在运行的小说导入长任务时，拦截直接退出并弹出二次确认对话框，防止用户误触关闭导致长文 AI 请求中断。

## 5. 质量验证与部署

- [x] 5.1 运行 `flutter analyze` 与 `flutter test`，修复潜在类型与未定义错误。
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 编译并热替换本机应用。
