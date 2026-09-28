## ADDED Requirements

### Requirement: Resilient multi-format tool invocation parsing
The Agent execution loop SHALL parse and dispatch tool calls from model replies formatted in Markdown blocks, XML tags (`<tool_call>`), or raw JSON objects, correctly extracting tool names and normalizing diverse argument parameter names.

#### Scenario: XML tool call tags are parsed and executed
- **WHEN** an AI model outputs a tool call enclosed in `<tool_call>` and `</tool_call>` XML tags
- **THEN** the agent loop extracts the JSON payload, resolves the tool name and arguments, and executes the tool without leaking the XML tags to user-visible chat bubbles.

#### Scenario: Unclosed XML tool call tags are parsed and executed
- **WHEN** an AI model outputs an unclosed `<tool_call>` tag followed by a valid JSON object
- **THEN** the agent loop successfully identifies the tool call block and executes the tool.

#### Scenario: Markdown tool call blocks are parsed and executed
- **WHEN** an AI model outputs tool call JSON inside markdown fences (````tool_call```` or ````json````)
- **THEN** the agent loop parses the block and dispatches the tool call.

#### Scenario: Parameter aliases are normalized to arguments
- **WHEN** an AI model returns parameters under keys such as `"parameters"` or `"args"` instead of `"arguments"`
- **THEN** the parser normalizes these aliases into the standard arguments map passed to the tool executor.

#### Scenario: Reasoning think tags are stripped before parsing
- **WHEN** a reasoning model emits `<think>...</think>` thoughts before or around the tool call
- **THEN** the agent loop strips reasoning blocks so thoughts do not interfere with tool call extraction.
