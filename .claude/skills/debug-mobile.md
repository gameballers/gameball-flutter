---
name: debug-mobile
description: Debug iOS/Android apps on emulators/devices — automated reproduction with screenshots, UI inspection, log analysis, and hypothesis-driven debugging via claude-in-mobile MCP
allowed-tools: Read, Edit, Grep, Glob, Bash, mcp__mobile__*
---

# Mobile Debug Mode

Hypothesis-driven debugging for iOS and Android apps using device/emulator interaction.

**Announce at start:** "Entering Mobile Debug Mode. I will connect, reproduce, capture, analyze, and report."
**State Tracking:** At the top of EVERY response during this workflow, print `[Phase X: NAME]`.

## Usage

- `/debug-mobile <bug description>` — start debugging
- `/debug-mobile <bug description> --platform android|ios` — target specific platform
- `/debug-mobile <bug description> --app com.example.myapp` — target specific app

For "$ARGUMENTS":

---

## Phase 0: MCP & Device Setup

### 0a. Verify MCP Server

Check if the `mobile` MCP server is configured:

```bash
claude mcp list 2>/dev/null | grep -i mobile
```

**If NOT found**, add it automatically:

- **Windows:**
  ```bash
  claude mcp add --transport stdio mobile -- cmd /c npx -y claude-in-mobile
  ```
- **macOS/Linux:**
  ```bash
  claude mcp add --transport stdio mobile -- npx -y claude-in-mobile
  ```

Inform the user: "Added claude-in-mobile MCP server. You may need to restart Claude Code for the tools to become available."

### 0b. Connect to Device

1. Call `list_devices` to discover available devices/emulators
2. If multiple devices found, ask the user which to target
3. Call `set_device` with the selected device
4. Call `screenshot` to verify connection — display it to confirm the device is reachable

**If no devices found:**
- Android: "No Android devices found. Start an emulator or connect a device with USB debugging enabled."
- iOS: "No iOS simulators found. Open Xcode and boot a simulator, or run `xcrun simctl boot <device-id>`."

### 0c. Identify the App

If `--app` was provided, use it. Otherwise:
1. Ask the user for the app package/bundle ID
2. Call `launch_app` to ensure the app is running
3. Take a `screenshot` to confirm the app is in the foreground

**Output:** Connected device, platform, app ID, and initial screenshot confirmed.

---

## Phase 1: Reproduce

A bug you cannot see is a bug you cannot fix.

1. Parse the bug description from `$ARGUMENTS`
2. Ask the user for reproduction steps if not clear from the description
3. Navigate to the buggy screen step by step:
   - Call `annotate_screenshot` to see current screen with labeled elements
   - Use `tap`, `swipe`, `input_text`, `press_key` to follow the reproduction steps
   - Call `annotate_screenshot` after EACH navigation action to verify progress
4. When the bug is visible/triggered:
   - Call `screenshot` to capture the broken state
   - Call `get_logs` to capture logs around the moment of the bug

### Navigation Strategy

```
For each step:
  1. annotate_screenshot → see numbered elements on screen
  2. Identify target element by label/number
  3. tap/swipe/input_text on target
  4. annotate_screenshot → verify result
  5. If wrong screen, press_key BACK and retry
```

### Bug-Type Quick Detection

| Symptom | Immediate Action |
|---------|-----------------|
| App crash / force close | `get_logs` immediately — look for FATAL/Exception |
| Blank/white screen | `get_ui` — check if elements exist but invisible |
| Frozen UI / ANR | `get_logs` filtered for ANR, `get_system_info` for memory |
| Wrong data displayed | `screenshot` + `get_ui` to read actual element text |
| Navigation broken | `get_ui` to check activity/fragment stack |
| Permission denied | `get_logs` + check with `shell` for permission state |

**CRITICAL:** Do NOT proceed to analysis until the bug is reproduced and captured.

---

## Phase 2: Capture State

Once the bug is reproduced, capture everything in rapid succession:

1. **Visual State:**
   - `screenshot` — clean capture of the broken state
   - `annotate_screenshot` — labeled version showing all UI elements

2. **UI Hierarchy:**
   - `get_ui` — full UI tree (element types, IDs, text, visibility, bounds)
   - `find_element` for specific elements relevant to the bug

3. **Logs:**
   - `clear_logs` first
   - Reproduce the exact failing action ONE MORE TIME
   - `get_logs` — isolated logs for just that action
   - Filter for: exceptions, errors, warnings, the app's tag/package name

4. **System State (if relevant):**
   - `get_system_info` — memory, battery, device info
   - `shell` commands for deeper inspection:
     - Android: `dumpsys activity top`, `dumpsys meminfo <package>`
     - iOS: process info via simctl

5. **WebView (if hybrid app):**
   - `get_webview` — inspect WebView DOM, console errors, network

**Output:** A complete snapshot — screenshots, UI tree, filtered logs, system info.

---

## Phase 3: Analyze

Generate **3-5 ranked hypotheses** based on captured evidence.

```
H<N>: <short-name>
  Theory: <what is wrong>
  Evidence from capture: <what supports this>
  Evidence needed: <what would confirm this>
  Platform-specific: <Android/iOS/both>
```

### Common Mobile Bug Patterns

