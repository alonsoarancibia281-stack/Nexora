import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the floating readout shows at one instant.
class PulseOverlayReading {
  const PulseOverlayReading({
    required this.headline,
    required this.detail,
    required this.probability,
    required this.up,
    required this.hasReading,
    required this.roundEndsAt,
    this.guard = OverlayGuard.off,
    this.guardDetail = '',
    this.actionLabel = '',
  });

  /// COMPRAR / VENDER / ESPERAR, or the outcome once the round closed.
  final String headline;

  /// Second line: price and opening, or why there is no call.
  final String detail;

  /// 0..100, as declared by the chief analyst.
  final double probability;

  final bool up;
  final bool hasReading;

  /// End of the round **on the device clock**, so the native side can keep
  /// counting down on its own while Flutter is in the background.
  final DateTime roundEndsAt;

  /// State of the protection over a position the user opened by hand.
  final OverlayGuard guard;

  /// One line explaining the guard: what it is watching, or why it fired.
  final String guardDetail;

  /// Label for the button that arms or clears the protection.
  final String actionLabel;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'headline': headline,
        'detail': detail,
        'probability': probability,
        'up': up,
        'hasReading': hasReading,
        'roundEndsAt': roundEndsAt.millisecondsSinceEpoch,
        'guard': guard.index,
        'guardDetail': guardDetail,
        'actionLabel': actionLabel,
      };
}

/// Mirrors `GuardState`, flattened for the platform channel.
enum OverlayGuard { off, armed, triggered }

/// Floating readout drawn on top of whatever app is in front — Binance
/// included.
///
/// It shows what Nexora's council decided for the running five-minute candle
/// and, when the user arms it, watches a position they opened by hand. It does
/// not read the other app's screen and it places no orders: the analysis comes
/// from Binance's own market feed, which Nexora already receives. Android calls
/// this an overlay window and gates it behind a permission the user grants in
/// system settings.
class PulseOverlay {
  const PulseOverlay();

  static const MethodChannel _channel = MethodChannel('ai.nexora/overlay');

  /// Overlay windows are an Android concept; everywhere else this is inert.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<bool> hasPermission() => _ask<bool>('hasPermission');

  /// Opens the system screen where the permission is granted. Android does not
  /// let an app grant it to itself.
  Future<bool> requestPermission() => _ask<bool>('requestPermission');

  /// Starts the floating window. Returns false when the permission is missing.
  Future<bool> start(PulseOverlayReading reading) =>
      _ask<bool>('start', reading.toMap());

  Future<bool> stop() => _ask<bool>('stop');

  Future<bool> isRunning() => _ask<bool>('isRunning');

  /// Refreshes the readout and collects whatever the user tapped on the panel
  /// since the last call — `'toggle'` for the protection button, or an empty
  /// string. The countdown itself ticks natively between calls.
  Future<String> update(PulseOverlayReading reading) async {
    if (!isSupported) return '';
    return _ask<String>('update', reading.toMap());
  }

  Future<T> _ask<T>(String method, [Map<String, dynamic>? arguments]) async {
    if (!isSupported) return _emptyOf<T>();
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      return result ?? _emptyOf<T>();
    } on PlatformException {
      return _emptyOf<T>();
    } on MissingPluginException {
      // Build without the native side (or a platform that has none).
      return _emptyOf<T>();
    }
  }

  T _emptyOf<T>() => (T == String ? '' : false) as T;
}
