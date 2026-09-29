## Context

The application is built with Flutter on macOS desktop. Colors were initially authored as compile-time static constants in `AppTheme` (`AppTheme.bgCard = 0xFF2D2D30`, `AppTheme.textPrimary = 0xFFD4D4D4`). While `MaterialApp` supports `themeMode`, widgets referencing static tokens bypass the inherited widget tree. See `proposal.md` for motivation.

## Goals / Non-Goals

**Goals:**
- Implement standard Flutter `ThemeExtension<AppColors>` for all custom desktop design tokens.
- Upgrade foundation components in `lib/components/app_components.dart` (`AppListItem`, `AppCard`, `AppTextField`, `AppButton`, `AppBadge`) to read from the dynamic theme context.
- Ensure all tool list items, tool page views, dialogs (settings, AI logs), and navigation elements seamlessly update when switching between Follow System, Light, and Dark modes.
- Fix all 7 issues reported in exploration (hotkey option tiles, tool list hover/selected background, tool main page backgrounds, tool title text contrast, proxy page background, AI config page background, log viewer dialog background).

**Non-Goals:**
- Rewriting individual tool internal logic (e.g., KMA generation, Docker API interactions).
- Adding tertiary themes (e.g. high-contrast solarized); only Light, Dark, and Follow System are in scope.

## Decisions

### 1. Flutter `ThemeExtension<AppColors>` over Global Static Switch
- **Decision**: Define `@immutable class AppColors extends ThemeExtension<AppColors>` and register it on `ThemeData.extensions`. Expose `context.colors` via `ThemeContextExtension`.
- **Rationale**: This is Flutter's official idiomatic mechanism for custom design tokens. It automatically handles hot reload, widget subtree scoping, and lerp animation transitions without polluting global state.
- **Alternatives Considered**: Modifying static getters on `AppTheme` to check `SettingsStore` on every access. Rejected because it breaks Flutter's reactive widget rebuilding and cannot handle context-specific theme overrides.

### 2. Upgrading Foundation Components (`app_components.dart`) as the Primary Lever
- **Decision**: Make `AppListItem`, `AppCard`, `AppTextField`, and `AppButton` theme-aware.
- **Rationale**: Over 85% of tool pages and list views use these core components. By making them dynamic, hundreds of screens become light-mode compliant immediately without altering each page's code.

### 3. Normalizing Scaffolds and Dialogs to Inherit `ThemeData`
- **Decision**: Configure `scaffoldBackgroundColor`, `canvasColor`, `dialogTheme`, and `cardTheme` directly in `AppTheme.lightTheme` and `AppTheme.darkTheme`. Remove hardcoded `backgroundColor: AppTheme.bgWindow` from `Scaffold` calls.
- **Rationale**: When `Scaffold()` has no explicit background, Flutter automatically uses `Theme.of(context).scaffoldBackgroundColor`. This ensures all existing and future tool pages look correct by default.

### 4. High-Contrast Typography
- **Decision**: Provide `context.textPrimary`, `context.textSecondary`, and dynamic `textTheme` in `ThemeData`.
- **Rationale**: Light mode uses `#0F172A` (Slate 900) for primary text and `#475569` (Slate 600) for secondary text. Dark mode uses `#D4D4D4` and `#A0A0A0`.

## Risks / Trade-offs

- **[Risk] Deeply nested widgets that still use static `AppTheme.bgCard`**:
  - *Mitigation*: The foundation components (`AppCard`, `AppListItem`, `AppTextField`) will automatically shield most views. For the primary views reported by the user (`AppShell`, `SettingsDialog`, `AiLogDialog`, `AiConfigPage`, `NetworkProxyPage`, `OpsToolMainPage`), we will directly update their container colors.
- **[Risk] Performance overhead of `Theme.of(context)` lookups**:
  - *Mitigation*: Flutter's `InheritedTheme` lookup is $O(1)$ and highly optimized. No noticeable overhead.
