// This file defines constants for left-to-right (LTR) and right-to-left (RTL) languages,
// and provides functions to handle language selection and directionality.

import 'gameball_utils.dart';

/// List of left-to-right (LTR) languages.
const List<String> ltrLanguageCodes = [
  "en",
  "fr",
  "es",
  "de",
  "pt",
  "pl",
  "it",
  "hu",
  "zh-tw",
  "nl",
  "sv",
  "no",
  "dk",
  "ja"
];

/// List of right-to-left (RTL) languages.
const List<String> rtlLanguageCodes = ["ar"];

/// Handles language selection, in priority order:
/// 1. Explicit per-call [override] (e.g. passed to showProfile)
/// 2. Customer preferred language ([preferredLang], set via CustomerAttributes)
/// 3. Global preferred language ([globalLang], set during SDK init)
/// 4. "en" if none of the above is set
/// The first one set wins; an unsupported code resolves to "en".
///
/// Returns the selected language.
String handleLanguage(String globalLang, String? preferredLang, [String? override]) {
  // Highest priority: explicit per-call override
  if (!isNullOrEmpty(override)) {
    return normalizeLanguage(override!);
  }

  if (!isNullOrEmpty(preferredLang)) {
    return normalizeLanguage(preferredLang!);
  }

  return normalizeLanguage(globalLang);
}

/// Returns [lang] trimmed and lowercased if it's supported, otherwise "en".
String normalizeLanguage(String lang) {
  final code = lang.trim().toLowerCase();
  return ltrLanguageCodes.contains(code) || rtlLanguageCodes.contains(code) ? code : "en";
}

/// Checks if a language is right-to-left (RTL). Every other code is treated as left-to-right.
bool isRtl(String lang) {
  return rtlLanguageCodes.contains(lang);
}
