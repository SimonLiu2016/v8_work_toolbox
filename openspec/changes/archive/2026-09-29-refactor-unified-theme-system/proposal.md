## Why

The current theming system defines color tokens as compile-time static constants (`AppTheme.bgCard`, `AppTheme.bgWindow`, `AppTheme.textPrimary`, etc.), bypassing Flutter's inherited `ThemeData` and `ColorScheme` resolution. As a result, when light mode is selected, hundreds of widgets and tool views continue rendering dark backgrounds (`0xFF1E1E1E`, `0xFF2D2D30`), or render faint light-grey text (`0xFFD4D4D4`) on white containers. A centralized, idiomatic Flutter theme architecture is required to systematically bind color tokens and reusable components to Flutter's dynamic theme context.

## What Changes

- **Theme Architecture Refactoring**: Introduce `ThemeExtension<AppColors>` registered in both `AppTheme.lightTheme` and `AppTheme.darkTheme`, providing dynamic semantic color tokens (`bgWindow`, `bgSidebar`, `bgContent`, `bgCard`, `bgCardHover`, `bgInput`, `bgSelected`, `borderSubtle`, `borderStrong`, `textPrimary`, `textSecondary`, `textTertiary`).
- **Typography Modernization**: Decouple `AppTheme.fontHeadline`, `fontTitle`, `fontBody`, and `fontCaption` from static dark-mode text colors, ensuring they dynamically contrast correctly or inherit `Theme.of(context).textTheme`.
- **Reusable Component Unification (`app_components.dart`)**: Update `AppListItem`, `AppCard`, `AppTextField`, `AppButton`, `AppBadge`, and `ShortcutInput` to resolve colors dynamically from `context.colors` / `Theme.of(context)` instead of static dark constants.
- **Top-Level Scaffold & Dialog Background Normalization**: Update `AppShell`, `SettingsDialog`, `AiLogDialog`, `AiConfigPage`, `NetworkProxyPage`, and tool Scaffolds (`OpsToolMainPage`, `PasswordPage`, `PrivateMediaPlayerPage`, etc.) to inherit `ThemeData.scaffoldBackgroundColor` and `dialogTheme` rather than forcing dark `AppTheme.bgWindow` or `AppTheme.bgContent`.
- **Contrast & Legibility Fixes**: Ensure list item selected/hover states, hotkey option tiles, tool titles, and input hints have WCAG-compliant contrast in both light and dark modes.

## Capabilities

### Modified Capabilities
- `theme-and-brand`: Extend the color token system from dark-only neutral grey to a unified, context-driven light and dark theme architecture with dynamic token inheritance across all UI components and shell windows.

## Impact

- `lib/theme/app_theme.dart`: Add `AppColors` `ThemeExtension`, configure `lightTheme` and `darkTheme`, and expose `context.colors`.
- `lib/components/app_components.dart`: Update `AppListItem`, `AppCard`, `AppTextField`, `AppButton`, etc. to use dynamic theme colors.
- `lib/shell/settings_dialog.dart`, `lib/shell/ai_log_dialog.dart`, `lib/shell/tool_panel.dart`, `lib/shell/app_shell.dart`, `lib/shell/ai_config_page.dart`: Replace hardcoded dark tokens with dynamic context tokens.
- `lib/tools/network_proxy/ui/network_proxy_page.dart`, `lib/tools/ops_tool/ui/ops_tool_main_page.dart`, `lib/tools/password/ui/password_page.dart`: Clean up hardcoded background colors.
