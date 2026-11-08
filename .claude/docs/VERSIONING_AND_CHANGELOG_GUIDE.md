Versioning & Changelog Guide
Quick Reference

Version Format: MAJOR.MINOR.PATCH
Breaking Changes → MAJOR (X.0.0) • Removes features, changes APIs, requires manual updates • Example: 1.5.3 → 2.0.0
New Features → MINOR (0.Y.0) • Adds functionality, backward compatible • Example: 1.5.3 → 1.6.0
Bug Fixes → PATCH (0.0.Z) • Fixes bugs, security patches, small tweaks • Example: 1.5.3 → 1.5.4

How to Version Your Release

Step 1: Analyze Your Changes
Ask yourself: • Did I remove or change existing functionality? → MAJOR • Did I add new features or options? → MINOR • Did I only fix bugs or make small improvements? → PATCH
Step 2: Decision Tree
What did you change? • Removed features or settings? → MAJOR (X.0.0) • Changed existing behavior? → MAJOR (X.0.0) • Added new features/sections/options? → MINOR (0.X.0) • Added new customization options? → MINOR (0.X.0) • Fixed bugs only? → PATCH (0.0.X) • Security fixes only? → PATCH (0.0.X)

Common Examples

MAJOR Updates (X.0.0) ❌ Removed a section type ❌ Changed theme settings structure ❌ Removed support for older features ❌ Changed CSS class names that merchants might use
MINOR Updates (0.X.0) ✅ Added new product section ✅ Added new customization options ✅ Added new template files ✅ Added translation support
PATCH Updates (0.0.X) 🔧 Fixed broken styling 🔧 Fixed JavaScript errors 🔧 Improved performance 🔧 Fixed accessibility issues

Changelog Template

File: CHANGELOG.md

# Changelog

All notable changes to [Your Theme Name] are documented here.

## [Unreleased]
*Changes planned for next release*

## [2.1.0] - 2024-07-22

### Added
- New hero section with video background support
- Additional color scheme options in theme settings
- Support for product reviews display

### Changed
- Improved mobile navigation performance
- Updated product card hover effects

### Fixed
- Fixed cart drawer closing unexpectedly on mobile
- Resolved product image zoom issues on Safari

## [2.0.1] - 2024-07-15

### Fixed
- Fixed broken checkout button styling
- Corrected search results page layout

## [2.0.0] - 2024-07-10

### Added
- Complete redesign with modern layout
- New homepage sections (testimonials, FAQ, newsletter)
- Enhanced customization options

### Changed
- **BREAKING**: Updated theme settings structure
- Improved overall performance by 40%

### Removed
- **BREAKING**: Removed legacy slideshow section
- **BREAKING**: Removed old color picker settings

### Fixed
- Multiple accessibility improvements
- Better cross-browser compatibility




Writing Guidelines

✅ Good Changelog Entries
Added • New product comparison feature for up to 3 products • Instagram feed integration in footer • One-click upsell options on product pages
Changed • Improved cart loading speed by 50% • Updated typography for better readability • Enhanced mobile menu with search functionality
Fixed • Fixed product images not loading on slow connections • Resolved duplicate products showing in search results • Corrected color swatch alignment on product cards
❌ Bad Changelog Entries
Added • Stuff for products • New thing in header • Fixed some issues
Changed • Updated code • Made improvements • Better performance

Best Practices

1. Be Specific and Clear ❌ "Fixed bugs" ✅ "Fixed product image zoom not working on mobile Safari"
2. Focus on User Impact ❌ "Refactored CSS architecture" ✅ "Improved page loading speed by 30%"
3. Use Action Words • Start with verbs: Added, Fixed, Improved, Enhanced, Updated • Be consistent with tense (past tense recommended)
4. Group Related ChangesMobile Improvements • Fixed navigation menu overlapping content • Improved touch targets for better usability • Enhanced product image swiping on mobile devices
5. Indicate Breaking ChangesChanged • BREAKING: Theme settings now use new color picker format • BREAKING: Custom CSS classes have been renamed (see migration guide)

Category Definitions

Added 🆕 New features, sections, settings, or capabilities • "Added wishlist functionality" • "Added support for 360° product images" • "Added new blog post layouts"
Changed 🔄 Modifications to existing features • "Improved checkout button visibility" • "Enhanced search functionality with filters" • "Updated footer layout for better mobile experience"
Fixed 🔧 Bug fixes and error corrections • "Fixed cart total calculation error" • "Resolved broken links in navigation menu" • "Corrected product variant image switching"
Removed 🗑️ Deleted features or discontinued support • "Removed deprecated slideshow section" • "Discontinued support for IE11"
Security 🔒 Security-related fixes and improvements • "Fixed XSS vulnerability in contact form" • "Updated dependencies to resolve security issues"

Release Checklist

Before Each Release:
☐ Determine version number using the decision tree ☐ List all changes made since last release ☐ Categorize changes (Added, Changed, Fixed, etc.) ☐ Write clear descriptions focusing on user impact ☐ Mark breaking changes with "BREAKING" label ☐ Add release date in YYYY-MM-DD format ☐ Update version number in theme files ☐ Test all changes before releasing
Example Workflow:

1. Made changes: Added new section, fixed 2 bugs
2. Version decision: New section = MINOR update
3. Current version: 1.4.2 → New version: 1.5.0
4. Write changelog: Document the new section and bug fixes
5. Release: Update version number and publish


Template Examples

Bug Fix Release (PATCH)

## [1.2.1] - 2024-07-22

### Fixed
- Fixed product image gallery not displaying on iOS devices
- Resolved cart drawer animation stuttering issue
- Corrected newsletter signup form validation



Feature Release (MINOR)

## [1.3.0] - 2024-07-22

### Added
- New testimonials section for homepage
- Product filtering by color and size
- Customer account dashboard enhancements

### Changed
- Improved mobile navigation with search integration
- Enhanced product card hover effects

### Fixed
- Fixed newsletter popup appearing too frequently
- Resolved search results pagination issues



Major Update (MAJOR)

## [2.0.0] - 2024-07-22

### Added
- Complete theme redesign with modern aesthetics
- New homepage builder with drag-and-drop sections
- Advanced customization options

### Changed
- **BREAKING**: Updated theme settings structure (see migration guide)
- **BREAKING**: Changed CSS class naming convention
- Improved performance across all pages

### Removed
- **BREAKING**: Removed legacy product gallery section
- **BREAKING**: Discontinued support for old color schemes

### Fixed
- Multiple accessibility improvements
- Enhanced cross-browser compatibility




Pro Tips

1. Keep a running changelog - Don't wait until release time
2. Use consistent language - Establish terminology and stick to it
3. Link to documentation - Reference migration guides for breaking changes
4. Consider your audience - Write for merchants, not developers
5. Review before publishing - Have someone else read your changelog

This guide gives you everything you need to properly version your releases and maintain clear, useful changelogs that your users will actually read and understand.
