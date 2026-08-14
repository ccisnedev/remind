/// How precisely a scheduled reminder should be delivered.
///
/// This is a product decision, not a technical one, and the two sensible
/// answers point in opposite directions:
///
/// * A reminder that arrives within the hour is fine, and asking the user for
///   a permission to achieve it is not worth the friction.
/// * A reminder that arrives fifteen minutes late is worse than one that never
///   arrives — a medication interval, a meeting, a market open — and the
///   permission is the price of being useful at all.
///
/// The library refuses to guess. Whichever is chosen, the scheduler reports
/// through `canDeliverExactly()` what it will actually do, so an application
/// can tell the user the truth rather than quietly under-delivering.
enum ExactnessPolicy {
  /// Never request exact delivery.
  ///
  /// Needs no permission and always works. On Android the platform batches the
  /// alarm to save battery, and the window widens with distance: near-instant
  /// for something a minute away, up to a full hour overnight.
  inexact,

  /// Deliver exactly when the platform permits it, and fall back to inexact
  /// when it does not.
  ///
  /// The useful default for most applications. Precision when it is available,
  /// still functional when it is not — and `canDeliverExactly()` says which is
  /// happening, so the application can warn instead of silently drifting.
  preferExact,

  /// Deliver exactly, treating the permission as a hard requirement.
  ///
  /// The scheduler still refuses to fail silently: it schedules with the exact
  /// mode regardless, and `canDeliverExactly()` reports false when permission
  /// is missing. What to do about that — prompt, warn, or refuse to accept the
  /// reminder at all — is the application's decision, because only it knows
  /// whether late is worse than nothing.
  requireExact,
}
