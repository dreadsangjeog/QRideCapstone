import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'kyc_auto_match_result.dart';
import 'kyc_face_embedder.dart';
import 'kyc_face_math.dart';

Future<KycAutoMatchResult> reviewKycPhotos({
  required Uint8List idBytes,
  required Uint8List selfieBytes,
  required String firstName,
  required String lastName,
}) async {
  final first = _norm(firstName);
  final last = _norm(lastName);
  if (first.isEmpty || last.isEmpty) {
    return const KycAutoMatchResult(
      nameMatch: false,
      firstNameMatch: false,
      lastNameMatch: false,
      photoMatch: false,
      note: 'Add your first and last name, then photograph your ID again.',
    );
  }

  final dir = Directory.systemTemp;
  final idFile = File(
    '${dir.path}/kyc_id_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  final selfieFile = File(
    '${dir.path}/kyc_selfie_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await idFile.writeAsBytes(idBytes, flush: true);
  await selfieFile.writeAsBytes(selfieBytes, flush: true);

  try {
    final names = await _readIdNames(idFile.path);
    final name = _matchFirstAndLast(
      names,
      firstParts: _parts(first),
      lastParts: _parts(last),
      firstLabel: firstName.trim(),
      lastLabel: lastName.trim(),
    );
    final photo = await _facesMatch(idFile.path, selfieFile.path);

    final note = <String>[];
    if (!name.ok) note.add(name.hint);
    if (!photo.ok) note.add(photo.hint);

    return KycAutoMatchResult(
      nameMatch: name.ok,
      firstNameMatch: name.firstOk,
      lastNameMatch: name.lastOk,
      photoMatch: photo.ok,
      note: note.isEmpty
          ? 'First name, last name, and photo matched. You are verified.'
          : note.join(' '),
    );
  } finally {
    try {
      await idFile.delete();
      await selfieFile.delete();
    } catch (_) {}
  }
}

Future<KycAutoMatchResult> reviewNameOnId({
  required Uint8List idBytes,
  required String firstName,
  required String lastName,
}) async {
  final first = _norm(firstName);
  final last = _norm(lastName);
  if (first.isEmpty || last.isEmpty) {
    return const KycAutoMatchResult(
      nameMatch: false,
      firstNameMatch: false,
      lastNameMatch: false,
      photoMatch: false,
      note: 'Add your first and last name, then photograph your ID again.',
    );
  }

  final dir = Directory.systemTemp;
  final idFile = File(
    '${dir.path}/kyc_id_name_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await idFile.writeAsBytes(idBytes, flush: true);
  try {
    final names = await _readIdNames(idFile.path);
    final name = _matchFirstAndLast(
      names,
      firstParts: _parts(first),
      lastParts: _parts(last),
      firstLabel: firstName.trim(),
      lastLabel: lastName.trim(),
    );
    return KycAutoMatchResult(
      nameMatch: name.ok,
      firstNameMatch: name.firstOk,
      lastNameMatch: name.lastOk,
      photoMatch: true,
      note: name.hint,
    );
  } finally {
    try {
      await idFile.delete();
    } catch (_) {}
  }
}

Future<KycAutoMatchResult> probeIdFace({
  required Uint8List idBytes,
}) async {
  final file = File(
    '${Directory.systemTemp.path}/kyc_id_probe_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(idBytes, flush: true);
  final extras = <File>[];
  try {
    final found = await _locatePrintedFace(file.path, extras);
    if (found == null) {
      return const KycAutoMatchResult(
        nameMatch: true,
        photoMatch: false,
        note:
            'Hold closer so the printed face on the ID is sharp and inside the frame.',
      );
    }
    if (found.sig == null) {
      return const KycAutoMatchResult(
        nameMatch: true,
        photoMatch: false,
        note:
            'The ID photo is not clear enough. Hold steady and move closer to the printed face.',
      );
    }
    return const KycAutoMatchResult(
      nameMatch: true,
      photoMatch: true,
      note: 'Printed face is clear.',
    );
  } finally {
    try {
      await file.delete();
      for (final extra in extras) {
        await extra.delete();
      }
    } catch (_) {}
  }
}

Future<KycAutoMatchResult> reviewFaces({
  required Uint8List idBytes,
  required Uint8List selfieBytes,
}) async {
  final dir = Directory.systemTemp;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final idFile = File('${dir.path}/kyc_id_face_$stamp.jpg');
  final selfieFile = File('${dir.path}/kyc_live_face_$stamp.jpg');
  await idFile.writeAsBytes(idBytes, flush: true);
  await selfieFile.writeAsBytes(selfieBytes, flush: true);
  try {
    final photo = await _facesMatch(idFile.path, selfieFile.path);
    return KycAutoMatchResult(
      nameMatch: true,
      photoMatch: photo.ok,
      note: photo.hint,
      faceVerdict: photo.verdict,
      faceScore: photo.score,
      unreadable: photo.unreadable,
      idFace: photo.idFace,
      liveFace: photo.liveFace,
    );
  } finally {
    try {
      await idFile.delete();
      await selfieFile.delete();
    } catch (_) {}
  }
}

class _Check {
  const _Check({
    required this.ok,
    required this.hint,
    this.verdict,
    this.score,
    this.unreadable,
    this.idFace,
    this.liveFace,
  });

  const _Check.unreadable(KycFaceStep step, String hint)
      : this(ok: false, hint: hint, unreadable: step);

  final bool ok;
  final String hint;
  final KycFaceVerdict? verdict;
  final double? score;
  final KycFaceStep? unreadable;
  final Uint8List? idFace;
  final Uint8List? liveFace;
}

class _NameCheck {
  const _NameCheck({
    required this.firstOk,
    required this.lastOk,
    required this.hint,
  });

  final bool firstOk;
  final bool lastOk;
  final String hint;
  bool get ok => firstOk && lastOk;
}

class _IdNames {
  const _IdNames({
    required this.lines,
    this.firstField,
    this.lastField,
  });

  final List<String> lines;
  final String? firstField;
  final String? lastField;
}

const _firstLabels = <String>[
  'FIRST NAME',
  'FIRSTNAME',
  'GIVEN NAME',
  'GIVENNAME',
  'GIVEN NAMES',
];

const _lastLabels = <String>[
  'LAST NAME',
  'LASTNAME',
  'SURNAME',
  'FAMILY NAME',
  'FAMILYNAME',
  'APELLIDO',
];

const _nameLabels = <String>[
  'STUDENT NAME',
  'NAME OF STUDENT',
  'FULL NAME',
  'FULLNAME',
  'CARD NAME',
  'NAME',
];

const _noise = <String>{
  'STUDENT',
  'SCHOOL',
  'UNIVERSITY',
  'COLLEGE',
  'INSTITUTE',
  'CAMPUS',
  'VALID',
  'UNTIL',
  'NUMBER',
  'NO',
  'ID',
  'CARD',
  'QRIDE',
  'PHILIPPINES',
  'REPUBLIC',
  'GOVERNMENT',
  'BIRTH',
  'BIRTHDATE',
  'BIRTHDAY',
  'DATE',
  'SEX',
  'MALE',
  'FEMALE',
  'ADDRESS',
  'COURSE',
  'YEAR',
  'SECTION',
  'GRADE',
};

String _norm(String raw) {
  var s = raw.trim().toUpperCase();
  s = s
      .replaceAll('Ñ', 'N')
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U');
  s = s.replaceAll(RegExp(r'[^A-Z]+'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> _parts(String name) {
  return name.split(' ').where((p) => p.length >= 2).toList();
}

Future<_IdNames> _readIdNames(String path) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final text = await recognizer.processImage(InputImage.fromFilePath(path));
    final lines = <String>[];
    String? commaFirst;
    String? commaLast;
    for (final block in text.blocks) {
      for (final line in block.lines) {
        final raw = line.text;
        final cut = raw.indexOf(',');
        if (cut > 1) {
          final left = _norm(raw.substring(0, cut));
          final right = _norm(raw.substring(cut + 1));
          if (_parts(left).isNotEmpty &&
              _parts(right).isNotEmpty &&
              left.split(' ').length <= 4 &&
              right.split(' ').length <= 4) {
            commaLast = left;
            commaFirst = right;
          }
        }
        final n = _norm(raw);
        if (n.isNotEmpty) lines.add(n);
      }
    }
    return _IdNames(
      lines: lines,
      firstField: _fieldAfter(lines, _firstLabels) ?? commaFirst,
      lastField: _fieldAfter(lines, _lastLabels) ?? commaLast,
    );
  } finally {
    await recognizer.close();
  }
}

String? _fieldAfter(List<String> lines, List<String> labels) {
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final label in labels) {
      if (line == label) {
        if (i + 1 < lines.length && !_isLabel(lines[i + 1])) {
          return lines[i + 1];
        }
        continue;
      }
      if (line.startsWith('$label ')) {
        final rest = line.substring(label.length).trim();
        if (rest.isNotEmpty && !_isLabel(rest)) return rest;
      }
    }
  }
  return null;
}

bool _isLabel(String line) {
  return _firstLabels.contains(line) ||
      _lastLabels.contains(line) ||
      _nameLabels.contains(line);
}

_NameCheck _matchFirstAndLast(
  _IdNames id, {
  required List<String> firstParts,
  required List<String> lastParts,
  required String firstLabel,
  required String lastLabel,
}) {
  if (firstParts.isEmpty || lastParts.isEmpty) {
    return _NameCheck(
      firstOk: firstParts.isNotEmpty,
      lastOk: lastParts.isNotEmpty,
      hint: 'Add your first and last name, then photograph your ID again.',
    );
  }

  final labeledFirst = id.firstField;
  final labeledLast = id.lastField;
  if (labeledFirst != null &&
      labeledLast != null &&
      _phraseIn(labeledFirst, lastParts) &&
      _phraseIn(labeledLast, firstParts) &&
      !_phraseIn(labeledFirst, firstParts) &&
      !_phraseIn(labeledLast, lastParts)) {
    return const _NameCheck(
      firstOk: false,
      lastOk: false,
      hint:
          'First name and last name look reversed. Put them in the same order as your ID.',
    );
  }

  final blob = id.lines.join(' ');
  final firstOk = labeledFirst != null
      ? _phraseIn(labeledFirst, firstParts)
      : _firstOnLines(id.lines, firstParts, avoid: labeledLast ?? '') ||
          _phraseIn(blob, firstParts);
  final lastOk = labeledLast != null
      ? _phraseIn(labeledLast, lastParts)
      : _lastOnLines(id.lines, lastParts, avoid: labeledFirst ?? '') ||
          _phraseIn(blob, lastParts);

  return _NameCheck(
    firstOk: firstOk,
    lastOk: lastOk,
    hint: _nameHint(
      firstOk: firstOk,
      lastOk: lastOk,
      firstLabel: firstLabel,
      lastLabel: lastLabel,
    ),
  );
}

String _nameHint({
  required bool firstOk,
  required bool lastOk,
  required String firstLabel,
  required String lastLabel,
}) {
  if (firstOk && lastOk) {
    return 'First and last name on the ID match.';
  }
  if (!firstOk && lastOk) {
    return 'The first name on the ID does not match $firstLabel.';
  }
  if (firstOk && !lastOk) {
    return 'The last name on the ID does not match $lastLabel.';
  }
  return 'The first name on the ID must be $firstLabel and the last name must be $lastLabel.';
}

List<String> _nameLines(List<String> lines) {
  final cleaned = <String>[];
  for (final raw in lines) {
    var line = raw;
    for (final label in [..._nameLabels, ..._firstLabels, ..._lastLabels]) {
      if (line == label) {
        line = '';
        break;
      }
      if (line.startsWith('$label ')) {
        line = line.substring(label.length).trim();
      }
    }
    line = line
        .split(' ')
        .where((t) => t.length >= 2 && !_noise.contains(t) && !RegExp(r'\d').hasMatch(t))
        .join(' ');
    if (line.isEmpty) continue;
    final tokens = line.split(' ');
    if (tokens.length > 7) continue;
    cleaned.add(line);
  }

  final out = [...cleaned];
  for (var i = 0; i < cleaned.length - 1; i++) {
    out.add('${cleaned[i]} ${cleaned[i + 1]}');
  }
  return out;
}

bool _phraseIn(String hay, List<String> parts) {
  if (parts.isEmpty) return false;
  final tokens = hay.split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.length < parts.length) return false;
  for (var i = 0; i <= tokens.length - parts.length; i++) {
    var ok = true;
    for (var j = 0; j < parts.length; j++) {
      if (tokens[i + j] != parts[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

bool _lastOnLines(List<String> lines, List<String> last, {required String avoid}) {
  for (final line in _nameLines(lines)) {
    if (line == avoid) continue;
    if (_phraseIn(line, last)) return true;
  }
  return _phraseIn(lines.join(' '), last);
}

bool _firstOnLines(List<String> lines, List<String> first, {required String avoid}) {
  for (final line in _nameLines(lines)) {
    if (line == avoid) continue;
    if (_phraseIn(line, first)) return true;
  }
  return _phraseIn(lines.join(' '), first);
}

/// A readable face: where it sits in the image at [path] and how it is turned.
class _FaceSig {
  const _FaceSig({
    required this.path,
    required this.warp,
    required this.yaw,
  });

  final String path;
  final FaceWarp warp;
  final double yaw;
}

class _LocatedFace {
  const _LocatedFace({
    required this.face,
    required this.path,
    required this.size,
    required this.sig,
    this.crop,
  });

  final Face face;
  final String path;
  final Size size;
  final _FaceSig? sig;

  /// Close crop around the printed face.
  final File? crop;
}

Future<_Check> _facesMatch(String idPath, String selfiePath) async {
  final extras = <File>[];
  File? liveCrop;
  try {
    final idFound = await _locatePrintedFace(idPath, extras);
    if (idFound == null) {
      return const _Check.unreadable(
        KycFaceStep.idPhoto,
        'Hold closer so the printed face on the ID is sharp and inside the frame.',
      );
    }

    final scan = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.08,
      ),
    );
    late final List<Face> liveFaces;
    try {
      liveFaces = await scan.processImage(InputImage.fromFilePath(selfiePath));
    } finally {
      await scan.close();
    }
    final liveSize = await _fileImageSize(selfiePath);
    final liveFace = _pickLiveFace(liveFaces, liveSize);
    if (liveFace == null) {
      return const _Check.unreadable(
        KycFaceStep.liveSelfie,
        'The live selfie must show your face looking at the camera.',
      );
    }

    liveCrop = await _cropFaceFile(selfiePath, liveFace.boundingBox, liveSize);
    final id = idFound.sig;
    var live = _faceSig(liveFace, selfiePath);
    if (liveCrop != null) {
      final closeup = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.12,
        ),
      );
      try {
        final closer = await closeup.processImage(
          InputImage.fromFilePath(liveCrop.path),
        );
        if (closer.isNotEmpty) {
          live = _faceSig(_largestFace(closer), liveCrop.path) ?? live;
        }
      } finally {
        await closeup.close();
      }
    }

    if (id == null) {
      return const _Check.unreadable(
        KycFaceStep.idPhoto,
        'The printed face on the ID is not clear enough. Hold closer and keep it sharp.',
      );
    }
    if (live == null) {
      return const _Check.unreadable(
        KycFaceStep.liveSelfie,
        'Could not read the live selfie. Look straight at the camera in good light.',
      );
    }
    if (live.yaw.abs() > 18) {
      return const _Check.unreadable(
        KycFaceStep.liveSelfie,
        'Look straight at the camera so your face lines up with the ID.',
      );
    }
    if (id.yaw.abs() > 32) {
      return const _Check.unreadable(
        KycFaceStep.idPhoto,
        'The ID photo must show a front-facing face.',
      );
    }

    final idFace = await _readOrNull(idFound.crop);
    final liveFaceCrop = await _readOrNull(liveCrop);
    final score = await _faceSimilarity(id, live);
    final verdict =
        score == null ? KycFaceVerdict.unsure : kycFaceVerdict(score);
    return _Check(
      ok: verdict != KycFaceVerdict.mismatch,
      verdict: verdict,
      score: score,
      idFace: idFace,
      liveFace: liveFaceCrop,
      hint: switch (verdict) {
        KycFaceVerdict.match =>
          'Your selfie matches the ID photo. Staff will do the final check.',
        KycFaceVerdict.unsure =>
          'Staff will compare your selfie with the ID photo.',
        KycFaceVerdict.mismatch =>
          'The live selfie does not match the face printed on the ID. Use your own ID, photograph it up close, and face the camera in good light.',
      },
    );
  } finally {
    try {
      await liveCrop?.delete();
      for (final extra in extras) {
        await extra.delete();
      }
    } catch (_) {}
  }
}

/// Null when the face model cannot run, so staff compare the photos instead.
Future<double?> _faceSimilarity(_FaceSig id, _FaceSig live) async {
  KycFaceEmbedder? embedder;
  try {
    embedder = await KycFaceEmbedder.open();
    final a = await _signatureOf(embedder, id);
    final b = await _signatureOf(embedder, live);
    return kycFaceSimilarity(a, b);
  } catch (e) {
    debugPrint('Face model could not run: $e');
    return null;
  } finally {
    embedder?.close();
  }
}

Future<Float32List> _signatureOf(KycFaceEmbedder embedder, _FaceSig sig) async {
  final image = await decodeFaceImage(sig.path);
  try {
    return await embedder.embed(image, sig.warp);
  } finally {
    image.dispose();
  }
}

Future<Uint8List?> _readOrNull(File? file) async {
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

Future<_LocatedFace?> _locatePrintedFace(
  String path,
  List<File> extras,
) async {
  final detector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.05,
    ),
  );
  final closeup = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      enableContours: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.12,
    ),
  );
  try {
    final first = await _readPrintedOn(
      detector: detector,
      closeup: closeup,
      file: File(path),
      extras: extras,
    );
    if (first?.sig != null) return first;

    _LocatedFace? best = first;
    final variants = await _idSearchImages(path, extras);
    for (final file in variants.skip(1)) {
      final found = await _readPrintedOn(
        detector: detector,
        closeup: closeup,
        file: file,
        extras: extras,
      );
      if (found == null) continue;
      if (found.sig != null) return found;
      best ??= found;
    }
    return best;
  } finally {
    await detector.close();
    await closeup.close();
  }
}

