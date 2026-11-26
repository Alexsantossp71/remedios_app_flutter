import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/core/boot/boot_progress.dart';

void main() {
  group('bootProgress — espelho do contrato do PWA (bootProgress.ts)', () {
    test('totalSteps <= 0 → 100 (nada a esperar)', () {
      expect(
        bootProgress(
          elapsed: const Duration(milliseconds: 100),
          stepsDone: 0,
          totalSteps: 0,
        ),
        100,
      );
    });

    test('stepsDone < 0 → 0 (defensivo)', () {
      expect(
        bootProgress(elapsed: const Duration(milliseconds: 500), stepsDone: -1),
        0,
      );
    });

    test('nenhuma etapa concluída → 0 (teto zero trava a barra)', () {
      expect(
        bootProgress(elapsed: const Duration(milliseconds: 1800), stepsDone: 0),
        0,
      );
    });

    test('elapsed zero → 0 mesmo com etapas concluídas', () {
      expect(bootProgress(elapsed: Duration.zero, stepsDone: 3), 0);
    });

    test('teto por etapa: 1/3 concluída trava em 33%', () {
      // ease-out cúbico em t=1.0 → 100%, mas o teto de 1/3 é 33.
      expect(
        bootProgress(elapsed: const Duration(milliseconds: 1800), stepsDone: 1),
        33,
      );
    });

    test('teto por etapa: 2/3 concluídas trava em 66%', () {
      expect(
        bootProgress(elapsed: const Duration(milliseconds: 1800), stepsDone: 2),
        66,
      );
    });

    test(
      'todas as etapas concluídas → teto abre e animação completa em 100',
      () {
        expect(
          bootProgress(
            elapsed: const Duration(milliseconds: 1800),
            stepsDone: 3,
          ),
          100,
        );
        expect(
          bootProgress(
            elapsed: const Duration(milliseconds: 3000),
            stepsDone: 3,
          ),
          100,
        );
      },
    );

    test('meio da animação segue a curva ease-out cúbico quando sem teto', () {
      // easeOutCubic(0.5) = 1 - 0.125 = 0.875 → 88% (arredondado).
      // Com todas as etapas concluídas, nenhum teto limita.
      expect(
        bootProgress(elapsed: const Duration(milliseconds: 900), stepsDone: 3),
        88,
      );
    });

    test('parcela de tempo nunca passa do teto das etapas', () {
      // t=0.9 → ease-out ≈ 99,9% → 100 arredondado; teto de 2 etapas é 66.
      expect(
        bootProgress(elapsed: const Duration(milliseconds: 1620), stepsDone: 2),
        66,
      );
    });

    test('elapsed acima da animação não ultrapassa 100', () {
      expect(
        bootProgress(elapsed: const Duration(seconds: 10), stepsDone: 3),
        100,
      );
    });

    test('início da animação é rápido (ease-out), depois desacelera', () {
      // Curva ease-out: primeiros 10% do tempo avançam muito mais que os
      // últimos 10% — comportamento idêntico ao PWA irmão.
      final int early = bootProgress(
        elapsed: const Duration(milliseconds: 180),
        stepsDone: 3,
      );
      final int late = bootProgress(
        elapsed: const Duration(milliseconds: 1800),
        stepsDone: 3,
      );
      // Linear daria 10%; ease-out dá 27% — o começo é mais rápido.
      expect(early, greaterThan(20));
      expect(early, lessThan(late));
    });
  });

  group('constantes do boot', () {
    test('três etapas com rótulos pt-BR e label final "Tudo pronto!"', () {
      expect(bootStepLabels.length, 3);
      expect(bootStepLabels.first, contains('armazenamento'));
      expect(bootStepLabels[1], contains('offline'));
      expect(bootStepLabels.last, contains('dados'));
      expect(bootDoneLabel, 'Tudo pronto!');
    });

    test('animação dura 1800ms — igual ao PWA irmão', () {
      expect(bootAnimationDuration, const Duration(milliseconds: 1800));
    });
  });
}
