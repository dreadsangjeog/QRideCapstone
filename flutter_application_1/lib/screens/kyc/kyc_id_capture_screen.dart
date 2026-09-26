import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../services/kyc_auto_match.dart';
import 'kyc_id_match_panel.dart';
import 'kyc_id_overlay.dart';
import 'kyc_id_quality.dart';

/// Rear-camera ID capture. The shutter fires when the printed face
/// and name are readable — edges do not need a perfect lock.
class KycIdCaptureScreen extends StatefulWidget {
  const KycIdCaptureScreen({
    super.key,
    required this.firstName,
    required this.lastName,
  });

  final String firstName;
  final String lastName;

  @override
  State<KycIdCaptureScreen> createState() => _KycIdCaptureScreenState();
}

class _KycIdCaptureScreenState extends State<KycIdCaptureScreen> {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  static const _lockNeed = Duration(milliseconds: 800);
  static const _onThresh = 16.0;
  static const _offThresh = 9.0;
  static const _darkLuma = 38.0;

  CameraController? _controller;
  FaceDetector? _faces;
  TextRecognizer? _text;
  Size? _viewSize;

  bool _busy = true;
  bool _processing = false;
  bool _snapping = false;
  bool _reviewing = false;
  bool _flash = false;
  int _tick = 0;
  String? _error;
  String? _reject;

