import 'dart:math' as math;

/// Filter sweep for intelligent dual-deck transitions (Apple Music Bass Swap).
///
/// Incoming enters with sub-bass cut (< 280 Hz) so kick and bassline do
/// not clash. Across the crossover window (progress 0.40 to 0.75), the filter
/// opens smoothly to 20 Hz (full sub-bass drop) while the outgoing track
/// darkens and lets go.
class TimedMixSweep {
  TimedMixSweep._();

  static double hz(double fromHz, double toHz, double progress) {
    final t = progress.clamp(0.0, 1.0);
    final a = math.log(fromHz);
    final b = math.log(toHz);
    return math.exp(a + (b - a) * t);
  }

  /// Outgoing deck: plays full spectrum through intro phase, then cuts
  /// down to 180 Hz during the bass swap handoff.
  static String outgoing(double progress) {
    final p = progress.clamp(0.0, 1.0);
    final cutoff = p < 0.35
        ? 18000.0
        : (p >= 0.80
            ? 180.0
            : hz(18000, 180, (p - 0.35) / 0.45));
    return 'lowpass=f=${cutoff.round()}:poles=2';
  }

  /// Incoming deck: enters with bass cut (< 280 Hz) so rhythm and melody
  /// are audible immediately without kick-drum clash, then opens fully to
  /// 20 Hz as the incoming track takes over the mix.
  static String incoming(double progress) {
    final p = progress.clamp(0.0, 1.0);
    final cutoff = p < 0.40
        ? 280.0
        : (p >= 0.75
            ? 20.0
            : hz(280, 20, (p - 0.40) / 0.35));
    return 'highpass=f=${cutoff.round()}:poles=2';
  }
}
