import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/exam.dart';
import '../services/exam_storage_service.dart';

/// Estado dos exames: pedidos do médico aguardando, agendados e os já
/// realizados com resultado. Mesma divisão de listas do PWA (pendentes em
/// cima, realizados embaixo).
class ExamProvider extends ChangeNotifier {
  ExamProvider({ExamStorageService? storage})
      : _storage = storage ?? ExamStorageService();

  final ExamStorageService _storage;

  List<Exam> _exams = [];
  bool _isLoading = true;

  UnmodifiableListView<Exam> get exams => UnmodifiableListView(_exams);
  bool get isLoading => _isLoading;
  bool get isEmpty => _exams.isEmpty;

  /// Solicitados + agendados, ordenados pela data (o PWA mostra só os que
  /// ainda não foram realizados na lista principal).
  List<Exam> get pendingExams {
    return _exams.where((exam) => exam.status != ExamStatus.done).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Realizados, do mais recente para o mais antigo.
  List<Exam> get doneExams {
    return _exams.where((exam) => exam.status == ExamStatus.done).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  int get requestedCount => _exams
      .where((exam) => exam.status == ExamStatus.requested)
      .length;
  int get scheduledCount => _exams
      .where((exam) => exam.status == ExamStatus.scheduled)
      .length;
  int get doneCount => doneExams.length;

  Future<void> initialize() async {
    _exams = await _storage.loadExams();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveExam(Exam exam) async {
    final existingIndex = _exams.indexWhere((item) => item.id == exam.id);
    if (existingIndex == -1) {
      _exams = [..._exams, exam];
    } else {
      _exams = [
        for (var index = 0; index < _exams.length; index++)
          if (index == existingIndex) exam else _exams[index],
      ];
    }
    await _storage.saveExam(exam);
    notifyListeners();
  }

  Future<void> removeExam(String id) async {
    _exams = _exams.where((exam) => exam.id != id).toList();
    await _storage.deleteExam(id);
    notifyListeners();
  }

  /// Exames vinculados a um médico do catálogo (para limpar referências
  /// quando o médico é excluído — o nome permanece como snapshot).
  List<Exam> getExamsForDoctor(String doctorId) {
    return _exams.where((exam) => exam.doctorId == doctorId).toList();
  }
}
