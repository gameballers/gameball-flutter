<!-- SHARED:START (do not edit between these markers — managed by gameball-sdk-tooling) -->

# Gameball SDK — Shared Standards

These rules apply to all Gameball mobile SDKs (iOS, Android, Flutter, React Native).

## Public API Contract

All SDKs must expose the following public methods on `GameballApp`:

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getInstance()` | Platform-specific (e.g., `Context` on Android) | `GameballApp` | Singleton accessor |
| `init(config)` | `GameballConfig` | void / Promise | Initialize SDK with API key and settings |
| `initializeCustomer(request, callback)` | `InitializeCustomerRequest`, callback, optional `sessionToken` | void / Promise | Register or initialize a customer |
| `sendEvent(event, callback)` | `Event`, callback, optional `sessionToken` | void / Promise | Track a user event |
| `showProfile(request)` | `ShowProfileRequest`, optional `sessionToken` | void | Display the profile/loyalty widget |

When adding a new public method, it must be added to all 4 SDKs to maintain feature parity.

## Singleton Pattern

- All SDKs use a private constructor + `getInstance()` static method
- Only one instance of `GameballApp` exists per app lifecycle
- No public constructors — consumers must use `getInstance()`

## GameballConfig

All SDKs accept a `GameballConfig` with these fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `apiKey` | String | Yes | Gameball API key |
| `lang` | String | No | Language code (e.g., "en", "ar") |
| `platform` | String | No | Platform identifier |
| `shop` | String | No | Shop identifier |
| `apiPrefix` | String | No | Custom API base URL |
| `sessionToken` | String | No | Global session token for authentication |

## Session Token Convention

- `sessionToken` is an **optional** parameter on `initializeCustomer`, `sendEvent`, and `showProfile`
- When provided on a method call, it **overrides** the global `sessionToken` from `GameballConfig` for that call only
- When omitted, the global `sessionToken` is used (or null if none was set)

## Request Models

All request models (`InitializeCustomerRequest`, `ShowProfileRequest`, `Event`) must:
- Use builder pattern (Android/iOS) or typed objects/interfaces (RN/Flutter)
- Have clear, documented fields
- Validate required fields and throw/return meaningful errors on invalid input
- Support optional `customerId` on `ShowProfileRequest` for guest mode

## Callback Convention

All async operations take a callback with success and error paths:
- **Android**: `Callback<T>` interface with `onSuccess(T)` and `onError(Throwable)`
- **iOS**: Completion handler `((Result?, Error?) -> Void)`
- **React Native**: Promise-based (`async/await`) with optional callback parameter
- **Flutter**: Callback function parameter (e.g., `RegisterCallback`, `SendEventCallback`)

## Error Handling

- Validate `apiKey` is set before any API call — fail fast with a clear error message
- Never silently swallow errors — always surface them through the callback/completion
- Use platform-idiomatic error types (exceptions on Android, `Error` on iOS, thrown errors on RN, `Exception` on Flutter)

## SDK Initialization Flow

All SDKs follow the same init sequence:
1. Store config (API key, language, etc.)
2. Register API key with the network layer
3. Fetch bot settings in the background (fire-and-forget)
4. Mark SDK as initialized

## Versioning

Follow **Semantic Versioning** (MAJOR.MINOR.PATCH):
- **MAJOR** (X.0.0): Removed features, changed existing APIs, requires migration — breaking changes
- **MINOR** (0.Y.0): New features, new endpoints, backward compatible
- **PATCH** (0.0.Z): Bug fixes, security patches, small improvements

When determining version:
- Removed or changed existing functionality? → MAJOR
- Added new features or options? → MINOR
- Fixed bugs only? → PATCH

## Documentation Standards

**Full reference documents** (synced to `.claude/docs/` in each SDK repo):
- `.claude/docs/SDK_DOCUMENTATION_STANDARD.md` — Master reference for all SDK documentation structure, templates, and quality standards
- `.claude/docs/VERSIONING_AND_CHANGELOG_GUIDE.md` — Complete versioning decision tree, changelog writing guidelines, and release checklist

**You MUST read and follow these documents** when working on any documentation task (changelog entries, release notes, migration guides, README updates). They are the authoritative source for templates, formatting, emoji conventions, and quality standards.

All SDKs must maintain 4 documentation files:
1. **README.md** — Primary usage guide with installation, quick start, API reference
2. **CHANGELOG.md** — Version history with semantic categorization
3. **MIGRATION.md** — Upgrade guides for major versions
4. **RELEASE_NOTES.md** — Detailed information about the current release

### Changelog Emoji Format

Use these exact categories and emojis in CHANGELOG.md:

- Release type emojis: `🎉` Major, `📱` Minor, `🔧` Patch
- `### ✨ Added` — New features (`🏗️` Architecture, `⚙️` Configuration, `🔧` Developer experience)
- `### 🔄 Changed` — Modifications (`💥 **BREAKING**` prefix for breaking changes, `🚀` Performance, `📦` Dependencies)
- `### 🗑️ Removed` — Deleted features (`💥 **BREAKING**` prefix when applicable)
- `### 🐛 Fixed` — Bug fixes
- `### 🔒 Security` — Security improvements (`🛡️` prefix)

