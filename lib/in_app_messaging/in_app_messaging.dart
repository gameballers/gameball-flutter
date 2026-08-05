/// Public surface of the in-app messaging module.
///
/// Everything else under `in_app_messaging/` is internal. In particular the
/// source, presenter, frequency cap and analytics interfaces are deliberately
/// not exported: they are seams for our own extensibility and tests, and
/// publishing them now would be API we must support.
library;

export 'in_app_messaging_service.dart'
    show GameballBeforeDisplay, GameballDisplayDecision;
export 'models/in_app_message.dart'
    show
        GameballButtonStyle,
        GameballClickAction,
        GameballDismissAction,
        GameballInAppMessage,
        GameballMessageButton,
        GameballMessageStyle,
        GameballMessageType,
        GameballOpenUrlAction,
        maxModalButtons;
export 'models/message_trigger.dart'
    show
        GameballCustomEventTrigger,
        GameballMessageTrigger,
        GameballSessionStartTrigger;
