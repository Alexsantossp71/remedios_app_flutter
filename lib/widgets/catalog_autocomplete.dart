import 'package:flutter/material.dart';

/// A thin generic wrapper over Material `Autocomplete<String>` for text
/// fields that offer suggestions from a [catalog] plus previously-known
/// values ([known]).
///
/// Known values appear first in the suggestion list, followed by catalog
/// values. Options are deduplicated case-insensitively, filtered by
/// case-insensitive substring match, and capped at 10 entries.
class CatalogAutocomplete extends StatelessWidget {
  const CatalogAutocomplete({
    super.key,
    required this.label,
    this.hint,
    this.initialText,
    required this.catalog,
    this.known = const [],
    this.onChanged,
    this.controller,
  });

  /// The label shown as [InputDecoration.labelText] of the inner field.
  final String label;

  /// Optional hint shown as [InputDecoration.hintText] of the inner field.
  final String? hint;

  /// Initial text for the field. Ignored when [controller] is provided.
  final String? initialText;

  /// Catalog values suggested after [known] values.
  final List<String> catalog;

  /// Previously-known values suggested before [catalog] values.
  final List<String> known;

  /// Called whenever the field text changes or an option is selected.
  final ValueChanged<String>? onChanged;

  /// Optional external controller. When provided, [initialText] is ignored.
  final TextEditingController? controller;

  static const int _maxOptions = 10;

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
    );
  }

  Iterable<String> _buildOptions(String query) {
    final normalized = query.trim().toLowerCase();
    bool matches(String value) =>
        normalized.isEmpty || value.toLowerCase().contains(normalized);

    final seen = <String>{};
    final options = <String>[];
    for (final source in [known, catalog]) {
      for (final value in source) {
        final trimmed = value.trim();
        final key = trimmed.toLowerCase();
        if (trimmed.isEmpty || !matches(trimmed)) continue;
        if (seen.add(key)) {
          options.add(trimmed);
          if (options.length >= _maxOptions) return options;
        }
      }
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(
        text: (controller?.text.isNotEmpty ?? false)
            ? controller!.text
            : initialText ?? '',
      ),
      optionsBuilder: (value) => _buildOptions(value.text),
      onSelected: (value) {
        controller?.text = value;
        onChanged?.call(value);
      },
      fieldViewBuilder: (context, fieldController, focusNode, onSubmitted) {
        final external = controller;
        if (external != null && external.text != fieldController.text) {
          if (external.text.isEmpty && fieldController.text.isNotEmpty) {
            external.text = fieldController.text;
          } else {
            fieldController.text = external.text;
          }
        }
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
          onChanged: (value) {
            external?.text = value;
            onChanged?.call(value);
          },
          decoration: _decoration(label, hint: hint),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 400),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(option),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
