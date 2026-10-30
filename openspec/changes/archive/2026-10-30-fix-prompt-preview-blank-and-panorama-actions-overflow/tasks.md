## 1. 修复 Prompt 预览弹窗渲染崩溃

- [x] 1.1 在 `AssetPromptPreviewDialog` 的 `actions` 中移除直属于 `OverflowBar` 的 `Spacer()`，使用 `SizedBox(width: double.infinity, child: Row(...))` 包裹操作按钮，消除 `_OverflowBarParentData` 异常
- [x] 1.2 编写或更新 Widget 测试用例，断言 `AssetPromptPreviewDialog` 弹出后正常渲染且无未捕获异常

## 2. 净化全景母图与切片操作按钮视觉与文案

- [x] 2.1 修改 `series_page.dart` 中“生成 360° 全景母图”按钮：移除 `Icon(Icons.auto_awesome)` 与 Emoji `✨`，去除 `(1次API)`，精简文案为 `生成全景母图`
- [x] 2.2 修改 `series_page.dart` 中“一键无损切片”按钮：移除 `Icon(Icons.crop_free)` 与 Emoji `🔄`，精简文案为 `一键切片`

## 3. 重构操作栏响应式排版根除横向溢出

- [x] 3.1 将冗长的切片说明文本 `（1次文生母图 · 本地毫秒级无损切片正/反/侧机位 · 彻底根除反打雷同）` 从单行 Row 抽离，转为标题下方独立的辅助提示行
- [x] 3.2 对右侧按钮组采用自适应弹性或紧凑布局，确保在不同窗口宽度下绝不溢出窗口边界

## 4. 验证与工程部署

- [x] 4.1 运行单元与 Widget 测试套件确保全部 PASS
- [x] 4.2 执行 `./scripts/deploy_local.sh` 完成 Release 构建与本地应用部署
