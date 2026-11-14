import 'package:uuid/uuid.dart';

/// Categorias fixas de exame oferecidas no cadastro (usada também pela
/// leitura de IA do pedido) — mesma lista do PWA "Remédio na Hora".
const List<String> examCategories = [
  'Laboratório',
  'Imagem',
  'Cardiológico',
  'Oftalmológico',
  'Outro',
];

class ExamStatus {
  static const requested = 'requested';
  static const scheduled = 'scheduled';
  static const done = 'done';

  static const List<String> values = [requested, scheduled, done];

  static String label(String status) {
    switch (status) {
      case requested:
        return 'Solicitado';
      case scheduled:
        return 'Agendado';
      case done:
        return 'Realizado';
      default:
        return status;
    }
  }
}

/// Exame (laboratório, imagem etc.) registrado pelo usuário — portado do
/// módulo de exames do PWA: acompanha do pedido do médico ao laudo.
///
/// [photo] é a foto do pedido/laudo anexada pelo usuário, comprimida em
/// JPEG e guardada como base64 (mesma decisão do PWA, que a mantinha no
/// armazenamento local do navegador).
class Exam {
  const Exam({
    required this.id,
    required this.name,
    this.category = '',
    this.status = ExamStatus.requested,
    required this.date,
    this.time,
    this.photo,
    this.doctorId = '',
    this.doctorName = '',
    this.place = '',
    this.results = '',
    this.createdAt,
  });

  factory Exam.create({
    required String name,
    String category = '',
    String status = ExamStatus.requested,
    required DateTime date,
    String? time,
    String? photo,
    String doctorId = '',
    String doctorName = '',
    String place = '',
    String results = '',
  }) {
    return Exam(
      id: const Uuid().v4(),
      name: name,
      category: category,
      status: status,
      date: date,
      time: time,
      photo: photo,
      doctorId: doctorId,
      doctorName: doctorName,
      place: place,
      results: results,
      createdAt: DateTime.now().toUtc(),
    );
  }

  final String id;

  /// Nome(s) do(s) exame(s). Vários exames ficam separados por vírgula
  /// (ex.: "Hemograma completo, Glicemia em jejum") — igual ao PWA.
  final String name;
  final String category;
  final String status;

  /// Data do pedido, agendada ou de realização, conforme o [status].
  final DateTime date;

  /// 'HH:MM' agendada (status agendado); null quando sem hora definida.
  final String? time;

  /// Foto do pedido/laudo em base64 JPEG; null quando não anexada.
  final String? photo;

  /// '' quando o médico solicitante não está cadastrado no catálogo.
  final String doctorId;
  final String doctorName;
  final String place;
  final String results;
  final DateTime? createdAt;

  bool get isRequested => status == ExamStatus.requested;
  bool get isScheduled => status == ExamStatus.scheduled;
  bool get isDone => status == ExamStatus.done;

  String get statusLabel => ExamStatus.label(status);

  /// "Pedido em 12/03/2026", "Agendado para …", "Realizado em …" —
  /// mesma redação dos cartões do PWA.
  String get datePrefix {
    switch (status) {
      case ExamStatus.requested:
        return 'Pedido em';
      case ExamStatus.scheduled:
        return 'Agendado para';
      case ExamStatus.done:
        return 'Realizado em';
      default:
        return 'Data';
    }
  }

  factory Exam.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String? ?? '';
    final status = json['status'] as String? ?? ExamStatus.requested;
    return Exam(
      id: json['id'] as String,
      name: json['name'] as String,
      category: examCategories.contains(category) ? category : '',
      status: ExamStatus.values.contains(status) ? status : ExamStatus.requested,
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String?,
      photo: json['photo'] as String?,
      doctorId: json['doctorId'] as String? ?? '',
      doctorName: json['doctorName'] as String? ?? '',
      place: json['place'] as String? ?? '',
      results: json['results'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'status': status,
        'date': date.toIso8601String(),
        'time': time,
        'photo': photo,
        'doctorId': doctorId,
        'doctorName': doctorName,
        'place': place,
        'results': results,
        'createdAt': createdAt?.toUtc().toIso8601String(),
      };

  Exam copyWith({
    String? name,
    String? category,
    String? status,
    DateTime? date,
    String? time,
    bool clearTime = false,
    String? photo,
    bool clearPhoto = false,
    String? doctorId,
    String? doctorName,
    String? place,
    String? results,
  }) {
    return Exam(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      status: status ?? this.status,
      date: date ?? this.date,
      time: clearTime ? null : (time ?? this.time),
      photo: clearPhoto ? null : (photo ?? this.photo),
      doctorId: doctorId ?? this.doctorId,
      doctorName: doctorName ?? this.doctorName,
      place: place ?? this.place,
      results: results ?? this.results,
      createdAt: createdAt,
    );
  }
}
