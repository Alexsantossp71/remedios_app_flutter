import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/lab_values.dart';
import '../models/lab_result.dart';
import '../services/lab_result_storage_service.dart';

/// Estado dos laudos de laboratório: histórico por data e evolução por
/// exame (o PWA mostra a evolução dos marcadores repetidos).
class LabResultProvider extends ChangeNotifier {
  LabResultProvider({LabResultStorageService? storage})
      : _storage = storage ?? LabResultStorageService();

  final LabResultStorageService _storage;

  List<LabResult> _results = [];
  bool _isLoading = true;

  UnmodifiableListView<LabResult> get results =>
      UnmodifiableListView(_results);
  bool get isLoading => _isLoading;
  bool get isEmpty => _results.isEmpty;

  /// Laudos do mais recente para o mais antigo.
  List<LabResult> get resultsByDate {
    return [..._results]
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Evolução dos marcadores repetidos entre laudos (máximo 12, igual
  /// ao PWA) — derivada a cada leitura, nunca persistida.
  List<ExamTrend> get trends {
    return computeTrends(
      _results
          .map(
            (result) => LabResultLike(
              date: _isoDate(result.date),
              labName: result.labName,
              values: result.values,
            ),
          )
          .toList(),
    );
  }

  String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> initialize() async {
    _results = await _storage.loadResults();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveResult(LabResult result) async {
    final existingIndex =
        _results.indexWhere((item) => item.id == result.id);
    if (existingIndex == -1) {
      _results = [..._results, result];
    } else {
      _results = [
        for (var index = 0; index < _results.length; index++)
          if (index == existingIndex) result else _results[index],
      ];
    }
    await _storage.saveResult(result);
    notifyListeners();
  }

  Future<void> removeResult(String id) async {
    _results = _results.where((result) => result.id != id).toList();
    await _storage.deleteResult(id);
    notifyListeners();
  }

  /// Total de marcadores com valor fora da faixa em todos os laudos.
  int get alteredCount {
    var count = 0;
    for (final result in _results) {
      count += result.highCount + result.lowCount;
    }
    return count;
  }
}
