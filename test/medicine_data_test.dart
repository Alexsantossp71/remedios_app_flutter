import 'package:flutter_test/flutter_test.dart';
import 'package:remedios_app_flutter/data/medicine_data.dart';
import 'package:remedios_app_flutter/models/medicine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads active medicine presentations from the bundled catalog',
      () async {
    final medicines = await MedicineData.load();

    expect(medicines.length, greaterThan(10000));
    expect(
        medicines.every((medicine) =>
            medicine.presentation.isNotEmpty || medicine.requiresManualDetails),
        isTrue);
    expect(
        medicines
            .where((medicine) => medicine.registrationNumber.isNotEmpty)
            .every((medicine) => medicine.registrationNumber.length == 9),
        isTrue);
  });

  test('search ignores accents and matches product codes', () {
    final medicine = Medicine(
      name: 'Ácido acetilsalicílico',
      dosage: '',
      presentation: '100 MG COMPRIMIDO',
      activeIngredient: 'Ácido acetilsalicílico',
      registrationNumber: '123456789',
      eans: const ['7891234567890'],
    );

    expect(
      MedicineData.search([medicine], 'acido acetilsalicilico'),
      contains(medicine),
    );
    expect(
        MedicineData.search([medicine], '7891234567890'), contains(medicine));
  });

  test('prioritizes exact commercial names over partial name matches', () {
    final partialMatch = Medicine(
      name: 'ANA-FLEX',
      dosage: '',
      presentation: '35 MG COMPRIMIDO',
      aliases: const ['DORFLEX'],
    );
    final exactMatch = Medicine(
      name: 'DORFLEX',
      dosage: '',
      presentation: '35 MG COMPRIMIDO',
    );
    final results = MedicineData.search(
      [partialMatch, exactMatch],
      'Dorflex',
    );

    expect(results, [exactMatch, partialMatch]);
  });

  test('extracts listed strengths from product presentations', () {
    Medicine createMedicine(String presentation) => Medicine(
          name: 'Produto',
          dosage: '',
          presentation: presentation,
        );

    expect(createMedicine('500 MG COM CT BL AL X 20').listedDosage, '500 MG');
    expect(
      createMedicine('100 MG/ML SOL INJ CX 2 SER').listedDosage,
      '100 MG/ML',
    );
    expect(
      createMedicine('500 MG + 30 MG COM CT BL X 12').listedDosage,
      '500 MG + 30 MG',
    );
    expect(createMedicine('1 FA - 3G').listedDosage, '');
  });

  test('extracts listed strengths that start after the pharmaceutical form',
      () {
    Medicine createMedicine(String presentation) => Medicine(
          name: 'Produto',
          dosage: '',
          presentation: presentation,
        );

    // O caso real da tela: apresentação que começa pela forma, não pela dose.
    expect(
      createMedicine('SODICA - 500MG CX C/ 100 CPR').listedDosage,
      '500MG',
    );
    expect(createMedicine('XAROPE 5MG/ML X 200ML').listedDosage, '5MG/ML');
    expect(
      createMedicine('COM CT BL AL PLAS AMB X 16').listedDosage,
      '',
    );
    // Contagem de unidades não é dose por toma, mesmo perto de um número.
    expect(createMedicine('CX C/ 100 CPR').listedDosage, '');
    expect(createMedicine('FRASCO X 1 U').listedDosage, '');
  });

  test('finds commercial reference names and the manual lookup term', () async {
    final medicines = await MedicineData.load();

    expect(MedicineData.search(medicines, 'Donaren'), isNotEmpty);
    expect(MedicineData.search(medicines, 'Trezete'), isNotEmpty);
    expect(MedicineData.search(medicines, 'Clexane'), isNotEmpty);

    final enterogermina = MedicineData.search(medicines, 'Enterogermina');
    expect(enterogermina, hasLength(1));
    expect(enterogermina.single.requiresManualDetails, isTrue);
    expect(enterogermina.single.registrationNumber, isEmpty);
    expect(enterogermina.single.presentation, isEmpty);
  });
}

test('bestMatch casa estrito: nome exato e prefixo, nada além disso',
    () async {
  final medicines = await MedicineData.load();

  final exact = MedicineData.bestMatch(medicines, '  dipirona  ');
  expect(exact, isNotNull);
  expect(normalizeMedicineText(exact!.name), 'dipirona');

  final prefixed = MedicineData.bestMatch(medicines, 'DIPIRONA COMP');
  expect(prefixed, isNotNull);
  expect(
    normalizeMedicineText(prefixed!.name),
    startsWith('dipirona'),
  );

  // OCR destruído demais não gera palpite: só conferência humana.
  expect(MedicineData.bestMatch(medicines, 'qxzjw vvvk'), isNull);
  expect(MedicineData.bestMatch(medicines, '   '), isNull);
});
