import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';

/// iPhone Photos uses PHPicker, without asking to browse the entire library.
/// Android retains its tested document picker and existing cancellation flow.
Future<XFile?> chooseImportedPhoto() => Platform.isIOS
    ? ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      )
    : openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '照片',
            extensions: ['jpg', 'jpeg', 'png'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
          ),
        ],
      );
