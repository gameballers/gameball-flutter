// RTL language list and language selection/direction helpers; any code not listed is LTR.

import 'gameball_utils.dart';

/// List of right-to-left (RTL) languages.
const List<String> rtlLanguageCodes = ["ar"];

/// Handles language selection, in priority order:
/// 1. Explicit per-call [override] (e.g. passed to showProfile)
/// 2. Customer preferred language ([preferredLang], set via CustomerAttributes)
/// 3. Global preferred language ([globalLang], set during SDK init)
/// 4. "en" if none of the above are valid
///
/// Returns the selected language.
String handleLanguage(String globalLang, String? preferredLang, [String? override]) {
  // Highest priority: explicit per-call override
  if (!isNullOrEmpty(override) && override?.length == 2) {
    return override!;
  }

  String? lang = preferredLang;
  // If the preferred language is valid (not null, empty, or not 2 characters), use it.
  if (isNullOrEmpty(lang) || lang?.length != 2) {
    // If the global language is valid, use it, Otherwise, use 'en'.
    lang = globalLang;
    if (isNullOrEmpty(lang) || lang.length != 2) {
      lang = "en";
    }
  }
  return lang.toString();
}

/// Checks if a language is right-to-left (RTL). Every other code is treated as left-to-right.
bool isRtl(String lang) {
  return rtlLanguageCodes.contains(lang);
}
