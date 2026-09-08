# Proposal: MCP Stdio Environment Resolution and Diagnostic Error Reporting Fix

## Problem
When running the V8WorkToolbox macOS desktop application bundle (launched via Finder / LaunchServices), the app process inherits a minimal system `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`). 

1. **Missing Node / npx in PATH**: On macOS developer environments, Node.js and npx are commonly installed via NVM (`~/.nvm/versions/node/*/bin`), fnm, asdf, volta, bun, or Homebrew. The current `McpStdioSession.buildSanitizedEnv` only appends `/opt/homebrew/bin` and `/usr/local/bin`, but omits NVM and other version managers.
2. **Launch Failure**: When executing `npx -y firecrawl-mcp`, the subshell fails with `/bin/sh: npx: command not found` (exit code 127). Furthermore, even if the absolute path to `npx` were specified, `npx` relies on `#!/usr/bin/env node`, which fails because `node` is absent from `PATH`.
3. **Obscured Diagnostics**: When the MCP child process terminates abnormally, stderr output is currently only output via `debugPrint` and discarded; the UI receives a generic `Exception: MCP 进程已中断` without displaying the exit code or stderr output, preventing users from understanding why the connection failed.

## Proposed Solution
1. **Intelligent Shell & PATH Auto-Discovery**:
   - In `McpStdioSession.buildSanitizedEnv`, add macOS login shell PATH discovery (`/bin/zsh -l -c 'echo -n "$PATH"'`) with in-memory caching to instantly capture the user's complete dev environment.
   - Add filesystem heuristic scanning for common Node.js version manager paths (`~/.nvm/versions/node/*/bin`, `~/.fnm/current/bin`, `~/.asdf/shims`, `~/.volta/bin`, `~/.bun/bin`, `~/.local/bin`, `~/.cargo/bin`) as proactive fallbacks.
   - If `endpointOrCommand` is a relative tool name like `npx` or `node`, search the resolved `PATH` and expand to its absolute executable path if available.
2. **Process Stderr Retention and Granular Error Reporting**:
   - In `McpStdioSession`, maintain a rolling ring buffer of recent stderr lines (up to 20 lines).
   - When the process terminates with a non-zero exit code or fails during initialization / requests, surface the exit code and exact stderr lines in the thrown Exception (e.g. `MCP 进程异常退出 (code: 127): /bin/sh: npx: command not found`).
   - Show this detailed message directly in the UI SnackBar / alert so the user can easily pinpoint any missing dependencies or network configuration issues.
3. **Validation & Verification**:
   - Unit tests covering `buildSanitizedEnv` with NVM paths and shell fallback.
   - Real connection test confirming Firecrawl MCP handshake and discovery of all 27 tools.
