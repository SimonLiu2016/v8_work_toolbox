## Context

参见 `proposal.md` 与 `specs/notebook-tool/spec.md`。
当前笔记中内嵌图片与原文档附件均以 `type: 'attachment'` 渲染在 AppFlowyEditor 中。

## Goals / Non-Goals

**Goals:**
- 在附件块卡片中提供直观安全的删除入口，从编辑器节点和数据库存储两层级联清理。
- 转换成功后，自动在原附件节点下方插入新附件节点，实现笔记内容闭环。
- 转换对话框展示完整产物信息与直接打开/访达定位入口，消除用户认知割裂。

**Non-Goals:**
- 不改变 AppFlowyEditor 本身的 block selection 或键盘事件底层处理机制。
- 不引入外部文件管理系统。

## Decisions

### 1. 附件卡片删除流程（双层清理）
- **Decision**: 点击附件操作栏的「删除」按钮，弹出二次确认弹窗。确认后：
  1. 通过 `context.read<EditorState>()` 执行事务：`transaction.deleteNode(widget.node)`；
  2. 调用 `NoteStore.instance.deleteAttachment(attId)`，删除磁盘上的物理文件和 SQLite `attachments` 表中的记录。
- **Rationale**: 仅删节点会产生孤儿附件文件；仅删文件会导致编辑器正文残存无法解析的坏节点。两层事务级联确保数据一致性。

### 2. 转换产物自动向 EditorState 插入新 Block 节点
- **Decision**: 将 `ConvertDialog` 与调用方所在节点的上下文连通（通过可选回调 `void Function(Attachment newAttachment)`），转换成功后调用：
  ```dart
  final newNode = attachmentNode(
    attachmentId: newAtt.id,
    filename: newAtt.filename,
    sizeBytes: newAtt.sizeBytes,
    mime: newAtt.mime,
  );
  editorState.transaction.insertNode(node.path.next, newNode);
  ```
- **Rationale**: 用户在当前笔记发起转换，天然期望看到转换生成的文件出现在原文件附近。

### 3. 对话框成功界面展示与文件操作
- **Decision**: 转换完成后不立即静默 `pop`，而是将对话框切换为「完成状态」：
  - 显示生成的文件名、文件大小与磁盘完整路径；
  - 提供两个直观按钮：`在访达中显示`（`open -R <path>`）与 `打开文件`（`open <path>`）；
  - 点击「完成」或关闭才退出弹窗。
- **Rationale**: 满足用户直接使用生成文件的诉求，无需手动去深层数据目录搜寻。

## Risks / Trade-offs

- **[Risk] 删除节点时如果处于未保存状态，数据库与编辑器是否冲突**：
  → *Mitigation*: 笔记正文基于 Delta/Json 响应式保存，删除节点会即时触发 `Document` 更新回调；`NoteStore.deleteAttachment` 通过主键删除且不阻碍正文保存。
