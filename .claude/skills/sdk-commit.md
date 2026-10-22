---
name: sdk-commit
description: Stage and commit release changes with a standardized release commit message
---

# SDK Commit

Stages and commits release-related changes with a standardized commit message. Typically called by `/sdk-release` after version bump and documentation updates, but can be used independently.

## Usage

`/sdk-commit <version> <type>`
- `version`: The release version (e.g., `3.2.0`)
- `type`: `major`, `minor`, or `patch`

If not provided, detect from the latest changes in the config file or CHANGELOG.md.

## Step 1: Review the working tree

Run `git status` and `git diff` to understand what's changed. Categorize changes into:
- **Release files**: version config, CHANGELOG.md, RELEASE_NOTES.md, MIGRATION.md
- **Unrelated files**: anything else

If there are unrelated uncommitted changes, **warn the user** and ask whether to:
- Include them in the release commit (not recommended)
- Commit them separately first
- Proceed with only the release files

## Step 2: Stage release files only

Stage only the files that are part of the release. Use `git add <file>` for each specific file — **never** `git add .` or `git add -A`.

### Files to stage

**Always** (if changed):
- The platform version config file:
  - Flutter: `pubspec.yaml`
  - iOS: `Gameball.podspec`
  - React Native: `package.json`
  - Android: `gameballsdk/build.gradle`
- `CHANGELOG.md`
- `RELEASE_NOTES.md`

**If applicable**:
- `MIGRATION.md` (major releases only)

## Step 3: Build the commit message

Read the CHANGELOG.md to extract the changes for this version — use them to populate the commit body.

### Commit message format

**PATCH releases:**
```
release: v<version>

<one-line summary of what was fixed>

Changes:
- <change 1>
- <change 2>
```

**MINOR releases:**
```
release: v<version>

<one-line summary of what was added>

Changes:
- <change 1>
- <change 2>
```

**MAJOR releases:**
```
release: v<version>

<one-line summary of the major change>

Breaking Changes:
- <breaking change 1>
- <breaking change 2>

Changes:
- <additional change 1>
- <additional change 2>

Migration: See MIGRATION.md for upgrade instructions.
```

### Rules

- Always use `release: v<version>` prefix — not `chore:`, `feat:`, or other prefixes
- The summary line should match the release description from CHANGELOG.md
- List changes from the CHANGELOG.md entry (strip emojis and markdown formatting for the commit message)
- Use past tense, action verbs
- Pass the commit message via HEREDOC for proper formatting

## Step 4: Commit

```bash
git commit -m "$(cat <<'EOF'
release: v<version>

<summary>

Changes:
- <change 1>
- <change 2>
EOF
)"
```

## Step 5: Post-commit

After committing:
- Run `git status` to verify the commit succeeded and working tree is clean (for release files)
- Do **NOT** push to remote — let the user decide when to push
- Do **NOT** create git tags — tags should be created after the PR is merged

Output:
```
Committed: release: v<version>

Next steps:
- Push to remote and create PR
- After PR merge, create git tag: git tag v<version> && git push origin v<version>
```
