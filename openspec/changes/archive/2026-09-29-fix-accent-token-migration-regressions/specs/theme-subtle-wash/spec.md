## Purpose

定义"弱强调底"（subtle wash）这一颜色角色的契约。它是半透明派生底而非实底，用来给徽标、状态容器、图标底座一个轻量的色彩身份；若被误当作实底使用，底色会变得过重，而当前景又被映射到同一实色时，文字会与底色同色而完全不可读。

## ADDED Requirements

### Requirement: Subtle wash is a translucent derivative, never a solid fill
A subtle wash background SHALL derive from the solid token of the same semantic name via translucency, preserving the original wash intent, rather than resolving to the solid value or the foreground-text value of that name.

#### Scenario: Status badge keeps its wash
- **WHEN** a status badge or status container paints a background that was originally a subtle wash
- **THEN** the background resolves to the solid token reduced by the original wash alpha, not to the solid value itself
- **AND** the badge does not read as a heavy solid block.

#### Scenario: Wash never equals its own foreground
- **WHEN** a subtle wash background is paired with a text or icon foreground of the same semantic name
- **THEN** the two SHALL differ in value, with the background being the translucent derivative and the foreground being the text-tier value
- **AND** the pair's contrast ratio is at least 4.5:1 in both light and dark modes.

#### Scenario: Migration preserves the role
- **WHEN** a color reference is migrated from a static constant to a theme token
- **THEN** the migration preserves the original role — solid fill, foreground text, and translucent wash are not interchangeable
- **AND** a wash that becomes a solid fill, or a wash that becomes the same value as its own foreground, is a defect.

### Requirement: Banner surfaces pair a tinted wash with body text color
A banner or inline notice surface SHALL use a translucent semantic wash as its background and keep the body text on the theme's primary text color, rather than pairing a solid semantic fill with dark body text.

#### Scenario: Info banner in light mode
- **WHEN** an info-type banner is rendered in light mode
- **THEN** its background is the translucent info wash and its body text resolves to the primary text color
- **AND** the body text contrast against that background is at least 4.5:1.

#### Scenario: All banner tiers agree
- **WHEN** any banner tier (info, success, warning, error) is rendered in either mode
- **THEN** each tier resolves its background through the wash role and its body text through the primary text color
- **AND** no tier pairs a solid semantic fill with dark body text.

### Requirement: Tool icon badges keep a light tinted base
A tool page's leading icon container SHALL paint a translucent wash rather than a solid semantic fill, so the icon reads as an accent on a light base instead of a heavy colored block.

#### Scenario: Unattended tool page header in light mode
- **WHEN** the unattended-approver tool page renders its header icon container in light mode
- **THEN** the container background is the translucent semantic wash and the icon resolves to the text-tier value of the same name
- **AND** the container reads as a light tinted base, not a saturated solid block.

### Requirement: Every window initializes the settings store
A window that binds its theme to the persisted theme mode SHALL initialize the settings store before building, so that a user's stored preference reaches that window.

#### Scenario: Password vault window under a dark preference
- **WHEN** the user's persisted theme preference is dark and they open the password vault in its own window
- **THEN** that window initializes the settings store and applies the dark theme
- **AND** the window does not fall back to the system brightness.

#### Scenario: All window kinds initialize settings
- **WHEN** the set of per-window-kind required services is inspected
- **THEN** every window kind that renders a themed `MaterialApp` includes the settings store
- **AND** none of them relies on the notifier's default value.

### Requirement: Translucency misuse is guarded in test and scan
Both the automated test suite and the source-scan guard SHALL detect the signature of a mistranslated wash — a text-tier or solid-tier token used directly as a background, or paired with a translucency coefficient in a context that expects a solid.

#### Scenario: Guard catches a regressed wash
- **WHEN** a wash background is changed to use the text-tier or solid-tier token without translucency
- **THEN** the subtle-role test fails and names the token and mode at fault.

#### Scenario: Guard catches a solid paired with dark text
- **WHEN** a banner or container pairs a solid semantic fill with the primary body text color
- **THEN** the contrast assertion fails because the ratio falls below 4.5:1.
