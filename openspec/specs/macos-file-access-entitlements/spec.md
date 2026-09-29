## Purpose

保证 macOS 打包产物声明了系统文件面板所需的 entitlement，使「选择文件/目录」与「保存文件」这两类基础操作在全部工具中真正可用；并保证当这类操作失败时用户看得到反馈，而不是点击后毫无反应。

## Requirements

### Requirement: Build artifacts declare user-selected file entitlements
The macOS build artifacts SHALL declare both `com.apple.security.files.user-selected.read-only` and `com.apple.security.files.user-selected.read-write`, in every build configuration's entitlements file, so that both selection and save panels function.

#### Scenario: Selecting a file succeeds
- **WHEN** the user invokes any tool's file-selection panel (import, choose folder, choose backup)
- **THEN** the system panel opens and returns the chosen path
- **AND** no entitlement error is raised.

#### Scenario: Saving a file succeeds
- **WHEN** the user invokes any tool's save panel (export MP3, export mindmap, save backup, save comparison report)
- **THEN** the system save panel opens and returns the chosen destination
- **AND** no entitlement error is raised, which requires the read-write entitlement since the save path checks only that one.

#### Scenario: Debug and release configurations agree
- **WHEN** the developer switches between the debug/profile and release build configurations
- **THEN** both entitlements are present in each
- **AND** a configuration that works while another fails is a defect.

#### Scenario: Redeployment preserves entitlements
- **WHEN** the app is re-signed by the local deployment script
- **THEN** the re-signed bundle still carries both entitlements
- **AND** a signing invocation that would strip them is a defect.

### Requirement: File panel failures surface to the user
When a file selection or save operation fails, the failure SHALL be visible to the user through the application's normal error surface (snack bar or dialog), not silently ignored.

#### Scenario: Import fails during selection
- **WHEN** a document import fails while opening the file panel or before any file is chosen
- **THEN** the user sees an error message naming the failure
- **AND** the button does not appear to do nothing.

#### Scenario: Exception escaping a button handler is still recorded
- **WHEN** an asynchronous operation started from a button handler throws and nothing in the call chain catches it
- **THEN** the application's global error handling records the failure with a diagnostic message
- **AND** the failure is not swallowed without trace in every window entry point.
