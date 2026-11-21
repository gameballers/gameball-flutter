---
name: sync-api
description: Update an existing SDK method to match a changed API contract (new params, renamed fields, updated response)
---

# Sync API

You are modifying an existing API method in a Gameball mobile SDK to match a contract change. The user will describe what changed (e.g., "add optional referralCode param to initializeCustomer"). You must propagate that change through all affected layers.

## Step 1: Detect the SDK platform

Check the project root for:
- `pubspec.yaml` → **Flutter** (Dart)
- `Package.swift` or `Gameball.podspec` → **iOS** (Swift)
- `package.json` with `react-native` dependency → **React Native** (TypeScript)
- `build.gradle` with `gameballsdk` → **Android** (Kotlin)

## Step 2: Read the current implementation

Read all files involved in the method being changed:
- The public method on `GameballApp`
- The request model
- The response model (if changing response)
- The network call / API interface
- The constants (if endpoint URL changes)

## Step 3: Apply the contract change

### Adding a new parameter

1. **Request model**: Add the field as optional (nullable) to maintain backward compatibility
   - Android: `val newField: String? = null` in data class
   - iOS: `var newField: String?` with default `nil`
   - Flutter: Named optional parameter `{String? newField}`
   - React Native: Optional property `newField?: string`

2. **Network call**: Include the new field in the request body/query params

3. **Public method on GameballApp**: Add the parameter if it should be exposed directly, or ensure the request model carries it

### Changing a field type or name

1. Update the field in the request/response model
2. Update all references in the network call
3. Update the public method signature if affected
4. Add `💥 **BREAKING**` note if this changes the public API

### Changing the response shape

1. Update the response model
2. Update the callback/completion type if the return type changed
3. Update any parsing logic in the network layer

### Changing the endpoint URL

1. Update the constant in the endpoint constants file
2. Verify the HTTP method hasn't changed

## Step 4: Update documentation

- Update code comments/documentation on the changed method
- Update README.md code examples if the public API changed
- If this is a breaking change, note it for MIGRATION.md

## Step 5: Verify consistency

Check that the change follows:
- Session token convention (if the param is session-token related)
- Callback convention (if the return type changed)
- Naming conventions for the platform
- Null safety patterns for the platform
