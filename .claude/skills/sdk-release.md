---
name: sdk-release
description: Full release flow — version bump, documentation updates, and git commit with standardized message
---

# SDK Release

You are preparing a full release for a Gameball mobile SDK. This skill handles the entire release flow end-to-end:
1. Version bump in platform config files
2. Documentation updates (CHANGELOG, RELEASE_NOTES, MIGRATION)
3. Git commit with a standardized release commit message

## Required References

Before performing any release task, **you MUST read** these two files:
- `.claude/docs/VERSIONING_AND_CHANGELOG_GUIDE.md` — The complete versioning decision tree, changelog templates, and release checklist
- `.claude/docs/SDK_DOCUMENTATION_STANDARD.md` — Templates for RELEASE_NOTES.md and MIGRATION.md

## Usage

The user provides: `/sdk-release <version> <type>`
- `version`: The new version string (e.g., `3.2.0`)
- `type`: `major`, `minor`, or `patch`

If not provided, determine the type from the version number change.

## Step 1: Detect the SDK platform

Check the project root for:
- `pubspec.yaml` → **Flutter**
- `Package.swift` or `Gameball.podspec` → **iOS**
- `package.json` with `react-native` dependency → **React Native**
- `build.gradle` with `gameballsdk` → **Android**

## Step 2: Read current state

**Read the existing files first** before making any changes. You must understand the current state:
- The platform config file (for current version)
- CHANGELOG.md (to see existing entries and structure)
- RELEASE_NOTES.md (to see current content)
- MIGRATION.md (if this is a MAJOR release)

All generated content must be placed **above** existing entries — newest on top. Never append to the bottom.

Read the current version from the platform's config file:
- **Flutter**: `pubspec.yaml` → `version` field
- **iOS**: `Gameball.podspec` → `s.version` field
- **React Native**: `package.json` → `version` field
- **Android**: `gameballsdk/build.gradle` → `versionName` field

Confirm with the user that the version bump is correct (e.g., "Bumping from 3.1.1 to 3.2.0 — is this correct?").

## Step 3: Validate the version bump

Apply the versioning decision tree:
- If the new MAJOR is higher: confirm breaking changes exist
- If the new MINOR is higher: confirm new features exist
- If only PATCH changed: confirm this is bug fixes only
- Warn if the bump doesn't match the type (e.g., user says "patch" but version goes from 3.1.1 to 4.0.0)

## Step 4: Bump version in config files

### Flutter
Update `pubspec.yaml`:
```yaml
version: <new-version>
```

### iOS
Update `Gameball.podspec`:
```ruby
s.version = '<new-version>'
```
Note: `Package.swift` version is controlled by git tags, not a file field.

### React Native
Update `package.json`:
```json
"version": "<new-version>"
```

### Android
Update `gameballsdk/build.gradle`:
```gradle
versionName "<new-version>"
```
Increment `versionCode` by 1.

## Step 5: Trigger documentation updates

After version bump, proceed with the `/sdk-docs release` workflow:
1. Generate CHANGELOG.md entry for the new version
2. Update RELEASE_NOTES.md
3. If MAJOR release, scaffold MIGRATION.md updates

Ask the user to describe the changes for this release, then format them according to the changelog emoji standards.

## Step 6: Git commit

Proceed with the `/sdk-commit` workflow to stage and commit all release changes with a standardized `release: v<version>` commit message.

Pass the version and type to `/sdk-commit`.

## Step 7: Summary

Output a checklist of what was done:
```
## Release v<version> prepared

- [x] Version bumped in <config-file> (<old-version> → <new-version>)
- [x] CHANGELOG.md updated (new entry added on top)
- [x] RELEASE_NOTES.md updated
- [x/n/a] MIGRATION.md updated (major releases only)
- [x] Changes committed: `release: v<version>`

Next steps:
- [ ] Push to remote and create PR
- [ ] After PR merge, create git tag: `git tag v<version> && git push origin v<version>`
```
