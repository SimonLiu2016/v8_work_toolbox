## Context

本方案基于探索阶段用户选定的**款式 2（流线莫比乌斯极客款）**，参考 Visual Studio Code 的一笔画折纸丝带美学与经典电光蓝配色，重构从 macOS Dock 图标、菜单栏托盘到 Flutter 主界面的全套视觉体系。

## Goals / Non-Goals

**Goals:**
- **AppIcon 全分辨率覆盖**：生成标准的 16x16 至 1024x1024 macOS 规范图标，严格施加 22.4% Squircle 透明大圆角，杜绝直角黑边。
- **TrayIcon 极简模板化**：基于款式 2 的流线轮廓，提取清晰的 18x18@1x 与 36x36@2x 纯黑 Template 图标，确保深浅色模式自动反色且不失真。
- **Flutter 端品牌呈现**：将高质量资源注入 `assets/images/app_logo.png`，保持 ActivityBar 与偏好设置弹窗清晰精美。
- **闭环打包同步**：编译 Release 安装包并同步至 `/Applications/V8WorkToolbox.app`，验证 Window Server 层级与 Dock 显示。

**Non-Goals:**
- 不修改已经稳定运行的 Cocoa 托盘右键菜单和全局热键响应逻辑。
- 不更改既有的窗口生命周期与后台常驻机制。

## Decisions

### 1. 源图提取与 Squircle 构图裁切
- **决策**：从源图 `v8_ribbon_origami_1788757366495.jpg` 中提取核心流线折带主体，剥离背景微网格，并在透明 Squircle 画布上留出符合 macOS HIG 规范的呼吸间距（约 8%~10% padding）。
- **备选**：直接使用满画幅正方形。弊端是边缘在 Dock 中会被直角剪切或产生毛刺。

### 2. 托盘图标矢量负空间二值化
- **决策**：利用 Python 图像处理脚本，对丝带的主体进行边缘提取与内环负空间保留，生成 18x18 及 36x36 的单色 Template PNG。
- **备选**：直接将彩色图标压缩至 18x18。弊端是彩色在 macOS 状态栏深浅色切换时会产生色污且辨识度低。

### 3. Flutter 端品牌与原生资源统一
- **决策**：`assets/images/app_logo.png` 采用 512x512 高清带微立体的透明 Squircle 图标，既能在 ActivityBar（28~32px）保持锐利，又能在“关于”弹窗（80px）展现丰富的折面细节。

## Risks / Trade-offs

- **[风险] 18x18 托盘尺寸细节丢失** → **缓解方案**：在生成 18x18 图标时做专门的二值形态学膨胀与内环加宽，确保小尺寸下“V”字与“8”字双环清晰透光。
- **[风险] macOS 系统图标缓存残留** → **缓解方案**：部署后自动执行 `touch /Applications/V8WorkToolbox.app` 并重启 Dock 进程。
