import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

Future<void> saveTextFile({
  required String filename,
  required String contents,
  String mime = 'text/plain',
  String? subject,
}) async {
  final bytes = utf8.encode(contents);
  final blob = html.Blob([bytes], mime);
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
