---
name: add-endpoint
description: Scaffold a new API endpoint method with request/response models, network call, and callback in the current SDK
---

# Add Endpoint

You are adding a new API endpoint to a Gameball mobile SDK. The user will provide the endpoint details (name, HTTP method, parameters, response shape). You must scaffold all required code following the existing patterns in the current SDK.

## Step 1: Detect the SDK platform

Check the project root for:
- `pubspec.yaml` → **Flutter** (Dart)
- `Package.swift` or `Gameball.podspec` → **iOS** (Swift)
- `package.json` with `react-native` dependency → **React Native** (TypeScript)
- `build.gradle` with `gameballsdk` → **Android** (Kotlin)

## Step 2: Read existing patterns

Before writing any code, read the following files to understand the existing patterns:
- The main `GameballApp` file to see how existing public methods are structured
- An existing request model to match the builder/constructor pattern
- An existing response model to match the structure
- The network layer to see how API calls are made

## Step 3: Scaffold the following

### 3a. Request Model

Create the request model following the SDK's established pattern:
- **Android**: Data class with builder pattern in `model/request/`
- **iOS**: Struct or class with initializer in `Models/`
- **Flutter**: Class in `models/requests/`
- **React Native**: TypeScript interface in `types/Common.ts` (add to existing file)

### 3b. Response Model (if the endpoint returns data)

Create the response model:
- **Android**: Data class in `model/response/`
- **iOS**: Struct in `Models/`
- **Flutter**: Class in `models/` or appropriate subfolder
- **React Native**: TypeScript interface in `types/Common.ts`

### 3c. Network Call

Wire up the API call:
- **Android**: Add method to `GameBallApi` Retrofit interface, implement in `GameballApp` using RxJava (`subscribeOn(Schedulers.io()).observeOn(AndroidSchedulers.mainThread())`)
- **iOS**: Add method to `NetworkManager`, call from `GameballApp` inside `queue.async`
- **Flutter**: Create request call class in `network/request_calls/`
- **React Native**: Add fetch call in `GameballApp` using existing header/endpoint patterns from `constants.ts`

### 3d. Public Method on GameballApp

Add the public method following the established pattern:
- Singleton access pattern
- Optional `sessionToken` parameter
- Callback/completion parameter for async result
- API key validation before making the call
- Proper error handling and callback invocation

### 3e. Update Constants

Add the new API endpoint URL to the constants file:
- **Android**: `utils/Constants.kt`
- **iOS**: `Constants.swift`
- **Flutter**: `network/utils/constants.dart`
- **React Native**: `constants.ts` (`API_ENDPOINTS`)

## Step 4: Verify

After scaffolding, verify:
- The new method signature is consistent with the shared API contract
- Session token handling follows the convention (optional override of global token)
- Error handling matches existing methods
- All imports are added
