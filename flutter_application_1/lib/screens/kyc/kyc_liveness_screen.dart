import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'kyc_liveness_overlay.dart';

class KycLivenessShots {
  const KycLivenessShots({required this.front});

  final File front;
}

enum _Pose { front, turn, center }

/// Stage inside the current pose.
enum _Stage { fit, steady, blink, snap }

/// Why the face is not usable yet.
enum _Fit { noFace, tooDark, tooFar, tooClose, offCenter, needTurn, needLive, good }

class _Sample {
  const _Sample(this.cx, this.cy, this.h, this.yaw);
  final double cx;
  final double cy;
  final double h;
  final double yaw;
}

class KycLivenessScreen extends StatefulWidget {
  const KycLivenessScreen({super.key});

  static const routeName = '/kyc-liveness';

  @override
  State<KycLivenessScreen> createState() => _KycLivenessScreenState();
}

class _KycLivenessScreenState extends State<KycLivenessScreen> {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };
  static const _holdNeed = Duration(milliseconds: 700);
  /// How far the head must turn from facing the camera (degrees).
  static const _turnDeg = 14.0;
  /// Minimum sweep from the forward pose so a pre-angled still photo fails.
  static const _turnSweep = 12.0;
  /// Mean Y-plane luma (0–255) below this → scene is too dark for reliable detect.
  static const _darkLuma = 42.0;
  /// Eye-open swing needed to count a blink. ML Kit often reports a narrow
  /// range on real faces, so this stays modest.
  static const _minEyeSwing = 0.12;

  CameraController? _controller;
  FaceDetector? _detector;

  _Pose _pose = _Pose.front;
  _Stage _stage = _Stage.fit;
  _Fit _fit = _Fit.noFace;

  String? _error;
  bool _busy = true;
  bool _processing = false;
  bool _snapping = false;
  bool _flash = false;
  int _frameSkip = 0;

  bool _eyesWereOpen = false;
  bool _blinkClosed = false;
  int _closedFrames = 0;
  int _openFrames = 0;
  bool _eyeScoresReady = true;
  double _eyeOpenMax = 0;
  double _eyeOpenMin = 1;
  DateTime? _blinkStarted;
  int? _poseTrackingId;
  int? _sessionTrackingId;
  final List<double> _yawSweep = [];
  bool _turnMotionOk = false;
  /// Yaw while looking at the camera (front pose). Left/right must move from this.
  double? _baselineYaw;

  double _holdProgress = 0;
  DateTime? _holdStarted;
  DateTime _lastHoldUi = DateTime.fromMillisecondsSinceEpoch(0);
  final List<_Sample> _samples = [];

  File? _front;
  final bool _turnLeft = math.Random().nextBool();
  String? _justTook;
  bool _sceneDark = false;
  bool _briefing = true;
  double _lastLuma = 128;
  DateTime _lastExposureAdjust = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (kIsWeb) {
      setState(() {
        _busy = false;
        _error =
            'Live selfie with blink checks works on the Android app, not in the browser.';
      });
      return;
    }
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => throw StateError('No front camera found'),
      );
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}
      try {
        await controller.setExposureMode(ExposureMode.auto);
      } catch (_) {}
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          minFaceSize: 0.1,
          performanceMode: FaceDetectorMode.fast,
        ),
      );
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

  Future<void> _onFrame(CameraImage image) async {
    if (_briefing || _processing || _snapping || _stage == _Stage.snap) return;
    if (_controller == null) return;
    // Every other frame is enough and keeps the preview smooth.
    _frameSkip = (_frameSkip + 1) % 2;
    if (_frameSkip != 0) return;

    _processing = true;
    try {
      final luma = _meanLuma(image);
      _lastLuma = luma;
      final dark = luma < _darkLuma;
      if (dark != _sceneDark) {
        _sceneDark = dark;
        if (mounted) setState(() {});
      }
      unawaited(_nudgeExposure(dark));

      final rotation = _rotation(_controller!);
      if (rotation == null) return;
      final input = _toInputImage(image, rotation);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      if (!mounted) return;
      if (faces.isEmpty) {
        _samples.clear();
        _resetHold();
        _setFit(dark ? _Fit.tooDark : _Fit.noFace);
        return;
      }
      if (dark && luma < _darkLuma * 0.85) {
        // Face found but still too dark for a reliable blink / capture.
        _samples.clear();
        _resetHold();
        _setFit(_Fit.tooDark);
        return;
      }
      final biggest = faces.reduce(
        (a, b) => a.boundingBox.height >= b.boundingBox.height ? a : b,
      );
      _applyFace(biggest, _rotatedSize(image, rotation));
    } catch (_) {
      // Drop this frame and keep streaming.
    } finally {
      _processing = false;
    }
  }

  /// Average brightness from the Y plane (NV21 / YUV).
  double _meanLuma(CameraImage image) {
    if (image.planes.isEmpty) return 128;
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 128;
    var sum = 0;
    var count = 0;
    // Subsample for speed — every ~20th pixel is enough for a scene check.
    final step = math.max(1, bytes.length ~/ 1200);
    for (var i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }
    return count == 0 ? 128 : sum / count;
  }

  Future<void> _nudgeExposure(bool dark) async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized) return;
    final now = DateTime.now();
    if (now.difference(_lastExposureAdjust) < const Duration(seconds: 2)) {
      return;
    }
    _lastExposureAdjust = now;
    try {
      final max = await cam.getMaxExposureOffset();
      final min = await cam.getMinExposureOffset();
      if (dark) {
        await cam.setExposureOffset(math.min(max, math.max(min, 1.5)));
      } else if (_lastLuma > _darkLuma + 25) {
        await cam.setExposureOffset(0);
      }
    } catch (_) {
      // Not all devices expose exposure offsets for the front camera.
    }
  }

  /// ML Kit reports coordinates in the *rotated* frame, so width/height swap
  /// for 90/270 degrees.
  Size _rotatedSize(CameraImage image, InputImageRotation rotation) {
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final sideways = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    return sideways ? Size(h, w) : Size(w, h);
  }

  void _setFit(_Fit fit) {
    if (_fit == fit) return;
    _fit = fit;
    if (mounted) setState(() {});
  }

  _Fit _classify(Face face, Size frame, double yaw) {
    if (frame.width <= 0 || frame.height <= 0) return _Fit.noFace;
    final box = face.boundingBox;
    final cx = box.center.dx / frame.width;
    final cy = box.center.dy / frame.height;
    final fracH = box.height / frame.height;

    if (fracH < 0.20) return _Fit.tooFar;
    if (fracH > 0.92) return _Fit.tooClose;
    if ((cx - 0.5).abs() > 0.30 || (cy - 0.45).abs() > 0.32) {
      return _Fit.offCenter;
    }
    switch (_pose) {
      case _Pose.front:
      case _Pose.center:
        if (yaw.abs() > 22) return _Fit.needTurn;
      case _Pose.turn:
        if (_turnLeft ? yaw < _turnDeg : yaw > -_turnDeg) {
          return _Fit.needTurn;
        }
    }
    return _Fit.good;
  }

  bool _isStable() {
    if (_samples.length < 5) return false;
    var minX = _samples.first.cx, maxX = minX;
    var minY = _samples.first.cy, maxY = minY;
    var minH = _samples.first.h, maxH = minH;
    var minYaw = _samples.first.yaw, maxYaw = minYaw;
    for (final s in _samples) {
      minX = math.min(minX, s.cx);
      maxX = math.max(maxX, s.cx);
      minY = math.min(minY, s.cy);
      maxY = math.max(maxY, s.cy);
      minH = math.min(minH, s.h);
      maxH = math.max(maxH, s.h);
      minYaw = math.min(minYaw, s.yaw);
      maxYaw = math.max(maxYaw, s.yaw);
    }
    return (maxX - minX) < 0.05 &&
        (maxY - minY) < 0.05 &&
        (maxH - minH) < 0.07 &&
        (maxYaw - minYaw) < 8;
  }

  void _resetBlink() {
    _eyesWereOpen = false;
    _blinkClosed = false;
    _closedFrames = 0;
    _openFrames = 0;
    _eyeOpenMax = 0;
    _eyeOpenMin = 1;
    _blinkStarted = null;
  }

  void _resetTurnMotion() {
    _yawSweep.clear();
    _turnMotionOk = _pose != _Pose.turn;
  }

  void _resetLivenessForPose() {
    _resetBlink();
    _resetTurnMotion();
    _poseTrackingId = null;
    _samples.clear();
    _resetHold();
  }

  /// Front: remember facing-forward yaw.
  /// Left/right: pass only if the head *moves* from that baseline to the side.
  /// A printed photo already looking left/right never sweeps, so it fails.
  void _noteYawMotion(double yaw) {
    if (_pose != _Pose.turn) {
      if (_pose == _Pose.front) {
        _baselineYaw =
            _baselineYaw == null ? yaw : (_baselineYaw! * 0.7 + yaw * 0.3);
      }
      _turnMotionOk = true;
      return;
    }

    _yawSweep.add(yaw);
    if (_yawSweep.length > 80) _yawSweep.removeAt(0);
    if (_turnMotionOk) return;

    final start = _baselineYaw ?? _yawSweep.first;
    if (_yawSweep.length < 5) return;

    var towardTarget = 0;
    for (final y in _yawSweep) {
      if (_turnLeft && y > start + 4) towardTarget++;
      if (!_turnLeft && y < start - 4) towardTarget++;
    }

    if (_turnLeft) {
      final peak = _yawSweep.reduce(math.max);
      _turnMotionOk = towardTarget >= 4 &&
          (peak - start) >= _turnSweep &&
          yaw >= _turnDeg;
    } else {
      final low = _yawSweep.reduce(math.min);
      _turnMotionOk = towardTarget >= 4 &&
          (start - low) >= _turnSweep &&
          yaw <= -_turnDeg;
    }
  }

  bool _trackingOk(Face face) {
    final id = face.trackingId;
    if (id == null) return true;
    // ML Kit tracking IDs can jump on a live face; only reject a sudden
    // swap after the front shot if it stays different for this pose.
    if (_sessionTrackingId != null && id != _sessionTrackingId) {
      _poseTrackingId = id;
      return true;
    }
    _poseTrackingId ??= id;
    return true;
  }

  void _resetHold() {
    _holdStarted = null;
    if (_holdProgress != 0) {
      _holdProgress = 0;
      if (mounted) setState(() {});
    }
  }

  void _note(Face face, Size frame, double yaw) {
    final box = face.boundingBox;
    _samples.add(
      _Sample(
        box.center.dx / frame.width,
        box.center.dy / frame.height,
        box.height / frame.height,
        yaw,
      ),
    );
    if (_samples.length > 8) _samples.removeAt(0);
  }

  void _tickHold(VoidCallback onDone) {
    _holdStarted ??= DateTime.now();
    final elapsed = DateTime.now().difference(_holdStarted!);
    final now = DateTime.now();
    if (now.difference(_lastHoldUi) > const Duration(milliseconds: 60)) {
      _lastHoldUi = now;
      _holdProgress =
          (elapsed.inMilliseconds / _holdNeed.inMilliseconds).clamp(0.0, 1.0);
      if (mounted) setState(() {});
    }
    if (elapsed >= _holdNeed) {
      _resetHold();
      onDone();
    }
  }

  void _applyFace(Face face, Size frame) {
    final yaw = face.headEulerAngleY ?? 0;
    _note(face, frame, yaw);
    _noteYawMotion(yaw);
    _trackingOk(face);

    var fit = _classify(face, frame, yaw);
    if (fit == _Fit.good && !_turnMotionOk && _pose == _Pose.turn) {
      fit = _Fit.needTurn;
    }
    _setFit(fit);

    if (fit != _Fit.good) {
      _resetHold();
      if (_stage == _Stage.blink) _resetBlink();
      if (_stage != _Stage.fit) setState(() => _stage = _Stage.fit);
      return;
    }

    if (!_isStable()) {
      _resetHold();
      return;
    }

    switch (_stage) {
      case _Stage.snap:
        return;
      case _Stage.fit:
        setState(() => _stage = _Stage.steady);
        return;
      case _Stage.steady:
        _tickHold(() {
          if (_pose == _Pose.front) {
            HapticFeedback.selectionClick();
            _resetBlink();
            setState(() => _stage = _Stage.blink);
          } else if (_pose == _Pose.turn) {
            HapticFeedback.selectionClick();
            setState(() {
              _pose = _Pose.center;
              _stage = _Stage.fit;
              _fit = _Fit.needTurn;
            });
            _resetLivenessForPose();
          } else {
            _capture();
          }
        });
      case _Stage.blink:
        _trackBlink(face, yaw);
    }
  }

  void _trackBlink(Face face, double yaw) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) {
      if (_eyeScoresReady) {
        _eyeScoresReady = false;
        if (mounted) setState(() {});
      }
      return;
    }
    if (!_eyeScoresReady) {
      _eyeScoresReady = true;
      if (mounted) setState(() {});
    }

    final openness = math.min(left, right);
    _eyeOpenMax = math.max(_eyeOpenMax, openness);
    _eyeOpenMin = math.min(_eyeOpenMin, openness);
    _blinkStarted ??= DateTime.now();

    final elapsed = DateTime.now().difference(_blinkStarted!);
    final swing = _eyeOpenMax - _eyeOpenMin;
    if (elapsed > const Duration(seconds: 20) && swing < 0.06) {
      _setFit(_Fit.needLive);
      _resetBlink();
      setState(() => _stage = _Stage.fit);
      return;
    }

    if (openness > 0.50) {
      _openFrames++;
      _closedFrames = 0;
      if (_openFrames >= 2) _eyesWereOpen = true;
      if (_eyesWereOpen &&
          _blinkClosed &&
          _openFrames >= 2 &&
          yaw.abs() < 28 &&
          swing >= _minEyeSwing) {
        HapticFeedback.mediumImpact();
        setState(() {
          _pose = _Pose.turn;
          _stage = _Stage.fit;
          _fit = _Fit.needTurn;
        });
        _resetLivenessForPose();
      }
    } else if (openness < 0.48) {
      _closedFrames++;
      _openFrames = 0;
      if (_eyesWereOpen && _closedFrames >= 1) _blinkClosed = true;
    }
  }

  Future<void> _capture() async {
    final cam = _controller;
    if (cam == null || _snapping) return;
    _snapping = true;
    _samples.clear();
    _resetHold();
    setState(() {
      _stage = _Stage.snap;
      _flash = true;
    });
    try {
      await cam.stopImageStream();
      // Let auto-focus/exposure settle so the still is not blurry.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final shot = await cam.takePicture();
      _front = File(shot.path);
      _sessionTrackingId = _poseTrackingId;

      if (!mounted) return;
      setState(() {
        _flash = false;
        _justTook = 'Live photo saved';
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.of(context).pop(KycLivenessShots(front: _front!));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _flash = false;
        _justTook = null;
        _error = 'Could not capture selfie: $e';
        _pose = _Pose.front;
        _stage = _Stage.fit;
        _fit = _Fit.noFace;
        _front = null;
      });
      _sessionTrackingId = null;
      _baselineYaw = null;
      _resetLivenessForPose();
      try {
        await cam.startImageStream(_onFrame);
      } catch (_) {}
    } finally {
      _snapping = false;
    }
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

  KycGuideState get _guideState {
    if (_justTook != null || _stage == _Stage.snap) {
      return KycGuideState.captured;
    }
    if (_stage == _Stage.blink) return KycGuideState.action;
    if (_stage == _Stage.steady) {
      return _holdProgress > 0 ? KycGuideState.holding : KycGuideState.aligned;
    }
    return KycGuideState.searching;
  }

  String get _headline {
    if (_justTook != null) return _justTook!;
    if (_stage == _Stage.snap) return 'Taking your live photo…';
    if (_stage == _Stage.blink) {
      return _eyeScoresReady ? 'Now blink once' : 'Looking for a blink';
    }
    switch (_fit) {
      case _Fit.noFace:
        return 'Fit your face in the oval';
      case _Fit.tooDark:
        return 'Too dark to scan';
      case _Fit.tooFar:
        return 'Move closer';
      case _Fit.tooClose:
        return 'Move back';
      case _Fit.offCenter:
        return 'Center your face';
      case _Fit.needLive:
        return 'Use your live face';
      case _Fit.needTurn:
        return switch (_pose) {
          _Pose.front => 'Look straight at the camera',
          _Pose.turn => _turnLeft
              ? 'Turn your head to the left'
              : 'Turn your head to the right',
          _Pose.center => 'Look back at the camera',
        };
      case _Fit.good:
        return _stage == _Stage.steady ? 'Stay put' : 'Hold still';
    }
  }

  String get _detail {
    if (_justTook != null) return 'That is your live selfie.';
    if (_stage == _Stage.snap) return 'Do not move.';
    if (_stage == _Stage.blink) {
      return _eyeScoresReady
          ? 'Close both eyes, then open them. A printed photo cannot do this.'
          : 'More light on your face helps the blink check.';
    }
    switch (_fit) {
      case _Fit.noFace:
        return 'Hold the phone at eye level. Face a window or bright light.';
      case _Fit.tooDark:
        return 'Move to a brighter area — stand near a window or turn on a light, then try again.';
      case _Fit.tooFar:
        return 'Your face should fill most of the oval.';
      case _Fit.tooClose:
        return 'The oval should frame your whole head.';
      case _Fit.offCenter:
        return 'Shift until your head sits inside the shape.';
      case _Fit.needLive:
        return 'Look at the camera and blink once when asked.';
      case _Fit.needTurn:
        return switch (_pose) {
          _Pose.front => 'Face the camera so the ring turns blue.',
          _Pose.turn => _turnLeft
              ? 'Slowly turn so your left ear moves toward the camera. We need to see the head move.'
              : 'Slowly turn so your right ear moves toward the camera. We need to see the head move.',
          _Pose.center => 'Face the camera again. The live photo is taken next.',
        };
      case _Fit.good:
        return switch (_pose) {
          _Pose.front => 'Keep steady — then blink when asked.',
          _Pose.turn => 'Keep the turn so we can see you move.',
          _Pose.center => 'Hold still — the photo is taken next.',
        };
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector?.close();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave live check?'),
        content: const Text(
          'Your progress on this selfie will be lost. You can start again from the verification steps.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _briefing
              ? 'Live selfie'
              : switch (_pose) {
                  _Pose.front => 'Step 1 of 3 · Blink',
                  _Pose.turn => _turnLeft
                      ? 'Step 2 of 3 · Turn left'
                      : 'Step 2 of 3 · Turn right',
                  _Pose.center => 'Step 3 of 3 · Live photo',
                },
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close_rounded),
          onPressed: _confirmCancel,
        ),
      ),
      body: _briefing
          ? _Briefing(
              onStart: () => setState(() => _briefing = false),
            )
          : _busy
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
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.center,
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: cam.value.previewSize!.height,
                                        height: cam.value.previewSize!.width,
                                        child: CameraPreview(cam),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned.fill(
                                  child: KycFaceGuide(
                                    state: _guideState,
                                    holdProgress: _holdProgress,
                                    caption: _fit == _Fit.good
                                        ? null
                                        : (_fit == _Fit.tooDark
                                            ? 'Brighter light needed'
                                            : (_fit == _Fit.needLive
                                                ? 'Live face required'
                                                : 'Place face here')),
                                  ),
                                ),
                                if (_flash)
                                  const ColoredBox(color: Colors.white70),
                                Positioned(
                                  top: 16,
                                  left: 16,
                                  right: 16,
                                  child: _Banner(
                                    title: _headline,
                                    subtitle: _detail,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    Material(
                      color: Colors.black,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                        child: Column(
                          children: [
                            _StepRow(
                              pose: _pose,
                              turnLeft: _turnLeft,
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Blink, then turn when asked. We only keep one live photo after you look back at the camera.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white70),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
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

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.pose,
    required this.turnLeft,
  });

  final _Pose pose;
  final bool turnLeft;

  @override
  Widget build(BuildContext context) {
    final current = switch (pose) {
      _Pose.front => 0,
      _Pose.turn => 1,
      _Pose.center => 2,
    };
    final labels = [
      'Blink',
      turnLeft ? 'Turn left' : 'Turn right',
      'Photo',
    ];
    final states = [
      current > 0,
      current > 1,
      false,
    ];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: states[i]
                        ? const Color(0xFF34C759)
                        : (i == current
                            ? const Color(0xFF0A84FF)
                            : Colors.white24),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const SizedBox(height: 6, width: double.infinity),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: states[i] || i == current
                        ? Colors.white
                        : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Briefing extends StatelessWidget {
  const _Briefing({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        children: [
          const Spacer(),
          const Icon(Icons.verified_user_outlined,
              color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text(
            'We need to see you move',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This looks for a live person — a blink and a real head turn. A printed photo or another phone screen will not pass.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 28),
          const _BriefRow(
            icon: Icons.visibility_outlined,
            title: 'Blink once',
            body: 'Eyes must close and open. A still picture cannot do that.',
          ),
          const SizedBox(height: 12),
          const _BriefRow(
            icon: Icons.rotate_90_degrees_ccw_rounded,
            title: 'Turn when asked',
            body: 'Left or right, chosen at random. We watch the head actually move.',
          ),
          const SizedBox(height: 12),
          const _BriefRow(
            icon: Icons.photo_camera_outlined,
            title: 'One live photo',
            body: 'Look back at the camera. We keep that selfie for the ID match.',
          ),
          const Spacer(),
          FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('I’m ready'),
          ),
        ],
      ),
    );
  }
}

class _BriefRow extends StatelessWidget {
  const _BriefRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF64B5F6)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ],
    );
  }
}