  KycIdEdges _edges = const KycIdEdges();
  KycIdChecks _checks = const KycIdChecks();
  DateTime? _readySince;
  double _hold = 0;
  bool _tooDark = false;
  bool _glare = false;
  DateTime _lastUi = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTextAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFaceAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _portrait = false;
  bool _readable = false;
  KycIdLayout _layout = KycIdLayout.horizontal;
  bool _layoutPinned = false;
  int _layoutVotes = 0;
  Uint8List? _matchPhoto;
  Future<KycIdMatchOutcome>? _matchWork;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (kIsWeb) {
      setState(() {
        _busy = false;
        _error = 'ID capture with the alignment frame works on the Android app.';
      });
      return;
    }
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      final cameras = await availableCameras();
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      _faces = FaceDetector(
        options: FaceDetectorOptions(
          enableTracking: true,
          minFaceSize: 0.03,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );
      _text = TextRecognizer(script: TextRecognitionScript.latin);
      _controller = controller;
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Rect _cardRect(Size view, [KycIdLayout? layout]) {
    return KycIdGuide.cardOn(view, layout: layout ?? _layout);
  }

  void _setLayout(KycIdLayout next, {required bool pinned}) {
    if (_layout == next && _layoutPinned == pinned) return;
    _layout = next;
    _layoutPinned = pinned;
    _layoutVotes = 0;
    _edges = const KycIdEdges();
    _readySince = null;
    _hold = 0;
    if (mounted) setState(() {});
  }

  void _maybeFlipLayout(CameraImage image, Size view, Size preview) {
    if (_layoutPinned || _snapping || _reviewing || _hold > 0) return;
    final other = _layout == KycIdLayout.horizontal
        ? KycIdLayout.vertical
        : KycIdLayout.horizontal;
    final cur = _edgeMean(image, view, preview, _layout);
    final alt = _edgeMean(image, view, preview, other);
    if (alt > cur * 1.22 && alt > 24) {
      _layoutVotes++;
      if (_layoutVotes >= 4) {
        _setLayout(other, pinned: false);
      }
    } else {
      _layoutVotes = 0;
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _snapping || _reviewing || _matchPhoto != null) return;
    _tick++;
    if (_tick % 2 != 0) return;
    final view = _viewSize;
    final cam = _controller;
    if (view == null || cam == null || !cam.value.isInitialized) return;
    final preview = cam.value.previewSize;
    if (preview == null) return;

    _processing = true;
    try {
      _maybeFlipLayout(image, view, preview);

      final cardStats = _cardStats(image, view, preview);
      final dark = cardStats.mean < _darkLuma;
      final glare = cardStats.hotFrac > 0.14;
      final edges = dark
          ? const KycIdEdges()
          : _detectEdges(image, view, preview);
      final sharp = !dark && cardStats.contrast >= 10;
      final inView = !dark &&
          (edges.count >= 2 || cardStats.contrast >= 12);
      final framed = inView && !glare;

      if (!dark && _tick % 4 == 0) {
        await _readFace(image, view, preview);
      }
      if (!dark && _tick % 6 == 0) {
        await _readText(image);
      }

      final now = DateTime.now();
      final portraitFresh =
          now.difference(_lastFaceAt) < const Duration(milliseconds: 2800);
      final textFresh =
          now.difference(_lastTextAt) < const Duration(milliseconds: 2400);
      final portrait = _portrait && portraitFresh;
      final readable = _readable && textFresh;

      final checks = KycIdChecks(
        frame: framed,
        portrait: portrait,
        text: readable,
        sharp: sharp,
      );
      final shownEdges = checks.ready
          ? const KycIdEdges(
              top: true,
              right: true,
              bottom: true,
              left: true,
            )
          : KycIdEdges(
              top: edges.top || framed,
              right: edges.right || framed,
              bottom: edges.bottom || framed,
              left: edges.left || framed,
            );

      if (checks.ready) {
        _readySince ??= now;
        _hold = (now.difference(_readySince!).inMilliseconds /
                _lockNeed.inMilliseconds)
            .clamp(0.0, 1.0);
        if (now.difference(_readySince!) >= _lockNeed) {
          await _capture();
          return;
        }
      } else {
        _readySince = null;
        _hold = 0;
      }

      if (now.difference(_lastUi) > const Duration(milliseconds: 80)) {
        _lastUi = now;
        if (mounted) {
          setState(() {
            _edges = shownEdges;
            _checks = checks;
            _tooDark = dark;
            _glare = glare;
            if (checks.ready) _reject = null;
          });
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _readFace(
    CameraImage image,
    Size view,
    Size preview,
  ) async {
    final detector = _faces;
    final cam = _controller;
    if (detector == null || cam == null) return;
    final rotation = _rotation(cam);
    if (rotation == null) return;
    final input = _toInputImage(image, rotation);
    if (input == null) return;
    final faces = await detector.processImage(input);
    final original = Size(image.width.toDouble(), image.height.toDouble());
    final rotated = _rotatedImageSize(image, rotation);
    final card = _cardInRotatedSpace(view, preview, image, rotation);
    final cardOrig = _cardInImageSpace(view, preview, image);

    Face? pick(Size frame, Rect guide) {
      final printed = faces.where((f) => _isPrintedIdFace(f, frame)).toList();
      if (printed.isEmpty) return null;
      if (guide.width > 8 && guide.height > 8) {
        final inside = printed.where((f) {
          return guide.inflate(guide.shortestSide * 0.12).contains(f.boundingBox.center);
        }).toList();
        if (inside.isNotEmpty) {
          inside.sort(
            (a, b) => a.boundingBox.height.compareTo(b.boundingBox.height),
          );
          return inside.first;
        }
      }
      printed.sort(
        (a, b) => a.boundingBox.height.compareTo(b.boundingBox.height),
      );
      return printed.first;
    }

    _portrait =
        pick(rotated, card) != null || pick(original, cardOrig) != null;
    _lastFaceAt = DateTime.now();
  }

  Size _rotatedImageSize(CameraImage image, InputImageRotation rotation) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final sideways = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    return sideways ? Size(h, w) : Size(w, h);
  }

  Rect _cardInImageSpace(Size view, Size preview, CameraImage image) {
    final card = _cardRect(view);
    final pts = [
      card.topLeft,
      card.topRight,
      card.bottomLeft,
      card.bottomRight,
    ]
        .map((p) => _screenToImage(p, view, preview, image.width, image.height))
        .whereType<Offset>()
        .toList();
    if (pts.length < 4) return Rect.zero;
    final xs = pts.map((p) => p.dx);
    final ys = pts.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  /// Printed ID portraits are small. A live face filling the camera is not.
  bool _isPrintedIdFace(Face face, Size frame) {
    if (frame.width <= 0 || frame.height <= 0) return false;
    final box = face.boundingBox;
    if (box.width < 24 || box.height < 28) return false;
    final fracH = box.height / frame.height;
    final fracW = box.width / frame.width;
    if (fracH < 0.045 || fracH > 0.58) return false;
    if (fracW < 0.03 || fracW > 0.50) return false;
    return true;
  }

  Future<void> _readText(CameraImage image) async {
    final recognizer = _text;
    final cam = _controller;
    if (recognizer == null || cam == null) return;
    final rotation = _rotation(cam);
    if (rotation == null) return;
    final input = _toInputImage(image, rotation);
    if (input == null) return;
    final result = await recognizer.processImage(input);
    _readable = KycIdQuality.looksLikeReadableText(result.text);
    _lastTextAt = DateTime.now();
  }

  Rect _cardInRotatedSpace(
    Size view,
    Size preview,
    CameraImage image,
    InputImageRotation rotation,
  ) {
    final card = _cardRect(view);
    final pts = [
      card.topLeft,
      card.topRight,
      card.bottomLeft,
      card.bottomRight,
    ]
        .map((p) => _screenToImage(p, view, preview, image.width, image.height))
        .whereType<Offset>()
        .map((p) => _toRotated(p, image.width, image.height, rotation))
        .toList();
    if (pts.length < 4) return Rect.zero;
    final xs = pts.map((p) => p.dx);
    final ys = pts.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  Offset _toRotated(
    Offset img,
    int w,
    int h,
    InputImageRotation rotation,
  ) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Offset(img.dy, w - 1 - img.dx);
      case InputImageRotation.rotation270deg:
        return Offset(h - 1 - img.dy, img.dx);
      case InputImageRotation.rotation180deg:
        return Offset(w - 1 - img.dx, h - 1 - img.dy);
      case InputImageRotation.rotation0deg:
        return img;
    }
  }

  _CardStats _cardStats(CameraImage image, Size view, Size preview) {
    final card = _cardRect(view);
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final imgW = image.width;
    final imgH = image.height;
    final inner = card.deflate(18);

    int? lumaAt(Offset screen) {
      final img = _screenToImage(screen, view, preview, imgW, imgH);
      if (img == null) return null;
      final x = img.dx.round().clamp(0, imgW - 1);
      final y = img.dy.round().clamp(0, imgH - 1);
      final i = y * stride + x;
      if (i < 0 || i >= bytes.length) return null;
      return bytes[i];
    }

    var sum = 0;
    var hot = 0;
    var n = 0;
    final samples = <int>[];
    for (var y = 0; y < 10; y++) {
      for (var x = 0; x < 16; x++) {
        final p = Offset(
          ui.lerpDouble(inner.left, inner.right, x / 15)!,
          ui.lerpDouble(inner.top, inner.bottom, y / 9)!,
        );
        final yv = lumaAt(p);
        if (yv == null) continue;
        samples.add(yv);
        sum += yv;
        if (yv > 246) hot++;
        n++;
      }
    }
    final mean = n == 0 ? 128.0 : sum / n;
    var varSum = 0.0;
    for (final yv in samples) {
      final d = yv - mean;
      varSum += d * d;
    }
    final contrast = n == 0 ? 0.0 : math.sqrt(varSum / n);

    var lap = 0.0;
    var ln = 0;
    for (var y = 1; y < 9; y++) {
      for (var x = 1; x < 15; x++) {
        int? at(int xx, int yy) {
          final p = Offset(
            ui.lerpDouble(inner.left, inner.right, xx / 15)!,
            ui.lerpDouble(inner.top, inner.bottom, yy / 9)!,
          );
          return lumaAt(p);
        }

        final c = at(x, y);
        final l = at(x - 1, y);
        final r = at(x + 1, y);
        final u = at(x, y - 1);
        final d = at(x, y + 1);
        if (c == null || l == null || r == null || u == null || d == null) {
          continue;
        }
        lap += (4 * c - l - r - u - d).abs();
        ln++;
      }
    }

    return _CardStats(
      mean: mean,
      contrast: contrast,
      sharpness: ln == 0 ? 0 : lap / ln,
      hotFrac: n == 0 ? 0 : hot / n,
    );
  }

  double _edgeMean(
    CameraImage image,
    Size view,
    Size preview,
    KycIdLayout layout,
  ) {
    final scores = _edgeScores(image, view, preview, layout);
    return (scores[0] + scores[1] + scores[2] + scores[3]) / 4;
  }

  List<double> _edgeScores(
    CameraImage image,
    Size view,
    Size preview,
    KycIdLayout layout,
  ) {
    final card = _cardRect(view, layout);
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final imgW = image.width;
    final imgH = image.height;

    int? lumaAt(Offset screen) {
      final img = _screenToImage(screen, view, preview, imgW, imgH);
      if (img == null) return null;
      final x = img.dx.round().clamp(0, imgW - 1);
      final y = img.dy.round().clamp(0, imgH - 1);
      final i = y * stride + x;
      if (i < 0 || i >= bytes.length) return null;
      return bytes[i];
    }

    double edgeScore({
      required Offset Function(double t) along,
      required Offset Function(Offset p) inward,
      required Offset Function(Offset p) outward,
    }) {
      var sum = 0.0;
      var n = 0;
      for (var i = 2; i <= 13; i++) {
        final t = i / 15;
        final p = along(t);
        final a = lumaAt(inward(p));
        final b = lumaAt(outward(p));
        if (a == null || b == null) continue;
        sum += (a - b).abs();
        n++;
      }
      return n == 0 ? 0 : sum / n;
    }

    const step = 14.0;
    return [
      edgeScore(
        along: (t) => Offset(
          ui.lerpDouble(card.left + 18, card.right - 18, t)!,
          card.top,
        ),
        inward: (p) => p.translate(0, step),
        outward: (p) => p.translate(0, -step),
      ),
      edgeScore(
        along: (t) => Offset(
          card.right,
          ui.lerpDouble(card.top + 18, card.bottom - 18, t)!,
        ),
        inward: (p) => p.translate(-step, 0),
        outward: (p) => p.translate(step, 0),
      ),
      edgeScore(
        along: (t) => Offset(
          ui.lerpDouble(card.left + 18, card.right - 18, t)!,
          card.bottom,
        ),
        inward: (p) => p.translate(0, -step),
        outward: (p) => p.translate(0, step),
      ),
      edgeScore(
        along: (t) => Offset(
          card.left,
          ui.lerpDouble(card.top + 18, card.bottom - 18, t)!,
        ),
        inward: (p) => p.translate(step, 0),
        outward: (p) => p.translate(-step, 0),
      ),
    ];
  }

  KycIdEdges _detectEdges(CameraImage image, Size view, Size preview) {
    final scores = _edgeScores(image, view, preview, _layout);
    final top = scores[0];
    final right = scores[1];
    final bottom = scores[2];
    final left = scores[3];

    bool lock(double score, bool was) {
      if (was) return score >= _offThresh;
      return score >= _onThresh;
    }

    return KycIdEdges(
      top: lock(top, _edges.top),
      right: lock(right, _edges.right),
      bottom: lock(bottom, _edges.bottom),
      left: lock(left, _edges.left),
    );
  }

  Offset? _screenToImage(
    Offset screen,
    Size view,
    Size preview,
    int imgW,
    int imgH,
  ) {
    final box = Size(preview.height, preview.width);
    final scale = math.max(view.width / box.width, view.height / box.height);
    final disp = Size(box.width * scale, box.height * scale);
    final origin = Offset(
      (disp.width - view.width) / 2,
      (disp.height - view.height) / 2,
    );
    final inBox = (screen + origin) / scale;
    if (inBox.dx < 0 ||
        inBox.dy < 0 ||
        inBox.dx > box.width ||
        inBox.dy > box.height) {
      return null;
    }
    return Offset(
      inBox.dy / box.height * imgW,
      inBox.dx / box.width * imgH,
    );
  }

  Future<void> _capture() async {
    final cam = _controller;
    if (cam == null || _snapping) return;
    _snapping = true;
    if (mounted) {
      setState(() {
        _flash = true;
        _hold = 1;
        _reviewing = true;
        _reject = null;
      });
    }
    try {
      if (cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }
      await Future<void>.delayed(const Duration(milliseconds: 220));
      final shot = await cam.takePicture();
      final bytes = await File(shot.path).readAsBytes();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _flash = false;
        _matchPhoto = bytes;
        _matchWork = _reviewCaptured(bytes);
      });
    } catch (e) {
      await _resumeAfterFail('Could not capture the ID. Try again.');
    }
  }

  Future<KycIdMatchOutcome> _reviewCaptured(Uint8List bytes) async {
    final quality = await KycIdQuality.reviewStill(bytes);
    final name = await KycAutoMatch.reviewNameOnId(
      idBytes: bytes,
      firstName: widget.firstName,
      lastName: widget.lastName,
    );
    final face = await KycAutoMatch.probeIdFace(idBytes: bytes);
    final faceOk = face.photoMatch;
    final nameOk = name.nameMatch;
    final ok = quality.hasText && !quality.tooDark && nameOk && faceOk;
    final hint = quality.tooDark
        ? quality.hint
        : !quality.hasText
            ? quality.hint
            : !faceOk
                ? face.note
                : !nameOk
                    ? name.note
                    : 'First name, last name, and ID photo look good.';
    return KycIdMatchOutcome(
      ok: ok,
      nameOk: nameOk,
      firstOk: name.firstNameMatch,
      lastOk: name.lastNameMatch,
      faceOk: faceOk,
      hint: hint,
    );
  }

  Future<void> _onMatchFinished(KycIdMatchOutcome result) async {
    if (!mounted) return;
    if (result.ok && _matchPhoto != null) {
      Navigator.of(context).pop<Uint8List>(_matchPhoto);
      return;
    }
    HapticFeedback.heavyImpact();
    await _resumeAfterFail(result.hint);
  }

  Future<void> _resumeAfterFail(String message) async {
    _snapping = false;
    _readySince = null;
    _hold = 0;
    _portrait = false;
    _readable = false;
    _matchPhoto = null;
    _matchWork = null;
    if (mounted) {
      setState(() {
        _flash = false;
        _reviewing = false;
        _reject = message;
        _checks = const KycIdChecks();
      });
    }
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      if (!cam.value.isStreamingImages) {
        await cam.startImageStream(_onFrame);
      }
    } catch (_) {}
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
    if (Platform.isAndroid) {
      final builder = BytesBuilder(copy: false);
      for (final plane in image.planes) {
        builder.add(plane.bytes);
      }
      return InputImage.fromBytes(
        bytes: builder.toBytes(),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }
    if (Platform.isIOS) {
      final plane = image.planes.first;
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }
    return null;
  }

  InputImageRotation? _rotation(CameraController cam) {
    final camera = cam.description;
    final sensor = camera.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensor);
    }
    final compensation = _orientations[cam.value.deviceOrientation];
    if (compensation == null) {
      return InputImageRotationValue.fromRawValue(sensor);
    }
    final degrees = camera.lensDirection == CameraLensDirection.front
        ? (sensor + compensation) % 360
        : (sensor - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(degrees);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faces?.close();
    _text?.close();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  String get _title {
    if (_matchPhoto != null) return 'Matching your ID';
    if (_reviewing) return 'Taking the photo…';
    if (_flash) return 'Capturing…';
    if (_tooDark) return 'Too dark';
    if (_glare) return 'Glare on the card';
    if (_checks.ready) return 'Looks good';
    if (!_checks.frame) return 'Fit the ID in the frame';
    if (!_checks.portrait) return 'Looking for the ID photo';
    if (!_checks.text) return 'Reading the name on the ID';
    return 'Need a sharper photo';
  }

  String get _detail {
    if (_matchPhoto != null) {
      return 'Reading the printed name and photo.';
    }
    if (_reviewing) {
      return 'Keep the card in view.';
    }
    if (_reject != null) return _reject!;
    if (_flash) return 'Keep the card steady.';
    if (_tooDark) return 'Move to a brighter spot so the name can be read.';
    if (_glare) return 'Tilt the card a little so the light is not bouncing.';
    if (_checks.ready) {
      return 'The important details look readable. The photo is taken next.';
    }
    if (!_checks.frame) {
      return _layout == KycIdLayout.vertical
          ? 'Hold the ID upright in the frame. A little shake is fine.'
          : 'Hold the ID in the frame. A little shake is fine — edges do not need to be perfect.';
    }
    if (!_checks.portrait) {
      return 'Move closer until the printed face on the ID is large, sharp, and fully visible.';
    }
    if (!_checks.text) {
      return 'Hold closer until the name on the ID is sharp enough to read.';
    }
    return 'Hold still. The camera is waiting for a clear picture.';
  }

  @override
  Widget build(BuildContext context) {
    final cam = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Photograph your ID'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _error != null && cam == null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: cam == null || !cam.value.isInitialized
                          ? const Center(
                              child: Text(
                                'Starting camera…',
                                style: TextStyle(color: Colors.white),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                _viewSize = constraints.biggest;
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.center,
                                        child: FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width:
                                                cam.value.previewSize!.height,
                                            height:
                                                cam.value.previewSize!.width,
                                            child: CameraPreview(cam),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (_matchPhoto == null)
                                      Positioned.fill(
                                        child: KycIdFrame(
                                          edges: _edges,
                                          holdProgress: _hold,
                                          layout: _layout,
                                          locked: _flash || _reviewing,
                                        ),
                                      ),
                                    if (_flash)
                                      const ColoredBox(color: Colors.white70),
                                    if (_reviewing && _matchPhoto == null)
                                      const ColoredBox(
                                        color: Color(0x66000000),
                                      ),
                                    if (_matchPhoto != null && _matchWork != null)
                                      Positioned.fill(
                                        child: KycIdMatchPanel(
                                          photo: _matchPhoto!,
                                          firstName: widget.firstName,
                                          lastName: widget.lastName,
                                          work: _matchWork!,
                                          onFinished: _onMatchFinished,
                                        ),
                                      ),
                                    if (_matchPhoto == null)
                                      Positioned(
                                        top: 16,
                                        left: 16,
                                        right: 16,
                                        child: _IdBanner(
                                          title: _title,
                                          subtitle: _detail,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                    ),
                    Material(
                      color: Colors.black,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                        child: Column(
                          children: [
                            if (_matchPhoto == null) ...[
                              _LayoutToggle(
                                layout: _layout,
                                onChanged: (next) {
                                  if (_snapping || _reviewing) return;
                                  _setLayout(next, pinned: true);
                                },
                              ),
                              const SizedBox(height: 12),
                              _QualityRow(checks: _checks),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              _matchPhoto == null
                                  ? 'Use a physical school or government ID. Edges do not need to line up perfectly — the printed face and name just need to be readable.'
                                  : 'Checking the printed name and photo against your account.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70,
                                height: 1.35,
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CardStats {
  const _CardStats({
    required this.mean,
    required this.contrast,
    required this.sharpness,
    required this.hotFrac,
  });

  final double mean;
  final double contrast;
  final double sharpness;
  final double hotFrac;
}

class _IdBanner extends StatelessWidget {
  const _IdBanner({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.66),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({
    required this.layout,
    required this.onChanged,
  });

  final KycIdLayout layout;
  final ValueChanged<KycIdLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _chip(
              selected: layout == KycIdLayout.horizontal,
              icon: Icons.crop_landscape_rounded,
              label: 'Horizontal',
              onTap: () => onChanged(KycIdLayout.horizontal),
            ),
            _chip(
              selected: layout == KycIdLayout.vertical,
              icon: Icons.crop_portrait_rounded,
              label: 'Vertical',
              onTap: () => onChanged(KycIdLayout.vertical),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? Colors.black : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.checks});

  final KycIdChecks checks;

  @override
  Widget build(BuildContext context) {
    final items = [
      (checks.frame, 'In view'),
      (checks.portrait, 'ID photo'),
      (checks.text, 'Readable'),
      (checks.sharp, 'Clear'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _QualityChip(on: items[i].$1, label: items[i].$2),
          ),
        ],
      ],
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.on, required this.label});

  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: on ? const Color(0xFF0A84FF) : const Color(0x22FFFFFF),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: on ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
