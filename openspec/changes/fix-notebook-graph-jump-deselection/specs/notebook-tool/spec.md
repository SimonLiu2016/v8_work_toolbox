# notebook-tool Delta

## ADDED Requirements

### Requirement: Cross-View Note Navigation and Selection Persistence
When a user navigates to a note from external panels (such as clicking a node in the knowledge graph or a citation in the AI assistant), the notebook tool SHALL synchronously switch sidebar navigation to the target note's notebook context and maintain steady editor selection without deselection flicker.

#### Scenario: Jumping from knowledge graph node to note in another notebook
- **WHEN** the user clicks a note node in the knowledge graph that belongs to a notebook different from the currently selected notebook
- **THEN** the sidebar updates its active notebook selection to match the target note's notebook, loads the target notebook's note list, and highlights and opens the target note in the main editor.

#### Scenario: Jumping from knowledge graph node to standalone note
- **WHEN** the user clicks a note node in the knowledge graph that does not belong to any notebook
- **THEN** the sidebar updates its active selection to "全部笔记" (all notes), refreshes the list to include the target note, and keeps the target note stably selected in the editor.

#### Scenario: Clearing conflicting search or tag filter on cross-view jump
- **WHEN** the user initiates a jump from the knowledge graph while an active search query or tag filter is applied
- **THEN** the system clears the active search query and tag filter so the target note is not excluded from the refreshed note list and is not reset to an empty state.
