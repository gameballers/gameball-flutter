const baseUrl = "https://api.gameball.co";
const integrationsUrlV4_0 = "/api/v4.0/integrations";
const integrationsUrlV4_1 = "/api/v4.1/integrations";
const initializeCustomerEndpoint = "/customers";
const sendEventEndpoint = "/events";
const mobileLogsPath = "/api/v4.0/integrations/mobile/logs";

// Taps, swipe-aways and influenced opens of Gameball pushes. Pinned to v4.0 and
// deliberately *not* built with getIntegrationsUrl() (v4.1 with a session
// token), the same as the other SDKs: the click token already names the customer.
// It replaces /mobile/push-click: a backend without push-engagement answers 404
// instead of counting another kind of engagement as a click.
const pushEngagementPath = "$integrationsUrlV4_0/mobile/push-engagement";

const inAppMessageEventsPath =
    "/api/v4.0/integrations/mobile/in-app-messages/events";

// In-app messaging lives under the bots namespace, on v1.0, which is the variant
// that accepts an external customer id as `playerUniqueId`. See
// docs/reference/backend-sdk-endpoints-reference.md.
const botsInAppSyncPath = "/api/v1.0/bots/inapp/sync";
const botsInAppEventsPath = "/api/v1.0/bots/inapp/events";

// In-app messaging lives on the V4 integrations surface, alongside the rest of
// this SDK. Pinned to v4.0 and deliberately *not* built with
// getIntegrationsUrl(): that helper switches to v4.1 when a session token is
// present, and the v4.1 variant of these paths answers 401 to APIKey auth — so
// routing through it would break in-app messaging for exactly the hosts that set
// a token.
const inAppMessagesSyncPath = "$integrationsUrlV4_0/inapp-messages/sync";
const inAppMessagesEventsPath = "$integrationsUrlV4_0/inapp-messages/events";
const inAppMessagesVariablesPath =
    "$integrationsUrlV4_0/inapp-messages/variables";
const widgetBaseUrl = "https://m.gameball.app";
