## Context

V8 Work Toolbox currently uses a two-column shell with a fixed 260px sidebar and a standard macOS window. See `proposal.md` for motivation. To evolve the toolbox into an extensible, modern desktop productivity suite with embedded AI infrastructure, we redesign the window chrome, layout, theme tokens, and add secure AI service layers.

## Goals / Non-Goals

**Goals:**
- Eliminate the native grey titlebar on macOS while preserving native window controls.
- Evolve navigation into a scalable 3-column architecture (Activity Bar 56px + Panel 220px + Content).
- Establish neutral dark grey theme tokens (#1E1E1E, #252526, #333333, #2D2D30) with clear contrast depth.
- Fix macOS status bar tray presence with dedicated 18x18 template icons.
- Build a platform-level AI & MCP configuration hub with Keychain credential protection.
- Ship high-resolution V8 brand icon assets.

**Non-Goals:**
- Implementing local model inference engines inside the app (e.g. compiling llama.cpp into Flutter). Local models are accessed via external Ollama/vLLM endpoints.
- Hosting an MCP server inside the app; the app acts as an MCP client connecting to user-specified external MCP servers.

## Decisions

### 1. macOS Window Chrome: Full-Size Content View with Transparent Titlebar
- **Decision**: In `MainFlutterWindow.swift`, enable:
  ```swift
  self.titlebarAppearsTransparent = true
  self.titleVisibility = .hidden
  self.styleMask.insert(.fullSizeContentView)
  ```
  In Flutter, provide a 38px top draggable padding in the activity bar/sidebar to accommodate the traffic lights cleanly.
- **Alternatives Considered**: Completely borderless window (`.borderless`). Rejected because it breaks native macOS window snapping, tiling, and mission control behavior.

### 2. Navigation Architecture: Activity Bar + Tool Panel + Work Area
- **Decision**:
  - `ActivityBar` (56px): Category switcher (Search/All, File, Build, System, AI Config, Settings).
  - `ToolPanel` (220px): Category tools list, search filter, and collapse toggle (~50px icon-only mode).
  - `ContentArea`: IndexedStack maintaining tool states.
- **Alternatives Considered**:
  - Single flat list: Fails when tools grow beyond 10 items (infinite scrolling, duplicate recents).
  - Modal command palette only (pure Raycast): Less discoverable for novice users who want visual browsing.

### 3. Credential Security: macOS Keychain Integration
- **Decision**: Use `flutter_secure_storage` to write and read API keys securely from the macOS Keychain under accessibility service `com.v8en.V8WorkToolbox.ai`. The JSON file `ai_config.json` only holds metadata (provider ID, name, endpoint, model list), never raw keys.
- **Alternatives Considered**: Storing plain text keys in `ai_config.json`. Rejected due to unacceptable credential leakage risks in local user backup or logs.

### 4. AI Provider & Protocol Abstraction
- **Decision**: Separate protocol handlers from provider definitions. Protocol handlers implement:
  - `OpenAiCompatibleProtocol` (OpenAI, DeepSeek, Ollama, vLLM, Moonshot, etc.)
  - `AnthropicProtocol`
  - `GeminiProtocol`
  Global capability slots (`Text`, `Multimodal`, `TTS`, `STT`) map to `(providerId, modelName)`. Any business tool consumes AI via `AiService.instance.chat(...)` or `AiService.instance.tts(...)` without knowing the underlying provider.
- **Alternatives Considered**: Hardcoding specific SDKs per vendor. Rejected because OpenAI-compatible endpoints cover 80%+ of LLM vendors through a single well-tested client.

### 5. External MCP Client Integration
- **Decision**: Store external MCP client configurations (stdio command or SSE URL, headers, environment variables) in `ai_config.json`. `AiService` initializes client stubs that can discover and execute tool definitions on external servers.
- **Alternatives Considered**: Launching embedded daemon processes. Rejected per user requirement: the toolbox configures and consumes externally running MCP servers.

### 6. Neutral Dark Grey Theme System
- **Decision**: Refactor `AppTheme` tokens:
  - `bgActivityBar`: `#333333`
  - `bgSidebar` (Panel): `#252526`
  - `bgContent`: `#1E1E1E`
  - `bgCard`: `#2D2D30`
  - `bgInput`: `#3C3C3C`
  - `borderSubtle`: `#3C3C3C`
  - `borderStrong`: `#505054`
  - `textPrimary`: `#D4D4D4`
  - `textSecondary`: `#A0A0A0`
- **Alternatives Considered**: Pure black theme (#000000 / #141416). Rejected because of poor surface differentiation and eye fatigue.

## Risks / Trade-offs

- **[Risk]** Window dragging becomes unresponsive when native titlebar is hidden.
  → **Mitigation**: Add window dragging gesture recognizer or native draggable background area on top regions.
- **[Risk]** Keychain permission prompt on macOS.
  → **Mitigation**: Use consistent app signing identity and bundle identifier; provide friendly error handling if Keychain is locked.
- **[Risk]** StatusItem hidden by MacBook display notch if menu bar is crowded.
  → **Mitigation**: Set status item length to fixed length with standard 18x18 template image and high priority.
