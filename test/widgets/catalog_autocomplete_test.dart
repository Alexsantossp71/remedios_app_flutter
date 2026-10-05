import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/widgets/catalog_autocomplete.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

Future<void> _openOptions(WidgetTester tester, String label) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.tap(field);
  await tester.pumpAndSettle();
}

Future<List<String>> _optionTexts(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final optionFinder = find.descendant(
    of: find.byType(ListView),
    matching: find.byType(InkWell),
  );
  final texts = <String>[];
  for (final element in optionFinder.evaluate()) {
    final inkWell = element.widget as InkWell;
    final child = inkWell.child;
    if (child is Padding && child.child is Align) {
      final align = child.child as Align;
      if (align.child is Text) {
        texts.add((align.child as Text).data ?? '');
      }
    }
  }
  return texts;
}

void main() {
  group('CatalogAutocomplete', () {
    testWidgets('renders label as labelText of inner TextFormField',
        (tester) async {
      await tester.pumpWidget(_wrap(const CatalogAutocomplete(
        label: 'Convênio',
        hint: 'Ex.: Unimed',
        catalog: ['Unimed', 'Bradesco Saúde'],
      )));

      expect(
        find.widgetWithText(TextFormField, 'Convênio'),
        findsOneWidget,
      );

      final textField = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Convênio'),
          matching: find.byType(TextField),
        ),
      );
      expect(textField.decoration?.labelText, 'Convênio');
      expect(textField.decoration?.hintText, 'Ex.: Unimed');
    });

    testWidgets('filters options by substring case-insensitively',
        (tester) async {
      await tester.pumpWidget(_wrap(const CatalogAutocomplete(
        label: 'Especialidade',
        catalog: ['Cardiologia', 'Dermatologia', 'Cardiopediatria'],
      )));

      final field = find.widgetWithText(TextFormField, 'Especialidade');
      await tester.enterText(field, 'CARDIO');
      await tester.pumpAndSettle();

      expect(find.text('Cardiologia'), findsWidgets);
      expect(find.text('Cardiopediatria'), findsWidgets);
      expect(find.text('Dermatologia'), findsNothing);
    });

    testWidgets('shows known values before catalog values', (tester) async {
      await tester.pumpWidget(_wrap(const CatalogAutocomplete(
        label: 'Plano',
        catalog: ['Amil', 'Bradesco Saúde', 'Unimed'],
        known: ['SulAmérica', 'Amil'],
      )));

      await _openOptions(tester, 'Plano');
      final options = await _optionTexts(tester);

      expect(options.first, 'SulAmérica');
      final knownIdx = options.indexOf('SulAmérica');
      final catalogIdx = options.indexOf('Bradesco Saúde');
      expect(knownIdx, lessThan(catalogIdx));
    });

    testWidgets('deduplicates values case-insensitively', (tester) async {
      await tester.pumpWidget(_wrap(const CatalogAutocomplete(
        label: 'Plano',
        catalog: ['Unimed', 'UNIMED', 'Amil'],
        known: ['unimed'],
      )));

      await _openOptions(tester, 'Plano');
      final options = await _optionTexts(tester);

      final unimedCount =
          options.where((o) => o.toLowerCase() == 'unimed').length;
      expect(unimedCount, 1);
      expect(options.length, 2);
    });

    testWidgets('caps options at 10', (tester) async {
      final catalog = List.generate(15, (i) => 'Opção $i');
      await tester.pumpWidget(_wrap(CatalogAutocomplete(
        label: 'Lote',
        catalog: catalog,
      )));

      await _openOptions(tester, 'Lote');
      final options = await _optionTexts(tester);
      expect(options.length, lessThanOrEqualTo(10));
    });

    testWidgets('calls onChanged when typing and on selection',
        (tester) async {
      final events = <String>[];
      await tester.pumpWidget(_wrap(CatalogAutocomplete(
        label: 'Convênio',
        catalog: const ['Unimed', 'Amil'],
        onChanged: events.add,
      )));

      final field = find.widgetWithText(TextFormField, 'Convênio');
      await tester.enterText(field, 'Uni');
      await tester.pumpAndSettle();
      expect(events, contains('Uni'));

      await tester.tap(find.text('Unimed').last);
      await tester.pumpAndSettle();
      expect(events.last, 'Unimed');
    });

    testWidgets('selecting an option fills the field text', (tester) async {
      await tester.pumpWidget(_wrap(const CatalogAutocomplete(
        label: 'Convênio',
        catalog: ['Unimed', 'Amil'],
      )));

      await _openOptions(tester, 'Convênio');
      await tester.tap(find.text('Amil').last);
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Convênio'),
      );
      expect(field.controller?.text, 'Amil');
    });

    testWidgets('honors initialText and external controller', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrap(CatalogAutocomplete(
        label: 'Convênio',
        initialText: 'Bradesco Saúde',
        catalog: const ['Unimed'],
        controller: controller,
      )));

      expect(controller.text, 'Bradesco Saúde');

      final field = find.widgetWithText(TextFormField, 'Convênio');
      await tester.enterText(field, 'Amil');
      await tester.pump();
      expect(controller.text, 'Amil');
    });
  });
}
