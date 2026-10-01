## 1. 删掉多余的 show()

- [x] 1.1 `lib/tools/lookup_panel/ui/lookup_window.dart` 的 `LookupWindowLauncher.open()`：删掉 `await controller.show()`，并在原处注释说明为什么不能留 —— 包的 `window_show` 会 `NSApp.activate(ignoringOtherApps: true)`，把主窗口一起带到前台；而 `CreateWindow` 在 `hiddenAtLaunch: false` 时已经 `orderFront` + `setIsVisible`，这行是多余的（连带 `controller` 局部变量也没用了，一并去掉）

- [x] 1.2 只改这一处。其余四个子窗口（registry.dart 三处 + notebook_page.dart 一处）保持调 `show()` —— 它们激活 App 是用户点"打开笔记本"的预期结果，本 change 不该顺手改掉

## 2. 测试与验证

- [ ] 2.1 运行 `flutter analyze` 与全量测试，确认零回归（失败集合与改动前逐字相同）
- [ ] 2.2 实机：桌面应用在后台 → 浏览器中「问 AI 深度解析」→ 浮窗出现、**主窗口不弹出**、Chrome 不失焦点
- [ ] 2.3 实机：同一条路点「在桌面端打开」→ 同样不激活 App
- [ ] 2.4 实机：`⌘D` 热键查词 → 浮窗正常出现、跟随光标（确认删 show() 没弄坏热键路径）
- [ ] 2.5 实机：浮窗失焦后仍会自动关闭（`onWindowBlur` 是窗口级的，理论上不受影响，但要验——关不掉的浮窗比激活 App 更烦）
- [ ] 2.6 实机：打开笔记本/密码/运维子窗口 → 仍然激活 App（确认没顺手改坏）

## 3. 部署

- [ ] 3.1 运行 `./scripts/deploy_local.sh` 并重新启动应用
- [ ] 3.2 核对新构建 AOT 快照已变化、strict 签名校验通过
- [ ] 3.3 浏览器侧需重载扩展（若 extensions/ 有改动）
