import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'kyc_face_math.dart';

/// Turns a face into a signature that is close for photos of the same person.
///
/// Model: MobileFaceNet, MIT licence, see assets/models/MOBILEFACENET_LICENSE.txt.
/// Android app only; the web build never imports this file.
class KycFaceEmbedder {
  KycFaceEmbedder._(this._interpreter);

  static const asset = 'assets/models/mobilefacenet.tflite';

  final Interpreter _interpreter;

  static Future<KycFaceEmbedder> open() async {
    final options = InterpreterOptions()..threads = 2;
    try {
      final interpreter = await Interpreter.fromAsset(asset, options: options);
      final input = interpreter.getInputTensor(0).shape;
      final output = interpreter.getOutputTensor(0).shape;
      if (input.length != 4 ||
          input[0] != 2 ||
          input[1] != kycFaceSize ||
          input[2] != kycFaceSize ||
          input[3] != 3 ||
          output.length != 2 ||
          output[0] != 2) {
        interpreter.close();
        throw StateError('Unexpected face model shape $input -> $output.');
      }
      return KycFaceEmbedder._(interpreter);
    } finally {
      options.delete();
    }
  }

  /// Signature of the face in [image] whose landmarks gave [warp].
  Future<Float32List> embed(Image image, FaceWarp warp) async {
    final rgba = await kycAlignedFace(image, warp);
    _interpreter.getInputTensor(0).data = kycFaceInput(rgba).buffer.asUint8List();
    _interpreter.invoke();
    final raw = _interpreter.getOutputTensor(0).data;
    return kycMergeMirrored(
      Float32List.fromList(
        raw.buffer.asFloat32List(raw.offsetInBytes, raw.lengthInBytes ~/ 4),
      ),
    );
  }

  void close() => _interpreter.close();
}

Future<Image> decodeFaceImage(String path) async {
  final codec = await instantiateImageCodec(await File(path).readAsBytes());
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// The face in [src] redrawn at [kycFaceSize] x [kycFaceSize] on the model's
/// template, as RGBA bytes.
Future<Uint8List> kycAlignedFace(Image src, FaceWarp warp) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFF808080), BlendMode.src);
  canvas.transform(warp.matrix4);
  canvas.drawImage(
    src,
    Offset.zero,
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(kycFaceSize, kycFaceSize);
  try {
    final data = await out.toByteData(format: ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Could not read the aligned face.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    out.dispose();
    picture.dispose();
  }
}
