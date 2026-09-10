## Why

用户在导入印象笔记导出文件（如 `/Users/simon/Desktop/我的笔记.notes`）时，遇到了两个阻断性问题：
1. 导出的 `.notes` / `.enex` XML 中各笔记并无 `<notebook>` 标签，导致笔记本未能迁移创建，所有笔记沦为“未归类”。
2. 印象笔记（中国版）导出的 `.notes` 文件中的正文被官方私有算法加密为 `base64:aes`（`ENC0` 前缀），全网无离线解密公开密钥，导致导入的正文全部为占位提示文本。
经探测，用户本机已经安装并登录了「印象笔记 Mac 客户端」，其本地 SQLite 数据库与缓存目录（`~/Library/Containers/com.yinxiang.Mac/...`）完整保留了未经加密的 40+ 个分类笔记本、320+ 篇完整正文（ENML / HTML）及原始附件。亟需支持从本机客户端一键全量迁移，并增强文件导入自动按文件名建本及关联本地明文还原。

## What Changes

- **本机客户端一键全量导入**：新增自动探测并直接读取本机「印象笔记」客户端 SQLite 数据库（`LocalNoteStore.sqlite`）与内容目录（`content/<UUID>/content.enml`）的能力，一键免密离线迁移所有笔记本分类、正文、标签与附件。
- **文件导入笔记本自动命名与归类**：针对用户手动导入 `.notes` / `.enex` 单文件场景，自动以文件名（如 `我的笔记.notes` ➔ `我的笔记`）作为所属笔记本，自动创建对应笔记本并将笔记归类其中。
- **文件导入本地明文关联补全**：若导入的 `.notes` 含有 `base64:aes` 加密正文，自动根据笔记标题和时间戳在本机印象笔记本地数据库中进行关联匹配；匹配成功则无缝拉取本地未加密的 ENML/HTML 正文与附件，彻底解决加密占位符问题。
- **导入交互界面升级**：在笔记列表/工具栏弹窗中增加“从本机印象笔记一键迁移”显著入口，并展示检测到的本地账号、笔记本数与笔记总数，迁移过程展示精确进度。

## Capabilities

### New Capabilities
- `notebook-evernote-migration`: 支持从本机印象笔记客户端数据库一键全量离线迁移（分类、正文、标签、附件）及文件导入智能关联明文与自动归类。

## Impact

- 影响模块：`lib/tools/notebook/evernote_import_service.dart`、`scripts/evernote_import.py`、`lib/tools/notebook/ui/notebook_page.dart`。
- 外部依赖：利用 Python `sqlite3`、`xml.etree` 及 `html2text` 实现本地数据提取与 ENML ➔ Markdown 转换，无需第三方新依赖，零网络开销。
