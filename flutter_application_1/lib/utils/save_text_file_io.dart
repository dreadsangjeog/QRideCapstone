import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

Future<void> saveTextFile({
  required String filename,
  required String contents,
  String mime = 'text/plain',
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(contents)),
          mimeType: mime,
          name: filename,
        ),
      ],
      fileNameOverrides: [filename],
      subject: subject ?? filename,
    ),
  );
}
