## MODIFIED Requirements

### Requirement: Storyboard card and thumbnail null-safe rendering
The storyboard board and thumbnail widgets SHALL cache media file references in local immutable variables during render passes, and SHALL NOT execute unchecked null assertion operator (`!`) on dynamically evaluated file getters.

#### Scenario: Keyframe generation completion and thumbnail update
- **WHEN** keyframe generation completes and triggers state reload on the storyboard board
- **THEN** thumbnail and card widgets render the newly saved frame image without throwing `Null check operator used on a null value`

## ADDED Requirements

### Requirement: Worldview tab edit persistence on tab switch
The worldview tab editor SHALL immediately flush any pending debounced changes to disk when the tab is disposed or when text fields lose focus, preventing pasted or typed content from being lost when switching between tabs.

#### Scenario: User pastes worldview content and immediately clicks another tab
- **WHEN** user pastes text into the Worldview text field and clicks the "角色卡" or "场景库" tab within 600ms
- **THEN** system saves the new worldview text immediately before disposing the tab, and reloading the tab displays the saved content

### Requirement: Novel import scope selection
The novel import flow SHALL prompt the user to choose between "Full Novel Deconstruction" (全案解构) and "Single Chapter / Episode Continuation" (单集/章节扩写), allowing users to target an existing episode or append as a new episode without destroying the rest of the series.

#### Scenario: User imports text under single episode continuation mode
- **WHEN** user selects a novel text file in Idea Incubator
- **THEN** system opens a scope dialog where the user can confirm whether this is full novel text or single chapter text, and select the target episode index
- **AND** executing chapter import updates the designated episode synopsis without deleting existing episodes

### Requirement: Incremental IP asset upsert
The project manager SHALL merge newly extracted characters, scenes, and worldview notes non-destructively: matching characters by name to preserve existing custom visual prompts, deduplicating scenes by name, and appending new worldview facts.

#### Scenario: Adding a novel chapter with new and existing characters
- **WHEN** a chapter containing existing character "林长生" and new character "杨德厚" is imported
- **THEN** system retains "林长生" without overwriting custom prompt anchors, and creates a new character card for "杨德厚"
