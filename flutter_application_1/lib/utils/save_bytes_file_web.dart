import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBytesFile({
  required String filename,
  required List<int> bytes,
  String mime = 'application/octet-stream',
  String? subject,
}) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  // Safari cancels the download if the URL is revoked before it starts.
  unawaited(
    Future<void>.delayed(
      const Duration(seconds: 30),
      () => html.Url.revokeObjectUrl(url),
    ),
  );
}
