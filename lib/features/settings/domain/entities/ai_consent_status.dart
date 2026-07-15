/// The user's decision on sending receipt photos to the third-party AI
/// service (Google Gemini) when on-device OCR falls short.
///
/// App Store Guideline 5.1.2(i): personal data may only be shared with a
/// third-party AI service after the user is told what is sent and to whom,
/// and has explicitly agreed. The scan flow asks once before the first scan
/// ([notAsked] → dialog) and the choice stays editable in Settings.
enum AiConsentStatus {
  /// The user has never been asked — the scan flow must ask before any
  /// image could leave the device.
  notAsked,

  /// The user allowed the Gemini fallback.
  granted,

  /// The user declined — OCR must stay fully on-device.
  denied,
}
