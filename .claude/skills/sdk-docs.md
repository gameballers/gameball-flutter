---
name: sdk-docs
description: Unified documentation skill — changelog entries, doc review, and release documentation
---

# SDK Docs

Unified documentation skill for Gameball mobile SDKs. Supports three sub-commands:
- `/sdk-docs changelog` — Add a formatted changelog entry
- `/sdk-docs review` — Audit documentation against the SDK Documentation Standard
- `/sdk-docs release` — Full release documentation pass

## Required References

Before performing any documentation task, **you MUST read** these two files:
- `.claude/docs/SDK_DOCUMENTATION_STANDARD.md` — The master reference for all documentation structure, templates, emoji standards, parameter table format, code example format, and cross-platform consistency rules
- `.claude/docs/VERSIONING_AND_CHANGELOG_GUIDE.md` — The complete versioning decision tree, changelog writing guidelines, category definitions, quality rules, and release checklist

These are the authoritative sources. The instructions below are summaries — always defer to the full documents when in doubt.

---

## Sub-command: `changelog`

### Usage
`/sdk-docs changelog <description of change>`

### What it does

1. Parse the user's description to determine the change category:
   - New feature → `### ✨ Added`
   - Modified existing feature → `### 🔄 Changed`
   - Removed feature → `### 🗑️ Removed`
   - Bug fix → `### 🐛 Fixed`
   - Security improvement → `### 🔒 Security`

2. Determine the appropriate sub-emoji:
   - Architecture/structure: `🏗️`
   - Configuration: `⚙️`
   - Developer experience: `🔧`
   - Performance: `🚀`
   - Dependencies: `📦`
   - Breaking change: prefix with `💥 **BREAKING**:`
   - Security: `🛡️`
   - Guest mode/auth: `🔓`
   - New capability: `🎁`

3. Format the entry following quality rules:
   - Be specific and user-impact focused
   - Start with action verb in past tense
   - Bold the feature/component name
   - Include enough context to understand without reading the code

4. Read the current CHANGELOG.md and insert the entry:
   - **Always read the existing CHANGELOG.md first** to understand the current state
   - If there's an `[Unreleased]` section, add the entry there
   - If not, add it **above** the latest version section (newest content always goes on top)
   - Place it under the correct category heading (create the heading if it doesn't exist)
   - Never append to the bottom — new entries always go above existing ones within their section

### Example

Input: `/sdk-docs changelog Fixed profile widget not loading for guest users`

Output in CHANGELOG.md:
```markdown
### 🐛 Fixed
- 🔧 **Guest Mode Widget**: Fixed profile widget not loading when no customer ID is set
```

---

## Sub-command: `review`

### Usage
`/sdk-docs review`

### What it does

1. Detect the SDK platform (Flutter/iOS/RN/Android)

2. Read all 4 documentation files:
   - README.md
   - CHANGELOG.md
   - MIGRATION.md
   - RELEASE_NOTES.md

3. Read the current public API from `GameballApp` to know what should be documented

4. Audit each file against the SDK Documentation Standard:

#### README.md checks
- [ ] Has required sections: Features, Requirements, Installation, Quick Start, API Methods, Configuration Options, Troubleshooting, Support
- [ ] All public methods are listed under API Methods
- [ ] Code examples use the current API (not outdated patterns)
- [ ] Parameter tables exist for: GameballConfig, InitializeCustomerRequest, ShowProfileRequest, Event
- [ ] Parameter tables include Type, Required, and Description columns
- [ ] Platform-specific badges are present and version is current
- [ ] Support links are correct (email, docs URL, GitHub issues)

#### CHANGELOG.md checks
- [ ] Uses the correct emoji format (`### ✨ Added`, `### 🐛 Fixed`, etc.)
- [ ] Latest version has a date in `YYYY-MM-DD` format
- [ ] Breaking changes are prefixed with `💥 **BREAKING**`
- [ ] Release type emoji matches the version bump type
- [ ] Entries are specific and user-impact focused (not "fixed bugs")

#### MIGRATION.md checks
- [ ] Covers the latest major version upgrade
- [ ] Has before/after code examples for each breaking change
- [ ] Includes migration checklist (Pre-Migration, During Migration, Post-Migration)
- [ ] Troubleshooting section with common migration issues

#### RELEASE_NOTES.md checks
- [ ] Reflects the latest version in CHANGELOG.md
- [ ] Has: Release Date, Version, Type
- [ ] Key Features section with code examples
- [ ] Breaking Changes section (if applicable)
- [ ] Installation section with current version

5. Output a report:
```
## Documentation Review: [Platform SDK]

### README.md
- ✅ [passing checks]
- ❌ [failing checks with specific details]

### CHANGELOG.md
- ✅ [passing checks]
- ❌ [failing checks]

### MIGRATION.md
- ✅ [passing checks]
- ❌ [failing checks]

### RELEASE_NOTES.md
- ✅ [passing checks]
- ❌ [failing checks]

### Summary
- X/Y checks passing
- Priority fixes: [list]
```

Do NOT make changes — this is an audit only.

---

## Sub-command: `release`

### Usage
`/sdk-docs release <version> <type> <description of changes>`

This is typically called by `/sdk-release` after the version bump, but can be run standalone.

### What it does

1. Detect the SDK platform

2. Ask the user what changed in this release (if not provided). Categorize each change.

3. **Update CHANGELOG.md**:
   - **Read the existing CHANGELOG.md first** to see the current versions and structure
   - Add the new version entry **above all existing version entries** (below `[Unreleased]` if it exists, but above the previous latest version)
   - Use the format:
     ```markdown
     ## [X.Y.Z] - YYYY-MM-DD <release-emoji>

     > **Release Type**: Brief description

     ### ✨ Added
     - 🏗️ **Feature**: Description

     ### 🔄 Changed
     - 💥 **BREAKING**: Description (if applicable)

     ### 🐛 Fixed
     - 🔧 **Fix**: Description

     ---
     ```
   - Release emoji: `🎉` for major, `📱` for minor, `🔧` for patch
   - Only include categories that have entries
   - Use today's date in `YYYY-MM-DD` format

4. **Update RELEASE_NOTES.md**:
   - Replace the content with the new release information
   - Follow the RELEASE_NOTES template from the SDK Documentation Standard
   - Include: version, date, type, what's new, key features with code examples, breaking changes (if any), requirements, installation, migration support links

5. **Update MIGRATION.md** (MAJOR releases only):
   - **Read the existing MIGRATION.md first** to see the current structure
   - Add the new migration section **above all existing migration sections** (newest migration on top)
   - Include before/after code examples for each breaking change
   - Follow the MIGRATION template from the SDK Documentation Standard
   - Include migration checklist

6. Output summary of all documentation changes made.
