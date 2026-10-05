import 'package:flutter/services.dart';

String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Formata o CPF enquanto digita: 000.000.000-00 (até 11 dígitos).
class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOnly(newValue.text);
    final clipped = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buffer = StringBuffer();
    for (var index = 0; index < clipped.length; index++) {
      if (index == 3 || index == 6) buffer.write('.');
      if (index == 9) buffer.write('-');
      buffer.write(clipped[index]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}


class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOnly(newValue.text);
    final clipped = digits.length > 8 ? digits.substring(0, 8) : digits;
    final formatted = clipped.length > 5
        ? '${clipped.substring(0, 5)}-${clipped.substring(5)}'
        : clipped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOnly(newValue.text);
    final clipped = digits.length > 11 ? digits.substring(0, 11) : digits;
    final buffer = StringBuffer();
    for (var index = 0; index < clipped.length; index++) {
      if (index == 0) buffer.write('(');
      if (index == 2) buffer.write(') ');
      if (clipped.length <= 10 && index == 6) buffer.write('-');
      if (clipped.length > 10 && index == 7) buffer.write('-');
      buffer.write(clipped[index]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class CrmInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = digitsOnly(newValue.text);
    final clipped = digits.length > 7 ? digits.substring(0, 7) : digits;
    return TextEditingValue(
      text: clipped,
      selection: TextSelection.collapsed(offset: clipped.length),
    );
  }
}

class UfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final letters = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '');
    final clipped = letters.length > 2 ? letters.substring(0, 2) : letters;
    return TextEditingValue(
      text: clipped,
      selection: TextSelection.collapsed(offset: clipped.length),
    );
  }
}
