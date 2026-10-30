## ADDED Requirements

### Requirement: 实时会议翻译工具的归类

实时会议翻译工具 SHALL 归类于"笔记与学习"（`ToolCategory.note`）分类，MUST NOT 归类于"AI 与资讯"（`ToolCategory.ai`）。

**理由**：该工具处理的是用户自己的会议音频转录（用户自己产出的文字），符合 note 分类"组织用户自己产出的文字"的语义；它虽用 AI 能力，但"带 AI 能力不改变归属"。

#### Scenario: 侧边栏中的位置

- **WHEN** 用户查看侧边栏分类
- **THEN** "实时会议翻译"出现在"笔记与学习"分组下，不在"AI 与资讯"分组下
