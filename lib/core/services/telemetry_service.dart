/// Product telemetry — the evidence layer 1.3.0 exists for (Block 3).
///
/// The tax calendar is not the point of this release; learning is. D-2 — who
/// the ICP actually is — is currently settled by two competing guesses, and no
/// amount of further reasoning separates them. These counters replace the
/// guesses with observation.
///
/// ## What may never travel
///
/// Counters and closed-vocabulary categorical values. No free text, no
/// amounts, no document content. Note that the API below makes that a
/// **type-level** property rather than a rule to remember: [record] takes a
/// [ProductEvent] and a [TelemetryDimension], not strings, so there is no call
/// site at which a store name, an OCR line or a lira figure could be passed in
/// the first place. The Postgres CHECK constraints on `product_events` repeat
/// the guarantee independently, so a bug on this side still cannot get a
/// phrase through. A scrubber would be a last line of defence; the design is
/// that the data is never carried.
///
/// ## Consent (D-15)
///
/// Opt-out, resting on KVKK art. 5/2-f (legitimate interest) rather than
/// explicit consent — the payload carries no free text or amount, it attaches
/// to an already-identified account rather than creating a new identity, there
/// is no third-party processor and no cross-border transfer, and the user can
/// switch it off in one tap. Opting out both stops collection and deletes what
/// was collected and not yet sent: otherwise "off" would still mean "the
/// backlog goes out on the next flush".
///
/// ## Third-party SDKs
///
/// None, deliberately. Any analytics SDK would add a new data processor, a
/// cross-border transfer, and a new consent item — three permanent costs to
/// avoid one table.
library;

/// The closed vocabulary of event names.
///
/// Adding a value here is the only way to add an event. That is the point: the
/// enum is the client-side half of the "no free text" guarantee, and the
/// server's `^[a-z][a-z0-9_]{2,47}$` CHECK is the half that does not trust
/// this one.
enum ProductEvent {
  /// User confirmed a captured image and OCR started.
  scanStarted('scan_started'),

  /// User pressed Save on the review screen — the scan became a real receipt.
  ///
  /// Paired with [scanStarted] this gives the conversion rate, which is the
  /// single most informative number about whether the reading pipeline is good
  /// enough to build a paid product on.
  scanApproved('scan_approved'),

  /// User finished the taxpayer-profile step, broken down by
  /// [TelemetryDimension]. This is the distribution that answers D-2.
  ///
  /// ⚠️ No call site yet — the tax calendar is Block 4, which lands after this
  /// one. The key is defined here so Block 4 only has to call it, and so the
  /// vocabulary (the part that needs care, because it is the privacy boundary)
  /// is fixed once, now.
  taxProfileCompleted('tax_profile_completed'),

  /// User opened a tax/payment deadline notification.
  ///
  /// Recorded in `SmartSpendApp` when a tapped reminder's payload resolves to
  /// an obligation. A bare count with no matching "scheduled" counter, so it
  /// answers "does anyone open these" and not "what fraction".
  taxNotificationOpened('tax_notification_opened'),

  /// User edited a generated calendar item. ⚠️ Block 4 call site.
  taxItemEdited('tax_item_edited'),

  /// User removed a generated calendar item — the signal that the generated
  /// calendar is wrong for them. ⚠️ Block 4 call site.
  taxItemRemoved('tax_item_removed'),

  /// User added a deadline we did not generate. ⚠️ Block 4 call site.
  taxItemCustomAdded('tax_item_custom_added');

  const ProductEvent(this.key);

  /// The wire value. Matches the server's `event_key` CHECK by construction.
  final String key;
}

/// The closed vocabulary of categorical breakdowns.
///
/// Currently only taxpayer-profile buckets, which is what D-2 turns on. The
/// values are Turkish because they name Turkish legal forms with no clean
/// English equivalent; the gloss is in each doc comment.
enum TelemetryDimension {
  /// Sole proprietorship.
  sahisSirketi('sahis_sirketi'),

  /// Limited company (Ltd. Şti.) — the current working assumption for the ICP.
  limited('limited'),

  /// Joint-stock company (A.Ş.).
  anonim('anonim'),

  /// Self-employed professional (serbest meslek erbabı) — invoices with
  /// stopaj, the segment that travels most easily to a second country.
  serbestMeslek('serbest_meslek'),

  /// Simplified regime (basit usul).
  basitUsul('basit_usul'),

  /// A form outside the list above.
  diger('diger'),

  /// User skipped the question. Recorded rather than dropped: a high skip rate
  /// is itself an answer about the step.
  belirtilmedi('belirtilmedi');

  const TelemetryDimension(this.value);

  /// The wire value. Matches the server's `dimension` CHECK by construction.
  final String value;
}

/// Records product-usage counters locally and uploads them on the back of the
/// sync engine's own triggers.
abstract class TelemetryService {
  /// Adds one to the counter for [event] (and [dimension], when the event has
  /// a breakdown) for today, UTC.
  ///
  /// Never throws and never blocks a user flow: telemetry that can break a
  /// scan is worse than no telemetry. A failure here is swallowed, because the
  /// alternative — surfacing an analytics error to someone photographing a
  /// receipt — is indefensible.
  ///
  /// A no-op when the user has opted out. Collection stops at the source
  /// rather than at upload, so an opted-out device holds nothing to leak.
  Future<void> record(ProductEvent event, {TelemetryDimension? dimension});

  /// Uploads every pending counter. Returns how many rows were accepted.
  ///
  /// Safe to call repeatedly: each row carries this device's absolute count
  /// for the day, so a retry after a lost response converges on the same
  /// server state instead of double-counting (D-14).
  Future<int> flush();

  /// Whether telemetry is on.
  Future<bool> isEnabled();

  /// What [isEnabled] answers before the user has touched the switch.
  ///
  /// On (opt-out) under D-15, but off where a local rule requires consent for
  /// device-side storage — see D-16. Exposed synchronously so the settings
  /// switch can paint the right position on its first frame instead of showing
  /// the wrong default and flicking.
  bool get defaultEnabled;

  /// Turns telemetry on or off. Turning it off also clears the local backlog.
  Future<void> setEnabled({required bool enabled});

  /// Drops every local counter. Called at sign-out, for the same reason the
  /// conflict quarantine is cleared: these rows describe the previous
  /// account's behaviour and must not survive into the next one.
  Future<void> clearLocalData();

  /// Begins flushing whenever the sync engine completes a run. Idempotent.
  void start();

  /// Tears down the listener.
  Future<void> dispose();
}
