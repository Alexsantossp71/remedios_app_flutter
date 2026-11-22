import 'package:sqflite/sqflite.dart';

/// Popula o banco em memória com dados mock para o modo demo.
///
/// O visitante que toca "Ver demo" na WelcomeScreen vê o app com dados
/// realistas — 2 tratamentos, doses de hoje, médico, consulta, exame,
/// laudo, perfil — sem precisar criar cofre nem cadastrar nada.
///
/// Todos os dados são fictícios. Nenhum dado real de paciente é usado.
class DemoDataSeeder {
  /// Insere dados mock em todas as tabelas do schema v11.
  ///
  /// Chamado por [DatabaseService._initDemoDatabase] após [_onCreate].
  /// Ordem de inserção respeita FKs (pais antes de filhos).
  static Future<void> seed(Database db) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    String utc(DateTime d) => d.toUtc().toIso8601String();

    // ── user_profile ──────────────────────────────────────────────
    await db.insert('user_profile', {
      'id': 1,
      'nome': 'João da Silva',
      'data_nascimento': '1965-03-15T00:00:00.000Z',
      'tipo_sanguineo': 'O+',
      'alergias': '["penicilina"]',
      'condicoes_cronicas': '["hipertensão"]',
      'peso': 78.5,
      'altura': 1.72,
      'telefone': '(11) 99999-9999',
      'cpf': null,
      'consent_at': utc(now),
      'ai_consent_at': null,
      'created_at': utc(now.subtract(const Duration(days: 90))),
      'updated_at': utc(now),
    });

    // ── emergency_contacts ────────────────────────────────────────
    await db.insert('emergency_contacts', {
      'id': 'demo-emer-1',
      'nome': 'Maria da Silva',
      'parentesco': 'Esposa',
      'telefone': '(11) 98888-8888',
      'created_at': utc(now),
      'updated_at': utc(now),
    });
    await db.insert('emergency_contacts', {
      'id': 'demo-emer-2',
      'nome': 'Pedro da Silva',
      'parentesco': 'Filho',
      'telefone': '(11) 97777-7777',
      'created_at': utc(now),
      'updated_at': utc(now),
    });

    // ── health_plans ──────────────────────────────────────────────
    await db.insert('health_plans', {
      'id': 'demo-plan-1',
      'name': 'Plano Essencial',
      'provider': 'UNIMED',
      'card_number': '1234567890',
      'group_number': '001',
      'beneficiary_code': 'JS-001',
      'validity': '12/2027',
      'coverage_type': 'Nacional',
      'specialties': '["cardiologia","clínica geral"]',
      'notes': '',
      'created_at': utc(now),
      'updated_at': utc(now),
    });

    // ── doctors ───────────────────────────────────────────────────
    await db.insert('doctors', {
      'id': 'demo-doc-1',
      'name': 'Dr. Carlos Almeida',
      'specialty': 'Cardiologia',
      'crm': '123456',
      'crm_state': 'SP',
      'phone': '(11) 3333-3333',
      'notes': 'Consulta de retorno em 6 meses.',
      'created_at': utc(now.subtract(const Duration(days: 60))),
      'updated_at': utc(now),
    });

    // ── treatments ────────────────────────────────────────────────
    // Tratamento 1: Losartana (crônico, dose matinal)
    await db.insert('treatments', {
      'id': 'demo-treat-1',
      'name': 'Losartana',
      'dosage': '50mg',
      'presentation': 'Comprimido',
      'instructions': 'Tomar pela manhã com água.',
      'start_date': utc(today.subtract(const Duration(days: 90))),
      'end_date': null,
      'frequency': 'daily',
      'dose_times': '[{"hour":8,"minute":0}]',
      'weekdays': null,
      'stock': 30,
      'refill_threshold': 10,
      'is_archived': 0,
      'prescriber_doctor_id': 'demo-doc-1',
      'prescriber_name': 'Dr. Carlos Almeida',
      'prescriber_crm': '123456',
      'prescriber_crm_state': 'SP',
      'prescribed_on': utc(today.subtract(const Duration(days: 90))),
      'created_at': utc(today.subtract(const Duration(days: 90))),
      'updated_at': utc(now),
    });

    // Tratamento 2: Amoxicilina (agudo, 8/8h por 7 dias)
    await db.insert('treatments', {
      'id': 'demo-treat-2',
      'name': 'Amoxicilina',
      'dosage': '500mg',
      'presentation': 'Cápsula',
      'instructions': 'Tomar após as refeições.',
      'start_date': utc(today),
      'end_date': utc(today.add(const Duration(days: 7))),
      'frequency': 'daily',
      'dose_times':
          '[{"hour":8,"minute":0},{"hour":16,"minute":0},{"hour":22,"minute":0}]',
      'weekdays': null,
      'stock': 21,
      'refill_threshold': 5,
      'is_archived': 0,
      'prescriber_doctor_id': 'demo-doc-1',
      'prescriber_name': 'Dr. Carlos Almeida',
      'prescriber_crm': '123456',
      'prescriber_crm_state': 'SP',
      'prescribed_on': utc(today),
      'created_at': utc(today),
      'updated_at': utc(now),
    });