Future<_LocatedFace?> _readPrintedOn({
  required FaceDetector detector,
  required FaceDetector closeup,
  required File file,
  required List<File> extras,
}) async {
  final faces = await detector.processImage(InputImage.fromFilePath(file.path));
  if (faces.isEmpty) return null;
  final size = await _fileImageSize(file.path);
  final pick = _pickPrintedFace(faces, size);
  if (pick == null) return null;
  var sig = _faceSig(pick, file.path);
  final crop = await _cropFaceFile(file.path, pick.boundingBox, size);
  if (crop != null) {
    extras.add(crop);
    final closer = await closeup.processImage(InputImage.fromFilePath(crop.path));
    if (closer.isNotEmpty) {
      sig = _faceSig(_largestFace(closer), crop.path) ?? sig;
    }
  }
  return _LocatedFace(
    face: pick,
    path: file.path,
    size: size,
    sig: sig,
    crop: crop,
  );
}

Future<List<File>> _idSearchImages(String path, List<File> extras) async {
  final files = <File>[File(path)];
  final bytes = await File(path).readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final src = frame.image;
  try {
    final w = src.width.toDouble();
    final h = src.height.toDouble();
    final cards = <Rect>[
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.40),
        width: w * 0.88,
        height: math.min(h * 0.46, w * 0.88 / 1.5858 * 1.15),
      ),
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.42),
        width: math.min(w * 0.64, h * 0.54 / 1.5858),
        height: h * 0.54,
      ),
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.45),
        width: w * 0.96,
        height: h * 0.72,
      ),
    ];
    Future<void> add(Rect rect, double scale, int turns) async {
      final out = await _writeImageRect(
        src,
        srcRect: rect,
        scale: scale,
        quarterTurns: turns,
      );
      if (out != null) {
        extras.add(out);
        files.add(out);
      }
    }

    for (final rect in cards) {
      await add(rect, 1.8, 0);
    }
    for (final rect in cards) {
      await add(rect, 1.8, 1);
      await add(rect, 1.8, 3);
    }
  } finally {
    src.dispose();
  }
  return files;
}

