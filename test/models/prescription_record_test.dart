import 'package:flutter_test/flutter_test.dart';

import 'package:remedios_app_flutter/models/prescription_record.dart';
import 'package:remedios_app_flutter/models/treatment.dart';

Treatment _treatment({
  String prescriberName = '',
  String prescriberCrm = '',
  String prescriberCrmState = '',
  String? prescriberDoctorId,
  DateTime? prescribedOn,
}) {
  return Treatment(
    id: 'treat-1',
    name: 'Losartana',
    dosage: '50mg',
    presentation: 'Comprimido',
    instructions: '',
    startDate: DateTime(2026, 11, 1),
    endDate: null,
    frequency: TreatmentFrequency.daily,
    doseTimes: const [DoseTime(hour: 8, minute: 0)],
    stock: null,
    refillThreshold: null,
    prescriberDoctorId: prescriberDoctorId,
    prescriberName: prescriberName,
    prescriberCrm: prescriberCrm,
    prescriberCrmState: prescriberCrmState,
    prescribedOn: prescribedOn,
  );
}

void main() {
  group('PrescriptionRecord', () {
    test('toJson e fromJson preservam quem receitou e em que dia', () {
      final record = PrescriptionRecord(
        id: 'rec-1',
        treatmentId: 'treat-1',
        doctorId: 'doc-1',
        doctorName: 'Dr. Carlos Almeida',
        doctorCrm: '123456',
        doctorCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
        source: PrescriptionSource.prescriptionPhoto,
        createdAt: DateTime(2026, 11, 15, 10),
      );

      final restored = PrescriptionRecord.fromJson(record.toJson());

      expect(restored.id, 'rec-1');
      expect(restored.treatmentId, 'treat-1');
      expect(restored.doctorId, 'doc-1');
      expect(restored.doctorName, 'Dr. Carlos Almeida');
      expect(restored.doctorCrm, '123456');
      expect(restored.doctorCrmState, 'SP');
      expect(restored.prescribedOn, DateTime(2026, 11, 15));
      expect(restored.source, PrescriptionSource.prescriptionPhoto);
    });

    test('crmLabel espelha o formato do catálogo (Doctor.crmLabel)', () {
      final comUf = PrescriptionRecord(
        id: 'rec-2',
        treatmentId: 'treat-1',
        doctorName: 'Dr. Roberto',
        doctorCrm: '123456',
        doctorCrmState: 'sp',
        prescribedOn: DateTime(2026, 11, 10),
        createdAt: DateTime(2026, 11, 15),
      );
      expect(comUf.crmLabel, 'CRM 123456/SP');

      final semCrm = PrescriptionRecord(
        id: 'rec-3',
        treatmentId: 'treat-1',
        doctorName: 'Dra. Ana',
        prescribedOn: DateTime(2026, 11, 10),
        createdAt: DateTime(2026, 11, 15),
      );
      expect(semCrm.crmLabel, isEmpty);
    });

    test('source tem rótulo legível e tolera nome desconhecido', () {
      expect(
        PrescriptionSource.fromName('prescriptionPhoto'),
        PrescriptionSource.prescriptionPhoto,
      );
      expect(PrescriptionSource.fromName(null), PrescriptionSource.manual);
      expect(
        PrescriptionSource.fromName('lixo'),
        PrescriptionSource.manual,
      );
      expect(
        PrescriptionSource.manual.label,
        'Cadastro manual',
      );
      expect(
        PrescriptionSource.prescriptionPhoto.label,
        'Foto da receita',
      );
    });

    test('matchesTreatment reconhece a mesma receita (nome, CRM e dia)', () {
      final record = PrescriptionRecord(
        id: 'rec-4',
        treatmentId: 'treat-1',
        doctorName: 'dr. carlos almeida',
        doctorCrm: '123456',
        doctorCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
        createdAt: DateTime(2026, 11, 15),
      );

      final igual = _treatment(
        prescriberName: 'Dr. Carlos Almeida',
        prescriberCrm: '123456',
        prescriberCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15, 9, 30),
      );
      expect(record.matchesTreatment(igual), isTrue);

      final outroDia = _treatment(
        prescriberName: 'Dr. Carlos Almeida',
        prescriberCrm: '123456',
        prescriberCrmState: 'SP',
        prescribedOn: DateTime(2026, 12, 1),
      );
      expect(record.matchesTreatment(outroDia), isFalse);

      final outroMedico = _treatment(
        prescriberName: 'Dra. Bianca',
        prescriberCrm: '654321',
        prescriberCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
      );
      expect(record.matchesTreatment(outroMedico), isFalse);
    });
  });

  group('Treatment prescriber (quem receitou)', () {
    test('sem prescritor, hasPrescriber é falso e o JSON não obriga campos', () {
      final treatment = _treatment();
      expect(treatment.hasPrescriber, isFalse);
      expect(treatment.prescriberCrmLabel, isEmpty);

      final restored = Treatment.fromJson(treatment.toJson());
      expect(restored.hasPrescriber, isFalse);
      expect(restored.prescribedOn, isNull);
    });

    test('com prescritor, snapshot preserva nome, CRM, UF e data', () {
      final treatment = _treatment(
        prescriberName: 'Dr. Carlos Almeida',
        prescriberCrm: '123456',
        prescriberCrmState: 'SP',
        prescriberDoctorId: 'doc-9',
        prescribedOn: DateTime(2026, 11, 15),
      );

      expect(treatment.hasPrescriber, isTrue);
      expect(treatment.prescriberCrmLabel, 'CRM 123456/SP');

      final restored = Treatment.fromJson(treatment.toJson());
      expect(restored.prescriberName, 'Dr. Carlos Almeida');
      expect(restored.prescriberCrm, '123456');
      expect(restored.prescriberCrmState, 'SP');
      expect(restored.prescriberDoctorId, 'doc-9');
      expect(restored.prescribedOn, DateTime(2026, 11, 15));
    });

    test('copyWith limpa o prescritor sem tocar no resto', () {
      final treatment = _treatment(
        prescriberName: 'Dr. Carlos Almeida',
        prescriberCrm: '123456',
        prescriberCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
      );

      final limpo = treatment.copyWith(clearPrescriber: true);
      expect(limpo.hasPrescriber, isFalse);
      expect(limpo.name, 'Losartana');
      expect(limpo.prescribedOn, DateTime(2026, 11, 15));

      final semData = treatment.copyWith(clearPrescribedOn: true);
      expect(semData.prescribedOn, isNull);
      expect(semData.prescriberName, 'Dr. Carlos Almeida');
    });

    test('samePrescription muda com nome, CRM ou data — renovação nova', () {
      final base = _treatment(
        prescriberName: 'Dr. Carlos Almeida',
        prescriberCrm: '123456',
        prescriberCrmState: 'SP',
        prescribedOn: DateTime(2026, 11, 15),
      );

      // Mesma receita (nome difere só em caixa; mesmo dia).
      expect(
        Treatment.samePrescription(
          base,
          _treatment(
            prescriberName: 'dr. carlos almeida',
            prescriberCrm: '123456',
            prescriberCrmState: 'SP',
            prescribedOn: DateTime(2026, 11, 15, 21, 0),
          ),
        ),
        isTrue,
      );

      // CRM mudou: prescritor diferente.
      expect(
        Treatment.samePrescription(
          base,
          _treatment(
            prescriberName: 'Dr. Carlos Almeida',
            prescriberCrm: '999999',
            prescriberCrmState: 'SP',
            prescribedOn: DateTime(2026, 11, 15),
          ),
        ),
        isFalse,
      );

      // Data mudou: renovação.
      expect(
        Treatment.samePrescription(
          base,
          _treatment(
            prescriberName: 'Dr. Carlos Almeida',
            prescriberCrm: '123456',
            prescriberCrmState: 'SP',
            prescribedOn: DateTime(2026, 12, 1),
          ),
        ),
        isFalse,
      );

      // De prescritor a nenhum: mudou.
      expect(
        Treatment.samePrescription(base, _treatment()),
        isFalse,
      );
    });
  });
}
