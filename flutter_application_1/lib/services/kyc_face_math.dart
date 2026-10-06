import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'kyc_auto_match_result.dart';

/// Side of the square face the recognition model reads.
const kycFaceSize = 112;

/// Where the eyes and mouth corners sit in the face the model was trained on,
/// listed left to right as they appear in the image.
const kycTemplateEyes = [Offset(38.2946, 51.6963), Offset(73.5318, 51.5014)];
const kycTemplateMouth = [Offset(41.5493, 92.3655), Offset(70.7299, 92.2041)];

/// At or above this similarity the faces are clearly the same person.
const kycFaceMatchAt = 0.50;

/// Below this similarity the faces are clearly different people. In between,
/// staff compare the photos.
const kycFaceRejectBelow = 0.25;

KycFaceVerdict kycFaceVerdict(double similarity) {
  if (similarity >= kycFaceMatchAt) return KycFaceVerdict.match;
  if (similarity >= kycFaceRejectBelow) return KycFaceVerdict.unsure;
  return KycFaceVerdict.mismatch;
}

/// Scale, rotation, and shift that carry a photo onto the model's template.
class FaceWarp {
  const FaceWarp(this.a, this.b, this.tx, this.ty);

  final double a;
  final double b;
  final double tx;
  final double ty;

  double get scale => math.sqrt(a * a + b * b);

  Offset apply(Offset p) {
    return Offset(a * p.dx - b * p.dy + tx, b * p.dx + a * p.dy + ty);
  }

  /// Column-major 4x4 matrix for [Canvas.transform].
  Float64List get matrix4 => Float64List.fromList([
        a, b, 0, 0, //
        -b, a, 0, 0, //
        0, 0, 1, 0, //
        tx, ty, 0, 1, //
      ]);

  /// Least-squares fit of [from] onto [to]. Needs two or more distinct points.
  static FaceWarp? fit(List<Offset> from, List<Offset> to) {
    final n = from.length;
    if (n < 2 || n != to.length) return null;
    var fx = 0.0, fy = 0.0, tx = 0.0, ty = 0.0;
    for (var i = 0; i < n; i++) {
      fx += from[i].dx;
      fy += from[i].dy;
      tx += to[i].dx;
      ty += to[i].dy;
    }
    fx /= n;
    fy /= n;
    tx /= n;
    ty /= n;
    var spread = 0.0, dot = 0.0, cross = 0.0;
    for (var i = 0; i < n; i++) {
      final px = from[i].dx - fx;
      final py = from[i].dy - fy;
      final qx = to[i].dx - tx;
      final qy = to[i].dy - ty;
      spread += px * px + py * py;
      dot += px * qx + py * qy;
      cross += px * qy - py * qx;
    }
    if (spread < 1e-6) return null;
    final a = dot / spread;
    final b = cross / spread;
    return FaceWarp(a, b, tx - (a * fx - b * fy), ty - (b * fx + a * fy));
  }

  /// Lines up both eyes, plus both mouth corners when the detector found them.
  static FaceWarp? forFace({
    required Offset eyeA,
    required Offset eyeB,
    Offset? mouthA,
    Offset? mouthB,
  }) {
    final eyes = [eyeA, eyeB]..sort((p, q) => p.dx.compareTo(q.dx));
    if ((eyes[1] - eyes[0]).distance < 6) return null;
    final from = [...eyes];
    final to = [...kycTemplateEyes];
    if (mouthA != null && mouthB != null) {
      final mouth = [mouthA, mouthB]..sort((p, q) => p.dx.compareTo(q.dx));
      from.addAll(mouth);
      to.addAll(kycTemplateMouth);
    }
    return fit(from, to);
  }
}

/// Model input for one face: the face, then its mirror image, as RGB scaled to
/// about -1..1. [rgba] is [kycFaceSize] x [kycFaceSize] RGBA bytes.
Float32List kycFaceInput(Uint8List rgba) {
  const size = kycFaceSize;
  const plane = size * size * 3;
  if (rgba.length < size * size * 4) {
    throw ArgumentError('Expected a $size x $size RGBA face.');
  }
  final out = Float32List(plane * 2);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final src = (y * size + x) * 4;
      final dst = (y * size + x) * 3;
      final mirror = plane + (y * size + (size - 1 - x)) * 3;
      for (var c = 0; c < 3; c++) {
        final v = (rgba[src + c] - 127.5) / 128.0;
        out[dst + c] = v;
        out[mirror + c] = v;
      }
    }
  }
  return out;
}

/// One unit-length signature from the model's two outputs (face and mirror).
Float32List kycMergeMirrored(Float32List raw) {
  final dim = raw.length ~/ 2;
  if (dim == 0) throw ArgumentError('Empty face signature.');
  double lengthOf(int start) {
    var sum = 0.0;
    for (var i = 0; i < dim; i++) {
      sum += raw[start + i] * raw[start + i];
    }
    return math.sqrt(sum);
  }

  final first = lengthOf(0);
  final second = lengthOf(dim);
  if (first < 1e-9 || second < 1e-9) {
    throw StateError('Face signature is blank.');
  }
  final out = Float32List(dim);
  var sum = 0.0;
  for (var i = 0; i < dim; i++) {
    final v = raw[i] / first + raw[dim + i] / second;
    out[i] = v;
    sum += v * v;
  }
  final length = math.sqrt(sum);
  for (var i = 0; i < dim; i++) {
    out[i] = out[i] / length;
  }
  return out;
}

/// Cosine similarity of two unit-length signatures: 1 is identical.
double kycFaceSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) throw ArgumentError('Signature sizes differ.');
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot.clamp(-1.0, 1.0);
}