| Pattern | Log Signature | UI Signature |
|---------|--------------|--------------|
| Null pointer / nil | NullPointerException, EXC_BAD_ACCESS | Crash, blank screen |
| Memory leak / OOM | OutOfMemoryError, Jetsam | Crash after prolonged use |
| ANR / UI thread block | ANR in, Application Not Responding | Frozen UI, no response to taps |
| Network timeout | SocketTimeoutException, NSURLErrorDomain | Loading spinner stuck, empty list |
| Permission not granted | SecurityException, permission denied | Feature not working, crash on action |
| Fragment/Activity lifecycle | IllegalStateException, lifecycle | Crash on rotation, back nav |
| Concurrency / race | ConcurrentModificationException | Intermittent wrong data |
| Deep link misroute | No matching intent, URL not handled | Wrong screen, 404 |
| WebView error | console.error, net::ERR_ | Blank WebView, JS errors |

Investigate most likely hypothesis first.

---

## Phase 4: Deep Dive

For each hypothesis (starting with the most likely):

### 4a. Isolate

1. `clear_logs`
2. Reproduce the EXACT action that triggers the bug
3. `get_logs` — capture ONLY the relevant logs
4. `screenshot` — capture the result

### 4b. Test Variations

Depending on the hypothesis, test edge cases:

- **Permission bug:** `revoke_permission` → reproduce → `grant_permission` → reproduce
- **Deep link bug:** `open_url` with various URL formats
- **State bug:** `stop_app` → `launch_app` → navigate back → reproduce
- **Network bug:** Toggle airplane mode via `shell`, reproduce on slow connection
- **Orientation bug:** Rotate device, reproduce
- **Memory bug:** `get_system_info` before and after, check for leaks

### 4c. Verdict

For each hypothesis:
```
H<N> ANALYSIS:
  Expected: <what should happen if this theory is correct>
  Actual:   <what actually happened>
  Verdict:  CONFIRMED / REFUTED / INCONCLUSIVE
  Evidence: <relevant log lines and screenshot observations>
```

**If INCONCLUSIVE after 3 iterations:** Re-evaluate hypotheses, generate new ones based on accumulated evidence, or ask the user for more context.

---

## Phase 5: Source Code Correlation

Once a hypothesis is CONFIRMED:

1. **Map device evidence to source code:**
   - Extract class names, method names, line numbers from stack traces
   - Use `Grep` to find the relevant source files in the project
   - Use `Read` to examine the buggy code

2. **Identify root cause in code:**
   - Cross-reference the log evidence with the source
   - Identify the exact line(s) causing the issue

3. **Propose fix:**
   - Explain the root cause
   - Show the specific code change needed
   - If the user confirms, apply the fix using `Edit`

---

## Phase 6: Verify on Device

After the fix is applied:

1. **Rebuild and deploy** (ask user to rebuild, or run build command if known)
2. `launch_app` — start the updated app
3. Navigate to the previously buggy screen using the same reproduction steps
4. `screenshot` — capture the fixed state
5. `get_logs` — confirm no errors during the fixed flow
6. Compare before/after screenshots

**If the bug persists:** Return to Phase 3 with new evidence.

---

## Report Format

At the end, present a structured report:

```
## Mobile Debug Report

**Device:** <device name and platform>
**App:** <package/bundle ID>
**Bug:** <one-line description>

### Root Cause
<explanation of what went wrong and why>

### Evidence
- **Logs:** <key log lines>
- **Screenshots:** <before/after>
- **UI Hierarchy:** <relevant element state>

### Fix Applied
- **File:** <file path>
- **Change:** <description of the code change>

### Verification
- Reproduced: YES
- Fixed: YES/NO
- Regression risk: LOW/MEDIUM/HIGH
```

---

## Quick Reference

```
ENTER MOBILE DEBUG MODE:
  0. Verify MCP + connect device + launch app
  1. Reproduce (navigate → screenshot → confirm bug)
  2. Capture (screenshot + UI + logs + system info)
  3. Analyze (3-5 hypotheses ranked by evidence)
  4. Deep Dive (isolate → test variations → verdict)
  5. Source Code (map evidence → find code → propose fix)
  6. Verify (rebuild → reproduce → confirm fixed)

NAVIGATION LOOP:
  annotate_screenshot → identify element → tap/swipe → annotate_screenshot → verify

CAPTURE COMBO (do these in rapid succession):
  clear_logs → reproduce action → get_logs + screenshot + get_ui

COMMON TOOLS:
  screenshot / annotate_screenshot — see the device
  tap / swipe / input_text — interact with the device
  get_ui / find_element — inspect UI hierarchy
  get_logs / clear_logs — device logs
  get_system_info — memory, battery, device info
  shell — arbitrary device commands
  open_url — test deep links
  grant_permission / revoke_permission — test permissions
```

---

## Iron Laws

```
1. NO ANALYSIS WITHOUT REPRODUCTION FIRST.
2. NO GUESSING — CAPTURE AND OBSERVE.
3. ALWAYS annotate_screenshot AFTER NAVIGATION — verify you're on the right screen.
4. ISOLATE LOGS — clear_logs before reproducing, capture only relevant output.
5. SCREENSHOT BEFORE AND AFTER EVERY SIGNIFICANT ACTION.
6. CORRELATE VISUAL + LOGS + UI HIERARCHY — never rely on just one signal.
7. VERIFY THE FIX ON DEVICE — code changes mean nothing until confirmed on the emulator.
```

---

## Red Flags — STOP

- "Let me just fix the code..." → STOP. Did you reproduce on device?
- "The logs look fine..." → STOP. Did you check the screenshot and UI hierarchy too?
- "I think it's a..." → STOP. Where's the evidence from the device?
- "The fix should work..." → STOP. Did you verify on the emulator?
- Navigating blindly without `annotate_screenshot` → STOP. You'll tap the wrong element.
- Dumping full `get_logs` without filtering → STOP. Clear first, reproduce, then capture.
