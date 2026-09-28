## 1. Storage Logic Fix

- [x] 1.1 Update `AiConfigStore._load()` to check `json.containsKey('mcpServers')` rather than checking `_mcpClients.isEmpty`
- [x] 1.2 Ensure default preset is only injected when `mcpServers` key is entirely absent or on fresh defaults initialization

## 2. Testing and Verification

- [x] 2.1 Add unit tests in `test/ai_config_store_mcp_test.dart` to verify that deleting all MCP clients persists after re-loading config from disk
- [x] 2.2 Verify that fresh initializations without `mcpServers` still get the Firecrawl preset