Future<File?> _writeImageRect(
  Image src, {
  required Rect srcRect,
  required double scale,
  required int quarterTurns,
}) async {
  final left = srcRect.left.round().clamp(0, src.width - 2);
  final top = srcRect.top.round().clamp(0, src.height - 2);
  final right = srcRect.right.round().clamp(left + 2, src.width);
  final bottom = srcRect.bottom.round().clamp(top + 2, src.height);
  final sw = right - left;
  final sh = bottom - top;
  if (sw < 48 || sh < 48) return null;
  final destW = (sw * scale).round().clamp(80, 1600);
  final destH = (sh * scale).round().clamp(80, 1600);
  final outW = quarterTurns.isOdd ? destH : destW;
  final outH = quarterTurns.isOdd ? destW : destH;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(outW / 2, outH / 2);
  canvas.rotate(quarterTurns * math.pi / 2);
  canvas.drawImageRect(
    src,
    Rect.fromLTWH(left.toDouble(), top.toDouble(), sw.toDouble(), sh.toDouble()),
    Rect.fromCenter(
      center: Offset.zero,
      width: destW.toDouble(),
      height: destH.toDouble(),
    ),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(outW, outH);
  final data = await out.toByteData(format: ImageByteFormat.png);
  out.dispose();
  picture.dispose();
  if (data == null) return null;
  final file = File(
    '${Directory.systemTemp.path}/kyc_id_search_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file;
}

/// The main photo on the card. Cards with a small ghost copy of the photo
/// show the same face twice, and the ghost is too faint to match well.
Face? _pickPrintedFace(List<Face> faces, Size frame) {
  if (faces.isEmpty) return null;
  if (frame.width <= 0 || frame.height <= 0) return _largestFace(faces);
  final printed = faces.where((f) {
    final box = f.boundingBox;
    if (box.width < 14 || box.height < 16) return false;
    final fracH = box.height / frame.height;
    final fracW = box.width / frame.width;
    if (fracH < 0.03 || fracH > 0.62) return false;
    if (fracW < 0.02 || fracW > 0.55) return false;
    return true;
  }).toList();
  return _largestFace(printed.isNotEmpty ? printed : faces);
}

Face _largestFace(List<Face> faces) {
  return faces.reduce(
    (a, b) => b.boundingBox.height > a.boundingBox.height ? b : a,
  );
}

Face? _pickLiveFace(List<Face> faces, Size frame) {
  if (faces.isEmpty) return null;
  final usable = faces.where((f) {
    final box = f.boundingBox;
    if (frame.height <= 0) return box.height >= 48;
    return box.height / frame.height >= 0.16;
  }).toList();
  final pool = usable.isNotEmpty ? usable : faces;
  pool.sort((a, b) => b.boundingBox.height.compareTo(a.boundingBox.height));
  return pool.first;
}

/// Null unless both eyes, the nose, and the mouth were found. [path] is the
/// image the landmarks of [face] refer to.
_FaceSig? _faceSig(Face face, String path) {
  final box = face.boundingBox;
  if (box.width < 16 || box.height < 18) return null;
  Offset? at(FaceLandmarkType type) {
    final p = face.landmarks[type]?.position;
    return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
  }

  final left = at(FaceLandmarkType.leftEye);
  final right = at(FaceLandmarkType.rightEye);
  if (left == null || right == null || (left - right).distance < 8) {
    return null;
  }
  if (at(FaceLandmarkType.noseBase) == null ||
      at(FaceLandmarkType.bottomMouth) == null) {
    return null;
  }
  final warp = FaceWarp.forFace(
    eyeA: left,
    eyeB: right,
    mouthA: at(FaceLandmarkType.leftMouth),
    mouthB: at(FaceLandmarkType.rightMouth),
  );
  if (warp == null) return null;
  return _FaceSig(path: path, warp: warp, yaw: face.headEulerAngleY ?? 0);
}

Future<Size> _fileImageSize(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final size = Size(
    frame.image.width.toDouble(),
    frame.image.height.toDouble(),
  );
  frame.image.dispose();
  return size;
}

Future<File?> _cropFaceFile(String path, Rect box, Size frame) async {
  if (frame.width <= 0 || frame.height <= 0) return null;
  final bytes = await File(path).readAsBytes();
  final codec = await instantiateImageCodec(bytes);
  final frameImage = await codec.getNextFrame();
  final src = frameImage.image;
  final pad = box.inflate(math.max(box.width, box.height) * 0.45);
  final left = pad.left.round().clamp(0, src.width - 2);
  final top = pad.top.round().clamp(0, src.height - 2);
  final right = pad.right.round().clamp(left + 2, src.width);
  final bottom = pad.bottom.round().clamp(top + 2, src.height);
  final w = right - left;
  final h = bottom - top;
  if (w < 72 || h < 72) {
    src.dispose();
    return null;
  }
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    src,
    Rect.fromLTWH(left.toDouble(), top.toDouble(), w.toDouble(), h.toDouble()),
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint(),
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(w, h);
  final data = await out.toByteData(format: ImageByteFormat.png);
  src.dispose();
  out.dispose();
  picture.dispose();
  if (data == null) return null;
  final file = File(
    '${Directory.systemTemp.path}/kyc_face_crop_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file;
}