    // ── dose_events (hoje: 2 tomadas, 2 pendentes) ────────────────
    await db.insert('dose_events', {
      'id': 'demo-dose-1',
      'treatment_id': 'demo-treat-1',
      'scheduled_at': utc(today.add(const Duration(hours: 8))),
      'status': 'taken',
      'completed_at': utc(today.add(const Duration(hours: 8, minutes: 5))),
      'created_at': utc(today),
    });
    await db.insert('dose_events', {
      'id': 'demo-dose-2',
      'treatment_id': 'demo-treat-2',
      'scheduled_at': utc(today.add(const Duration(hours: 8))),
      'status': 'taken',
      'completed_at': utc(today.add(const Duration(hours: 8, minutes: 10))),
      'created_at': utc(today),
    });
    await db.insert('dose_events', {
      'id': 'demo-dose-3',
      'treatment_id': 'demo-treat-2',
      'scheduled_at': utc(today.add(const Duration(hours: 16))),
      'status': 'pending',
      'created_at': utc(today),
    });
    await db.insert('dose_events', {
      'id': 'demo-dose-4',
      'treatment_id': 'demo-treat-2',
      'scheduled_at': utc(today.add(const Duration(hours: 22))),
      'status': 'pending',
      'created_at': utc(today),
    });

    // ── treatment_prescriptions ──────────────────────────────────
    await db.insert('treatment_prescriptions', {
      'id': 'demo-rx-1',
      'treatment_id': 'demo-treat-1',
      'doctor_id': 'demo-doc-1',
      'doctor_name': 'Dr. Carlos Almeida',
      'doctor_crm': '123456',
      'doctor_crm_state': 'SP',
      'prescribed_on': utc(today.subtract(const Duration(days: 90))),
      'source': 'manual',
      'created_at': utc(today.subtract(const Duration(days: 90))),
    });
    await db.insert('treatment_prescriptions', {
      'id': 'demo-rx-2',
      'treatment_id': 'demo-treat-2',
      'doctor_id': 'demo-doc-1',
      'doctor_name': 'Dr. Carlos Almeida',
      'doctor_crm': '123456',
      'doctor_crm_state': 'SP',
      'prescribed_on': utc(today),
      'source': 'manual',
      'created_at': utc(today),
    });

    // ── consultations ─────────────────────────────────────────────
    await db.insert('consultations', {
      'id': 'demo-cons-1',
      'doctor_id': 'demo-doc-1',
      'title': 'Consulta de rotina — hipertensão',
      'date': utc(today.subtract(const Duration(days: 60))),
      'status': 'completed',
      'notes': 'Pressão controlada. Manter Losartana 50mg.',
      'return_date': utc(today.add(const Duration(days: 120))),
      'created_at': utc(today.subtract(const Duration(days: 60))),
      'updated_at': utc(today.subtract(const Duration(days: 60))),
    });

    // ── exams ─────────────────────────────────────────────────────
    await db.insert('exams', {
      'id': 'demo-exam-1',
      'name': 'Eletrocardiograma',
      'category': 'Cardiologia',
      'status': 'done',
      'date': utc(today.subtract(const Duration(days: 30))),
      'time': '10:00',
      'photo': null,
      'doctor_id': 'demo-doc-1',
      'doctor_name': 'Dr. Carlos Almeida',
      'place': 'Hospital São Lucas',
      'results': 'Ritmo sinusal normal. Frequência 72 bpm.',
      'created_at': utc(today.subtract(const Duration(days: 30))),
      'updated_at': utc(today.subtract(const Duration(days: 25))),
    });

    // ── lab_results ───────────────────────────────────────────────
    await db.insert('lab_results', {
      'id': 'demo-lab-1',
      'date': utc(today.subtract(const Duration(days: 15))),
      'lab_name': 'Laboratório Central',
      'photo': null,
      'values_json':
          '[{"marker":"glicemia","value":92,"unit":"mg/dL","reference_min":70,"reference_max":99,"flag":"normal"},'
          '{"marker":"colesterol_total","value":182,"unit":"mg/dL","reference_min":0,"reference_max":200,"flag":"normal"},'
          '{"marker":"hdl","value":45,"unit":"mg/dL","reference_min":40,"reference_max":99,"flag":"normal"},'
          '{"marker":"ldl","value":110,"unit":"mg/dL","reference_min":0,"reference_max":100,"flag":"alto"},'
          '{"marker":"creatinina","value":0.9,"unit":"mg/dL","reference_min":0.7,"reference_max":1.2,"flag":"normal"}]',
      'notes': 'Jejum de 12h. LDL levemente elevado — Dr. Carlos pediu dieta.',
      'created_at': utc(today.subtract(const Duration(days: 15))),
      'updated_at': utc(today.subtract(const Duration(days: 15))),
    });
  }
}
