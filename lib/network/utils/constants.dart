const baseUrl = "https://api.gameball.co";
const integrationsUrlV4_0 = "/api/v4.0/integrations";
const integrationsUrlV4_1 = "/api/v4.1/integrations";
const initializeCustomerEndpoint = "/customers";
const sendEventEndpoint = "/events";
const mobileLogsPath = "/api/v4.0/integrations/mobile/logs";
// In-app messaging lives on the V4 integrations surface, alongside the rest of
// this SDK. Pinned to v4.0 and deliberately *not* built with
// getIntegrationsUrl(): that helper switches to v4.1 when a session token is
// present, and the v4.1 variant of these paths answers 401 to APIKey auth — so
// routing through it would break in-app messaging for exactly the hosts that set
// a token. See docs/superpowers/specs/2026-08-17-in-app-messaging-v4-migration-design.md
const inAppMessagesSyncPath = "$integrationsUrlV4_0/inapp-messages/sync";
const inAppMessagesEventsPath = "$integrationsUrlV4_0/inapp-messages/events";
const inAppMessagesVariablesPath =
    "$integrationsUrlV4_0/inapp-messages/variables";
const widgetBaseUrl = "https://m.gameball.app";
