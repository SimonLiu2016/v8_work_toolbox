## Why

When users delete all external MCP client configurations in the "外部MCP客户端" (External MCP Clients) tab, the change is saved to `ai_config.json` with `"mcpServers": []`. However, upon restarting the application, `AiConfigStore._load()` treats an empty list `_mcpClients.isEmpty` as a fresh installation and unconditionally re-injects the Firecrawl preset (`McpClientConfig.firecrawlPreset()`) and writes it back to disk. As a result, deleting MCP clients does not persist across application restarts.

## What Changes

- In `AiConfigStore._load()`, distinguish between "fresh installation / missing key" and "user-cleared empty list":
  - Only inject the default `McpClientConfig.firecrawlPreset()` if `ai_config.json` does not exist OR if the JSON payload is completely missing the `mcpServers` field (for backwards compatibility migration).
  - If `json.containsKey('mcpServers')` is present (even if it is an empty list `[]`), respect the user's deletion and leave `_mcpClients` empty without re-adding or auto-saving presets.
- Add unit tests verifying that deleting all MCP clients and reloading from disk maintains an empty list.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `ai-configuration`: Preserve user deletion of external MCP clients across application restarts.

## Impact

- `lib/services/ai_config_store.dart`: `_load()` method logic for `mcpServers`.
- `test/mcp_assistant_test.dart` or a new/dedicated `ai_config_store_test.dart`: tests verifying persistence of MCP client deletion.
