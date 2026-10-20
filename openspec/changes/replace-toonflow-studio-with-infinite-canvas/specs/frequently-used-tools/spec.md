## MODIFIED Requirements

### Requirement: Usage recorded for both embedded and separate-window tools
Opening a tool SHALL count toward its cumulative usage count regardless of whether the tool is embedded in the main window or opened in its own separate window.

The AI category SHALL contain the tools `ai-assistant`, `ai-video-studio`, `agnes-playground`, `infinite-canvas`, and `novel-manager`. The former `toonflow-studio` entry SHALL NOT appear in any category.

#### Scenario: Separate-window tool usage is recorded
- **WHEN** the user opens a tool that launches in its own window (for example the notebook, password vault, or ops tool)
- **THEN** that tool's usage count is incremented just as an embedded tool's would be, so it can appear in 常用软件.

#### Scenario: Private tools excluded from frequency ranking
- **WHEN** a private-category tool is opened while the privacy space is unlocked
- **THEN** it does not count toward 常用软件, since that surface is visible without unlocking the privacy space.

#### Scenario: Counts survive application restart
- **WHEN** the application restarts after tools have been opened
- **THEN** the accumulated usage counts are unchanged, so the ranking does not reset.

#### Scenario: AI 分类成员是替换后的集合
- **WHEN** 用户查看 AI 分类下的工具清单
- **THEN** 清单包含 `ai-assistant`、`ai-video-studio`、`agnes-playground`、`infinite-canvas`、`novel-manager`，且不含 `toonflow-studio`
