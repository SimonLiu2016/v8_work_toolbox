# Tasks: MCP Stdio Environment Resolution and Error Reporting

## Implementation Tasks

- [x] 1. Enhance `McpStdioSession` environment discovery and path resolution
  - [x] 1.1 Implement login shell PATH discovery and heuristic multi-manager folder scanner (`nvm`, `asdf`, `fnm`, `volta`, `bun`, `brew`) in `buildSanitizedEnv`
  - [x] 1.2 Implement `resolveExecutable` helper to resolve relative command names (`npx`, `node`) against the expanded PATH
  - [x] 1.3 Add rolling stderr buffer (last 20 lines) and capture process exit codes in `McpStdioSession`
  - [x] 1.4 Propagate detailed stderr and exit code information through `_cleanup` and `testConnection`
- [x] 2. Add comprehensive automated tests
  - [x] 2.1 Update `test/mcp_assistant_test.dart` to verify PATH expansion and NVM detection
  - [x] 2.2 Add unit test verifying stderr message capturing when an MCP process fails or exits prematurely
- [x] 3. Build, deploy, and verify
  - [x] 3.1 Run `flutter test` across all MCP test suites
  - [x] 3.2 Build macOS release binary and redeploy to `/Applications/V8WorkToolbox.app`
  - [x] 3.3 Verify MCP test connection functionality in the running desktop app