### Changelog Entry Quality

- Be specific and user-impact focused: "Fixed product image zoom not working on mobile Safari" not "Fixed bugs"
- Start with action verbs (Added, Fixed, Improved, Enhanced, Updated)
- Use past tense consistently
- Group related changes
- Mark breaking changes with `💥 **BREAKING**` prefix

Refer to `.claude/docs/VERSIONING_AND_CHANGELOG_GUIDE.md` for the full decision tree, templates, and examples.

### Version Entry Format

```markdown
## [X.Y.Z] - YYYY-MM-DD <release-emoji>

> **Release Type**: Brief description

### ✨ Added
- 🏗️ **Feature Name**: Description

### 🐛 Fixed
- 🔧 **Fix Name**: Description
```

### README, MIGRATION, and RELEASE_NOTES Structure

Refer to `.claude/docs/SDK_DOCUMENTATION_STANDARD.md` for the complete templates and structure requirements for each file.

## Cross-SDK Coordination

- Major releases should align across platforms when possible
- Breaking changes must be coordinated — all SDKs should release the same breaking change in the same version cycle
- Feature parity: when a feature is added to one SDK, track it for implementation in all others
- Use identical terminology for the same concepts across all SDKs

<!-- SHARED:END -->


## Flutter-Specific Rules

### Language & Style
- Dart with `library gameball_sdk;` directive
- Use named optional parameters with `{}` syntax: `{String? sessionToken}`
- Null safety: use `String?` for nullable, `??` for defaults, `??=` for lazy assignment
- Use `isNullOrEmpty()` utility for string validation

### Architecture
- `GameballApp extends StatelessWidget` — singleton via static `_instance` field
- `getInstance()` returns `const GameballApp()` using `??=`
- Static fields for SDK state (`_apiKey`, `_lang`, `_platform`, etc.)
- Network calls via dedicated request classes in `network/request_calls/`

### Async Pattern
- `Future<void>` for async operations
- Callback function parameters: `RegisterCallback?`, `SendEventCallback?`
- No RxDart — use plain Dart async/await and callbacks

### Distribution
- **pub.dev**: `pubspec.yaml` — update `version` field on release
- Dependencies: `share_plus`, `url_launcher`, `webview_flutter`

### Project Structure
```
lib/
├── gameball_sdk.dart           # Main SDK entry point (library root)
├── models/
│   └── requests/               # Event, InitializeCustomerRequest, etc.
├── network/
│   ├── models/                 # Callbacks
│   ├── request_calls/          # API request implementations
│   └── utils/                  # Constants, helpers
└── utils/                      # Gameball utils, language utils, platform utils
```

### Naming Conventions
- Snake_case file names: `gameball_sdk.dart`, `initialize_customer_request.dart`
- PascalCase class names: `GameballApp`, `GameballConfig`
- Use `_` prefix for private static fields: `_apiKey`, `_instance`
- Request models: `InitializeCustomerRequest`, `ShowProfileRequest`

### Version Source Files
- `pubspec.yaml` → `version`
