import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/core/boot/boot_steps.dart';
import 'package:remedios_app_flutter/widgets/boot_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Etapas fake instantâneas — o comportamento temporal real vem do ticker.
  List<BootStep> fakeSteps(List<String> labels) =>
      labels.map((l) => BootStep(l, () => Future<void>.value())).toList();

  group('BootLoader — comportamento em toda abertura', () {
    testWidgets('começa em 0% com o rótulo da primeira etapa e sem botões', (
      tester,
    ) async {
      final onEnterCalls = <int>[];
      final onDemoCalls = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: fakeSteps(['Etapa um', 'Etapa dois', 'Etapa três']),
            onEnter: () => onEnterCalls.add(1),
            onDemo: () => onDemoCalls.add(1),
            animationDuration: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Etapa um'), findsOneWidget);
      expect(find.text('Entrar'), findsNothing);
      expect(find.text('Demo (não salva dados)'), findsNothing);
      expect(onEnterCalls, isEmpty);
      expect(onDemoCalls, isEmpty);
    });

    testWidgets('percentual avança com o tempo conforme etapas concluem', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: fakeSteps(['Um', 'Dois', 'Três']),
            onEnter: () {},
            onDemo: () {},
            animationDuration: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump(); // microtasks: etapas instantâneas concluem
      await tester.pump(const Duration(milliseconds: 400));

      // ease-out cúbico em t=0.4 → 1 - 0.216 = 78%. Todas as etapas já
      // concluíram, então nenhum teto limita.
      expect(find.text('78%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('chega a 100% e NÃO navega sozinho: revela Entrar/Demo', (
      tester,
    ) async {
      final onEnterCalls = <int>[];
      final onDemoCalls = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: fakeSteps(['Um', 'Dois', 'Três']),
            onEnter: () => onEnterCalls.add(1),
            onDemo: () => onDemoCalls.add(1),
            animationDuration: const Duration(seconds: 1),
            doneHold: const Duration(milliseconds: 100),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('100%'), findsOneWidget);
      expect(find.text(bootDoneLabel), findsOneWidget);
      // Nenhum callback disparado automaticamente e nenhum botão ainda.
      expect(onEnterCalls, isEmpty);
      expect(onDemoCalls, isEmpty);
      expect(find.text('Entrar'), findsNothing);

      // Após o doneHold os botões aparecem na própria tela de %.
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Demo (não salva dados)'), findsOneWidget);
      expect(onEnterCalls, isEmpty, reason: 'navegação só por clique');
      expect(onDemoCalls, isEmpty, reason: 'navegação só por clique');

      // Entrar → onEnter (e apenas ele).
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(onEnterCalls, hasLength(1));
      expect(onDemoCalls, isEmpty);

      // Demo → onDemo.
      await tester.tap(find.text('Demo (não salva dados)'));
      await tester.pump();
      expect(onDemoCalls, hasLength(1));
    });

    testWidgets('rótulo acompanha a etapa atual (teto trava o avanço)', (
      tester,
    ) async {
      final completer1 = Completer<void>();
      final completer2 = Completer<void>();
      final completer3 = Completer<void>();
      final steps = <BootStep>[
        BootStep('Primeira', () => completer1.future),
        BootStep('Segunda', () => completer2.future),
        BootStep('Terceira', () => completer3.future),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: steps,
            onEnter: () {},
            onDemo: () {},
            animationDuration: const Duration(seconds: 1),
            doneHold: const Duration(milliseconds: 50),
          ),
        ),
      );
      await tester.pump();

      // Nenhuma etapa concluída → teto zero → barra presa em 0%.
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Primeira'), findsOneWidget);

      // Primeira etapa conclui → percentual pode avançar até o teto de 33%.
      completer1.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('33%'), findsOneWidget);
      expect(find.text('Segunda'), findsOneWidget);

      // Segunda conclui → teto 66%.
      completer2.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('66%'), findsOneWidget);
      expect(find.text('Terceira'), findsOneWidget);

      // Terceira conclui com a animação já completa (1s) → 100% na hora.
      completer3.complete();
      await tester.pump();
      expect(find.text('100%'), findsOneWidget);
      expect(find.text(bootDoneLabel), findsOneWidget);

      // Libera o timer do doneHold para o FakeAsync não reclamar no fim.
      await tester.pump(const Duration(milliseconds: 60));
    });

    testWidgets('etapa que falha ou demora não trava o app (fail-open)', (
      tester,
    ) async {
      final onEnterCalls = <int>[];
      final hung = Completer<void>(); // nunca completa → estoura timeout
      final steps = <BootStep>[
        BootStep('Quebrada', () async => throw Exception('boom')),
        BootStep('Travada', () => hung.future),
        BootStep('Normal', () => Future<void>.value()),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: steps,
            onEnter: () => onEnterCalls.add(1),
            onDemo: () {},
            animationDuration: const Duration(milliseconds: 100),
            stepTimeout: const Duration(milliseconds: 200),
            doneHold: const Duration(milliseconds: 50),
          ),
        ),
      );
      // 100ms (etapa quebrada) + 200ms (timeout da travada) + margem.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('100%'), findsOneWidget);
      expect(find.text(bootDoneLabel), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Entrar'), findsOneWidget);
      expect(onEnterCalls, isEmpty);

      await tester.tap(find.text('Entrar'));
      await tester.pump();
      expect(onEnterCalls, hasLength(1));
    });

    testWidgets('reduced motion: percentual salta por etapas e ações aparecem', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final onEnterCalls = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: fakeSteps(['Um', 'Dois', 'Três']),
            onEnter: () => onEnterCalls.add(1),
            onDemo: () {},
            animationDuration: const Duration(seconds: 1),
            doneHold: const Duration(milliseconds: 50),
          ),
        ),
      );
      await tester.pump(); // microtasks: etapas concluem
      await tester.pump(); // tick: reduced motion → termina imediatamente

      expect(find.text('100%'), findsOneWidget);
      expect(find.text(bootDoneLabel), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Demo (não salva dados)'), findsOneWidget);
      expect(onEnterCalls, isEmpty);
    });

    testWidgets('expõe progresso à semântica (região viva com value)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: BootLoader(
            steps: fakeSteps(['Um', 'Dois', 'Três']),
            onEnter: () {},
            onDemo: () {},
            animationDuration: const Duration(seconds: 1),
          ),
        ),
      );
      await tester.pump();

      final Finder liveFinder = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.liveRegion ?? false),
      );
      expect(liveFinder, findsOneWidget);

      final data = tester.getSemantics(liveFinder).getSemanticsData();
      expect(data.value, '0%');
      // O rótulo pode vir mesclado com o texto dos filhos (percentual/rótulo
      // renderizados dentro do mesmo nó de semântica).
      expect(data.label, contains('Um'));
      expect(data.flagsCollection.isLiveRegion, isTrue);

      handle.dispose();
    });
  });

  group('buildBootSteps — etapas reais executam sem erro', () {
    // test() puro (não testWidgets): as tarefas fazem I/O real de asset e
    // de storage, que não completa dentro do FakeAsync de testWidgets.
    test('todas as três etapas reais completam', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final steps = buildBootSteps();
      expect(steps.length, bootStepLabels.length);

      for (final step in steps) {
        await step.task().timeout(const Duration(seconds: 10));
      }
      // Se chegou aqui sem exceção, o boot real está sadio.
      expect(steps.map((s) => s.label), bootStepLabels);
    });
  });
}
