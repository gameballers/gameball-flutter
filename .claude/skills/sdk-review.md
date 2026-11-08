---
name: sdk-review
description: Audit SDK parity — review current SDK or compare all 4 SDKs side by side against the shared contract
---

# SDK Review

Audit Gameball mobile SDKs for parity with the shared API contract. This is a **read-only** operation — report findings but do not make changes.

Supports two modes:
- `/sdk-review` — Audit the current SDK only
- `/sdk-review all` — Audit all 4 SDKs side by side and compare them against each other

## Step 1: Detect mode and locate SDKs

### Single SDK mode (`/sdk-review`)
Check the project root for:
- `pubspec.yaml` → **Flutter** (Dart)
- `Package.swift` or `Gameball.podspec` → **iOS** (Swift)
- `package.json` with `react-native` dependency → **React Native** (TypeScript)
- `build.gradle` with `gameballsdk` → **Android** (Kotlin)

### All SDKs mode (`/sdk-review all`)
Locate all 4 SDK repos as siblings in the parent directory. Look for:
- `../gameball-ios` or a sibling directory containing `Gameball.podspec`
- `../gameball-flutter` or a sibling directory containing `pubspec.yaml` with `gameball`
- `../gameball-react-native` or a sibling directory containing `package.json` with `react-native`
- `../gb-mobile-android` or a sibling directory containing `gameballsdk/`

If a repo can't be found, note it in the report and continue with the ones that are available.

## Step 2: Read the shared contract

The shared API contract (from `.claude/CLAUDE.md`) requires these public methods on `GameballApp`:

| Method | Required Params | Optional Params |
|--------|----------------|-----------------|
| `getInstance()` | Platform-specific | — |
| `init(config)` | `GameballConfig` | completion/callback |
| `initializeCustomer(request, callback)` | `InitializeCustomerRequest`, callback | `sessionToken` |
| `sendEvent(event, callback)` | `Event`, callback | `sessionToken` |
| `showProfile(request)` | `ShowProfileRequest` | `sessionToken` |

## Step 3: Read each SDK's public API

For each SDK being reviewed, read `GameballApp` (the main SDK file) and extract:
- All public methods and their signatures
- Parameter names and types
- Optional vs required parameters
- Callback/completion types
- Session token handling

### File locations
- **iOS**: `Sources/Gameball/GameballApp.swift`
- **Android**: `gameballsdk/src/main/java/com/gameball/gameball/GameballApp.kt`
- **Flutter**: `lib/gameball_sdk.dart`
- **React Native**: `src/GameballApp.ts`

Also read the request/response models to compare field names and types across SDKs.

## Step 4: Compare and report

### For single SDK mode

Generate a report with these sections:

#### Method Parity
For each method in the contract, check:
- Does it exist in this SDK? (Missing = gap)
- Does the method signature match? (Different params = mismatch)
- Is `sessionToken` optional on methods that should support it?

#### Parameter Consistency
For each shared request model (`GameballConfig`, `InitializeCustomerRequest`, `ShowProfileRequest`, `Event`):
- Are all expected fields present?
- Are field names consistent with the contract?
- Are optional/required designations correct?

#### Behavioral Consistency
Check for:
- API key validation before API calls
- SDK initialization check before operations
- Session token override behavior
- Error handling patterns (does it fail fast? surface errors through callbacks?)
- Bot settings fetch during init

#### Guest Mode Support
- Does `ShowProfileRequest.customerId` support null/optional for guest mode?
- Does the widget URL construction handle both authenticated and guest modes?

### For all SDKs mode

Do everything from single SDK mode for each SDK, **plus** cross-SDK comparison:

#### Cross-SDK Method Comparison Table
Build a comparison table showing each method across all 4 SDKs:

```
| Method              | iOS         | Android     | Flutter     | React Native |
|---------------------|-------------|-------------|-------------|--------------|
| getInstance()       | ✅          | ✅          | ✅          | ✅           |
| init(config)        | ✅          | ✅          | ✅          | ✅           |
| initializeCustomer  | ✅          | ✅          | ✅          | ✅           |
| sendEvent           | ✅          | ⚠️ missing  | ✅          | ✅           |
| showProfile         | ✅          | ✅          | ✅          | ✅           |
```

#### Cross-SDK Parameter Comparison
For each shared request model, compare field names and types across SDKs:
- Flag fields that exist in some SDKs but not others
- Flag fields with different names for the same concept
- Flag fields with different required/optional designations

#### Cross-SDK Behavioral Comparison
Compare behaviors across SDKs:
- Which SDKs validate API key before calls vs. which don't?
- Which SDKs support guest mode vs. which don't?
- Session token override: is it consistent across all SDKs?
- Error handling: do all SDKs surface errors the same way?

#### Version Comparison
Read each SDK's version from its config file and compare:
- Are all SDKs on the same major version?
- Are there feature gaps between versions?

#### Documentation Comparison
Compare documentation state across SDKs:
- Do all have CHANGELOG.md, MIGRATION.md, RELEASE_NOTES.md?
- Are they using the same changelog format?
- Are version entries aligned?

## Step 5: Output format

### Single SDK mode
```
## SDK Review: [Platform Name]

### ✅ Passing
- [list of things that match the contract]

### ⚠️ Gaps
- [list of missing methods, parameters, or behaviors]

### 🔄 Mismatches
- [list of things that exist but differ from the contract]

### 💡 Recommendations
- [prioritized list of changes to achieve parity]
```

### All SDKs mode
```
## Cross-SDK Parity Review

### Method Parity
[comparison table]

### Parameter Parity
[field-by-field comparison for each request model]

### Behavioral Parity
[behavior comparison]

### Version Status
| SDK            | Version | Last Release   |
|----------------|---------|----------------|
| iOS            | x.y.z   | YYYY-MM-DD     |
| Android        | x.y.z   | YYYY-MM-DD     |
| Flutter        | x.y.z   | YYYY-MM-DD     |
| React Native   | x.y.z   | YYYY-MM-DD     |

### Per-SDK Details
[individual SDK reports as in single mode]

### 🔴 Critical Gaps (fix before next release)
- [gaps that affect feature parity or correctness]

### 🟡 Non-Critical Gaps (plan for future)
- [nice-to-have alignment improvements]

### 💡 Recommendations
- [prioritized, actionable list]
```

Do NOT make any code changes. This is an audit only.
