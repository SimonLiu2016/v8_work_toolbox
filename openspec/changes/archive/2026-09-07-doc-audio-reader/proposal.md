# Proposal: Document & Web AI Audio Reader (文档与网页 AI 语音朗读助手)

## Why

知识工作者和开发者经常需要阅读大量的技术文档、电子书（PDF/EPUB/DOCX）以及长篇网络文章。长时间盯屏容易造成视力疲劳，且在通勤、散步或多任务工作场景下难以继续获取信息。
通过为 V8WorkToolbox 增加内置的“文档与网页 AI 语音朗读助手 (Doc Audio Reader)”，将多格式文档与网页正文通过智能切片和多模态 AI 语音合成（TTS）实时转为高品质语音，并配备“卡拉OK式”双向同步播放器和 MP3 离线导出功能，使用户能够随时“用耳朵听文档”，极大解放双眼、提升阅读效率。

## What Changes

- **新增多格式文档与网页正文解析引擎**：
  - 本地文件：支持 .pdf、.docx、.txt、.md、.epub 格式的内容抽取与段落清洗。
  - 网络文章：支持输入 URL，自动拉取网页 HTML 并过滤导航栏/广告/页脚，提取纯净正文。
  - 智能切片分段：按自然段与标点符号自适应分块，实现低首字延迟（TTFB）与滑动窗口并发合成。
- **构建三模态可配置 TTS 语音合成矩阵**：
  - **模式 1 (Edge-TTS 免费神经网络语音)**：免 API Key，内置微软高品质音色（晓晓、云希、云健等），开箱即用。
  - **模式 2 (商业/自定义 OpenAI 兼容 TTS)**：对接标准 POST /v1/audio/speech 协议，可在设置中自由绑定 MiniMax、OpenAI、SenseTime 等商用模型与音色。
  - **模式 3 (macOS 原生离线语音兜底)**：调用系统级 AVSpeechSynthesizer / say，在完全离线无网状态下保证 100% 可用。
- **新增内置双向同步播放器与阅读界面**：
  - 全功能播放控制：播放/暂停、前后快进、0.5x ~ 2.5x 灵活变速、声音与音色即时切换。
  - 沉浸式阅读视图：当前朗读段落聚光灯高亮，平滑自动滚动居中，支持点击任意段落跳播。
  - 章节目录导航：针对 EPUB 或长篇文档生成章节导航树。
- **新增完整音频导出 (MP3/M4A Export)**：
  - 支持将整篇或所选章节一键合并导出为 MP3 音频文件，方便同步到手机或车载播放器离线收听。
- **集成到工具箱主壳与侧边栏注册表**：
  - 在 lib/tools/registry.dart 注册 doc-audio-reader 工具卡片与侧边导航图标。

## Capabilities

### New Capabilities
- `doc-audio-reader`: 涵盖多格式文档/网页解析提取、三模态 TTS 语音合成管线、双向同步播放器界面以及离线 MP3 导出功能。

### Modified Capabilities

## Impact

- **UI / Shell**:
  - 在 lib/tools/registry.dart 新增工具注册项 doc-audio-reader。
  - 在 lib/tools/reader/ 下新增完整页面与组件实现。
- **依赖扩展 (pubspec.yaml)**:
  - 新增音频播放支持库 audioplayers: ^6.0.0。
  - 利用已有的 archive、xml、http 库处理 DOCX/EPUB 与网页提取。
- **存储与缓存**:
  - 在 ~/.v8worktoolbox/audio_cache/ 建立临时音频分块缓存，避免重复请求。
