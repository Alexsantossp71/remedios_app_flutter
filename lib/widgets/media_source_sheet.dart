import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Bottom sheet única de escolha de fonte de imagem (câmera/galeria) —
/// substitui as 3 cópias idênticas em Tratamentos, Médicos e Planos.
Future<ImageSource?> showImageSourceSheet(
  BuildContext context, {
  String cameraLabel = 'Tirar foto',
  String galleryLabel = 'Escolher imagem da galeria',
}) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(cameraLabel),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(galleryLabel),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
