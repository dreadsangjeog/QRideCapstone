import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveBytesFile({
  required String filename,
  required List<int> bytes,
  String mime = 'application/octet-stream',
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: mime,
          name: filename,
        ),
      ],
      fileNameOverrides: [filename],
      subject: subject ?? filename,
    ),
  );
}
