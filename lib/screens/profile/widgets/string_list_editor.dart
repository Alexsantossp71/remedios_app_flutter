import 'package:flutter/material.dart';

/// Editor simples de lista de textos: chips com remoção + campo para adicionar.
class StringListEditor extends StatefulWidget {
  const StringListEditor({
    super.key,
    required this.label,
    required this.icon,
    required this.hint,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<StringListEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.values.any((v) => v.toLowerCase() == text.toLowerCase())) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.values, text]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.values.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: widget.values
                    .map(
                      (value) => InputChip(
                        label: Text(value),
                        onDeleted: () => widget.onChanged(
                          widget.values.where((v) => v != value).toList(),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 18),
                      ),
                    )
                    .toList(),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: Text('Nenhum item adicionado'),
            ),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Adicionar',
                onPressed: _add,
              ),
            ),
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
          ),
        ],
      ),
    );
  }
}
