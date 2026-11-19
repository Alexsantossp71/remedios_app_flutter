/// Validações e conversões numéricas do formulário de perfil.
///
/// Funções puras — sem acesso a estado de widget — reutilizadas pelos
/// validadores de campo do ProfileScreen e testáveis isoladamente.
library;

/// Formata um número decimal do perfil (peso/altura): inteiro sem casas
/// decimais quando possível, caso contrário com duas casas.
String formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.roundToDouble().toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

/// Converte o texto do campo (vírgula aceita como separador decimal) em
/// double; retorna null para texto vazio ou inválido.
double? parseNumber(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed.replaceAll(',', '.'));
}

/// CPF opcional: se preenchido, precisa ter 11 dígitos com dígitos
/// verificadores válidos.
String? cpfError(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 11) return 'CPF deve ter 11 dígitos';
  if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return 'CPF inválido';

  int sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(digits[i]) * (10 - i);
  }
  final d1 = (sum * 10) % 11;
  if ((d1 == 10 ? 0 : d1) != int.parse(digits[9])) return 'CPF inválido';

  sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += int.parse(digits[i]) * (11 - i);
  }
  final d2 = (sum * 10) % 11;
  if ((d2 == 10 ? 0 : d2) != int.parse(digits[10])) return 'CPF inválido';

  return null;
}

/// Telefone opcional: se preenchido, precisa ter 10 ou 11 dígitos.
String? telefoneError(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10 || digits.length > 11) {
    return 'Telefone deve ter 10 ou 11 dígitos';
  }
  return null;
}

/// Peso opcional: se preenchido, deve ser um número entre 1 e 500 kg.
String? pesoError(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final peso = parseNumber(value);
  if (peso == null) return 'Informe um peso válido';
  if (peso < 1 || peso > 500) return 'Peso deve estar entre 1 e 500 kg';
  return null;
}

/// Altura opcional: se preenchida, deve ser um número entre 0,30 e
/// 3,00 metros.
String? alturaError(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final altura = parseNumber(value);
  if (altura == null) return 'Informe uma altura válida';
  if (altura < 0.3 || altura > 3) {
    return 'Altura deve estar entre 0,30 e 3,00 m';
  }
  return null;
}
