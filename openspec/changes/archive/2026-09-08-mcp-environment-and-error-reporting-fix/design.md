# Design: MCP Stdio Environment Resolution and Error Reporting

## Context
When running on macOS as a `.app` bundle, applications launched through LaunchServices have an isolated, restricted `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`). CLI tools like `node`, `npm`, `npx`, `python3`, etc. installed via NVM or user directories are not accessible unless explicitly discovered.

## Architectural Changes

### 1. Robust PATH Discovery (`McpStdioSession.buildSanitizedEnv`)
- Maintain a static memoized `_cachedSystemPath` in `McpStdioSession`.
- If `Platform.isMacOS` or `Platform.isLinux` and `_cachedSystemPath` is not yet computed:
  1. Attempt to run `Process.runSync('/bin/zsh', ['-l', '-c', 'echo -n "\$PATH"'])` (or `$SHELL` if present), with a short timeout.
  2. If that fails or produces an empty string, fallback to directory probing:
     - Scan `~/.nvm/versions/node/` for installed Node versions (sort descending to pick newest version, add its `/bin`).
     - Probe `~/.fnm/current/bin`, `~/.asdf/shims`, `~/.asdf/bin`, `~/.volta/bin`, `~/.bun/bin`, `~/.cargo/bin`, `~/.local/bin`, `~/bin`.
     - Probe `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/homebrew/sbin`, `/usr/local/sbin`.
  3. Deduplicate and validate existing directories.
  4. Merge with any custom `env` overrides supplied by the user.

### 2. Command Absolute Path Expansion (`resolveExecutablePath`)
- Add a helper function `resolveExecutable(String command, String pathEnv)`:
  - If `command` already contains a path separator (`/`), return it as-is.
  - Otherwise, search each directory in `pathEnv` for `command` (and ensure it is executable).
  - If found, use the resolved absolute path to execute directly, bypassing shell lookup ambiguities.

### 3. Stderr Ring Buffer & Enhanced Error Handling
- In `McpStdioSession`:
  - Keep a `List<String> _recentStderr = []` capped at 20 lines.
  - In `_stderrSub.listen`: append non-empty lines to `_recentStderr`.
  - In `_process!.exitCode.then((code))`:
    - Save `_exitCode = code`.
    - If `code != 0`:
      - Format error string: `MCP 进程异常退出 (code $code): ${_recentStderr.join('\n')}`.
      - Pass this descriptive error into `_cleanup(errorString)` so any pending requests are rejected with this exact diagnostic.
  - In `start()`:
    - If handshake fails, ensure `_recentStderr` is included in the exception message.

## Security Considerations
- Probed directories are confined to standard user home directory tools and system bin paths.
- Does not modify global environment outside child processes.
