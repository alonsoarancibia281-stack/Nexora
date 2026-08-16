import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the user wants light, dark or the system look.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    _load();
  }

  static const _key = 'nexora_theme_mode_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved == null) return;
      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == saved,
        orElse: () => ThemeMode.dark,
      );
    } catch (_) {
      // Keep the default look when storage is not available.
    }
  }

  Future<void> select(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  /// Quick switch used by the side bar button.
  Future<void> toggle(Brightness current) async {
    final next =
        current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    await select(next);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);

extension ThemeModeLabel on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'Sistema',
        ThemeMode.light => 'Claro',
        ThemeMode.dark => 'Oscuro',
      };

  IconData get icon => switch (this) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };
}
