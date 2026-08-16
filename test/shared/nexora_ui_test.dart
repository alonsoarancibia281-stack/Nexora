import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora_markets_ai/features/settings/presentation/settings_screen.dart';
import 'package:nexora_markets_ai/shared/theme/nexora_theme.dart';
import 'package:nexora_markets_ai/shared/theme/theme_controller.dart';
import 'package:nexora_markets_ai/shared/widgets/nexora_button.dart';
import 'package:nexora_markets_ai/shared/widgets/shader_gradient.dart';

Widget host(Widget child, {ThemeData? theme}) => ProviderScope(
      child: MaterialApp(
        theme: theme ?? NexoraTheme.light(),
        home: child,
      ),
    );

void main() {
  testWidgets('a button keeps its label on one line', (tester) async {
    await tester.pumpWidget(
      host(
        const Scaffold(
          body: SizedBox(
            width: 90,
            child: NexoraButton(
              label: 'Un texto bastante largo para un botón',
              icon: Icons.bolt,
            ),
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(
      find.text('Un texto bastante largo para un botón'),
    );
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a button reports the tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: NexoraButton(label: 'Actualizar', onPressed: () => taps++),
        ),
      ),
    );
    await tester.tap(find.text('Actualizar'));
    expect(taps, 1);
  });

  testWidgets('the segmented control switches option', (tester) async {
    var selected = 'a';
    await tester.pumpWidget(
      host(
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => NexoraSegmented<String>(
              values: const ['a', 'b'],
              selected: selected,
              labelOf: (value) => value == 'a' ? '5 min' : '1 hora',
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('1 hora'));
    await tester.pumpAndSettle();
    expect(selected, 'b');
  });

  testWidgets('the gradient paints behind its child', (tester) async {
    await tester.pumpWidget(
      host(
        const ShaderGradientBackground(
          child: Scaffold(body: Center(child: Text('Nexora'))),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Nexora'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings switches the theme mode', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NexoraTheme.light(),
          darkTheme: NexoraTheme.dark(),
          themeMode: container.read(themeModeProvider),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    // The title and the selected pill in the shell both read 'Ajustes'.
    expect(find.text('Ajustes'), findsWidgets);
    await tester.tap(find.text('Claro'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);

    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
