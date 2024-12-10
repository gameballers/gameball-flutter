import '../../models/responses/initialize_customer_response.dart';

/// Callback function type for customer registration responses.
///
/// Defines the signature for a callback function that handles the result of a customer registration request.
///
/// Arguments:
///   - `response`: The `InitializeCustomerResponse` object if the registration was successful.
///   - `error`: An `Exception` object if an error occurred.
typedef RegisterCallback = void Function(
    InitializeCustomerResponse? response, Exception? error);

/// Callback function type for referral code retrieval.
///
/// Defines the signature for a callback function that handles the result of retrieving a referral code.
///
/// Arguments:
///   - `referralCode`: The retrieved referral code, if any.
///   - `error`: An `Exception` object if an error occurred.
typedef ReferralCodeCallback = void Function(
    String? referralCode, Exception? error);

/// Callback function type for event sending responses.
///
/// Defines the signature for a callback function that handles the result of sending an event.
///
/// Arguments:
///   - `status`: A boolean indicating whether the event was sent successfully.
///   - `error`: An `Exception` object if an error occurred.
typedef SendEventCallback = void Function(bool? status, Exception? error);
