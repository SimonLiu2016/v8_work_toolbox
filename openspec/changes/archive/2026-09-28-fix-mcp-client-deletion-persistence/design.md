## Context

See `proposal.md` for background.
In `lib/services/ai_config_store.dart`:
```dart
final mcps = (json['mcpServers'] as List<dynamic>?) ?? [];
_mcpClients = mcps
    .map((e) => McpClientConfig.fromJson(e as Map<String, dynamic>))
    .toList();
if (_mcpClients.isEmpty) {
  _mcpClients.add(McpClientConfig.firecrawlPreset());
  await _save();
}
```
This causes an empty `mcpServers` list (which occurs when the user deliberately deletes all MCP entries) to be treated as an uninitialized state, re-adding `McpClientConfig.firecrawlPreset()` and writing it back to disk on every application startup.

## Goals / Non-Goals

**Goals:**
- Differentiate between "missing `mcpServers` field in legacy json" (which requires adding the default preset) and "explicit empty list `mcpServers: []`" (which should remain empty).
- Ensure `deleteMcpClient` permanently persists deletions across app restarts.
- Ensure fresh installations (`_initDefaults`) still include the Firecrawl preset out of the box.

**Non-Goals:**
- Altering the UI layout or preset configuration parameters.
- Changing MCP server execution, handshake, or tool list logic.

## Decisions

### Decision: Check `json.containsKey('mcpServers')`
- **Choice**:
  ```dart
  if (json.containsKey('mcpServers')) {
    final mcps = (json['mcpServers'] as List<dynamic>?) ?? [];
    _mcpClients = mcps
        .map((e) => McpClientConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  } else {
    // 兼容升级：此前版本配置中没有 mcpServers 字段，补充预置
    _mcpClients = [McpClientConfig.firecrawlPreset()];
    await _save();
  }
  ```
- **Rationale**: If `mcpServers` key exists in JSON, the list content (whether empty or populated) represents the user's explicit saved state. If the key is missing entirely, it means an older version of `ai_config.json` was loaded, so we migrate by adding the default preset.
- **Alternative considered**: Adding a dedicated boolean flag `hasClearedPresets`. Rejected as redundant; `json.containsKey('mcpServers')` directly maps to whether the field has been established.

## Risks / Trade-offs

- None identified; backwards compatibility with old configuration files without `mcpServers` is fully preserved.
