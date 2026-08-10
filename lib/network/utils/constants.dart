const baseUrl = "https://api.gameball.co";
const integrationsUrlV4_0 = "/api/v4.0/integrations";
const integrationsUrlV4_1 = "/api/v4.1/integrations";
const initializeCustomerEndpoint = "/customers";
const sendEventEndpoint = "/events";
const mobileLogsPath = "/api/v4.0/integrations/mobile/logs";
// In-app messaging lives under the bots namespace, on v1.0, which is the variant
// that accepts an external customer id as `playerUniqueId`. See
// docs/reference/backend-sdk-endpoints-reference.md.
const botsInAppSyncPath = "/api/v1.0/bots/inapp/sync";
const botsInAppEventsPath = "/api/v1.0/bots/inapp/events";
const widgetBaseUrl = "https://m.gameball.app";
