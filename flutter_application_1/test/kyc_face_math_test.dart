import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_application_1/services/kyc_auto_match_result.dart';
import 'package:flutter_application_1/services/kyc_face_embedder.dart';
import 'package:flutter_application_1/services/kyc_face_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FaceWarp', () {
    test('recovers a known scale, rotation, and shift', () {
      const angle = 0.35;
      const scale = 0.42;
      final a = scale * math.cos(angle);
      final b = scale * math.sin(angle);
      final truth = FaceWarp(a, b, 12.5, -7.25);
      const from = [
        Offset(310, 402),
        Offset(455, 380),
        Offset(330, 560),
        Offset(450, 548),
      ];
      final to = from.map(truth.apply).toList();

      final warp = FaceWarp.fit(from, to)!;

      expect(warp.a, closeTo(a, 1e-9));
      expect(warp.b, closeTo(b, 1e-9));
      expect(warp.tx, closeTo(12.5, 1e-6));
      expect(warp.ty, closeTo(-7.25, 1e-6));
      expect(warp.scale, closeTo(scale, 1e-9));
    });

    test('puts eyes and mouth corners on the template in either order', () {
      final forward = FaceWarp.forFace(
        eyeA: kycTemplateEyes[0] * 3 + const Offset(40, 90),
        eyeB: kycTemplateEyes[1] * 3 + const Offset(40, 90),
        mouthA: kycTemplateMouth[0] * 3 + const Offset(40, 90),
        mouthB: kycTemplateMouth[1] * 3 + const Offset(40, 90),
      )!;
      final swapped = FaceWarp.forFace(
        eyeA: kycTemplateEyes[1] * 3 + const Offset(40, 90),
        eyeB: kycTemplateEyes[0] * 3 + const Offset(40, 90),
        mouthA: kycTemplateMouth[1] * 3 + const Offset(40, 90),
        mouthB: kycTemplateMouth[0] * 3 + const Offset(40, 90),
      )!;

      for (final warp in [forward, swapped]) {
        expect(warp.scale, closeTo(1 / 3, 1e-9));
        final eye = warp.apply(kycTemplateEyes[0] * 3 + const Offset(40, 90));
        expect(eye.dx, closeTo(kycTemplateEyes[0].dx, 1e-6));
        expect(eye.dy, closeTo(kycTemplateEyes[0].dy, 1e-6));
      }
    });

    test('works from the eyes alone and rejects eyes on top of each other', () {
      final eyesOnly = FaceWarp.forFace(
        eyeA: const Offset(100, 200),
        eyeB: const Offset(200, 200),
      )!;
      final left = eyesOnly.apply(const Offset(100, 200));
      final right = eyesOnly.apply(const Offset(200, 200));
      expect((right - left).distance,
          closeTo((kycTemplateEyes[1] - kycTemplateEyes[0]).distance, 1e-6));

      expect(
        FaceWarp.forFace(
          eyeA: const Offset(100, 200),
          eyeB: const Offset(102, 201),
        ),
        isNull,
      );
    });

    test('matrix4 is the same transform as apply', () {
      const warp = FaceWarp(0.3, -0.1, 14, 9);
      final m = warp.matrix4;
      const p = Offset(220, 140);
      final q = warp.apply(p);
      expect(m[0] * p.dx + m[4] * p.dy + m[12], closeTo(q.dx, 1e-9));
      expect(m[1] * p.dx + m[5] * p.dy + m[13], closeTo(q.dy, 1e-9));
    });
  });

  test('aligned face lands the eyes on the template', () async {
    const size = Size(400, 500);
    const eyeA = Offset(140, 210);
    const eyeB = Offset(262, 196);
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
    canvas.drawCircle(eyeA, 9, Paint()..color = const Color(0xFFFF0000));
    canvas.drawCircle(eyeB, 9, Paint()..color = const Color(0xFF0000FF));
    final picture = recorder.endRecording();
    final image =
        await picture.toImage(size.width.toInt(), size.height.toInt());

    final rgba = await kycAlignedFace(
      image,
      FaceWarp.forFace(eyeA: eyeA, eyeB: eyeB)!,
    );
    image.dispose();
    picture.dispose();

    List<int> pixel(Offset at) {
      final i = (at.dy.round() * kycFaceSize + at.dx.round()) * 4;
      return rgba.sublist(i, i + 3);
    }

    final left = pixel(kycTemplateEyes[0]);
    final right = pixel(kycTemplateEyes[1]);
    expect(left[0], greaterThan(200));
    expect(left[2], lessThan(60));
    expect(right[2], greaterThan(200));
    expect(right[0], lessThan(60));
    expect(pixel(const Offset(56, 100)), [255, 255, 255]);
  });

  test('model input is scaled RGB followed by its mirror image', () {
    const n = kycFaceSize * kycFaceSize;
    final rgba = Uint8List(n * 4);
    for (var i = 0; i < n; i++) {
      final x = i % kycFaceSize;
      rgba[i * 4] = x * 2;
      rgba[i * 4 + 1] = 128;
      rgba[i * 4 + 2] = 255 - x;
      rgba[i * 4 + 3] = 255;
    }

    final input = kycFaceInput(rgba);

    expect(input.length, n * 3 * 2);
    expect(input[0], closeTo((0 - 127.5) / 128, 1e-6));
    expect(input[1], closeTo(0.5 / 128, 1e-6));
    expect(input[2], closeTo(127.5 / 128, 1e-6));
    final mirrorRowStart = n * 3;
    expect(input[mirrorRowStart], closeTo((111 * 2 - 127.5) / 128, 1e-6));
    expect(input[mirrorRowStart + 2], closeTo((255 - 111 - 127.5) / 128, 1e-6));
    expect(() => kycFaceInput(Uint8List(10)), throwsArgumentError);
  });

  test('signature merge and similarity', () {
    final raw = Float32List.fromList([3, 4, 0, 6, 8, 0]);
    final merged = kycMergeMirrored(raw);
    expect(merged.length, 3);
    expect(merged[0], closeTo(0.6, 1e-6));
    expect(merged[1], closeTo(0.8, 1e-6));
    expect(kycFaceSimilarity(merged, merged), closeTo(1, 1e-6));
    expect(
      kycFaceSimilarity(
        Float32List.fromList([1, 0, 0]),
        Float32List.fromList([0, 1, 0]),
      ),
      closeTo(0, 1e-9),
    );
    expect(
      () => kycMergeMirrored(Float32List.fromList([0, 0, 1, 1])),
      throwsStateError,
    );
  });

  test('similarity maps to match, unsure, and mismatch', () {
    expect(kycFaceVerdict(0.83), KycFaceVerdict.match);
    expect(kycFaceVerdict(kycFaceMatchAt), KycFaceVerdict.match);
    expect(kycFaceVerdict(0.49), KycFaceVerdict.unsure);
    expect(kycFaceVerdict(kycFaceRejectBelow), KycFaceVerdict.unsure);
    expect(kycFaceVerdict(0.24), KycFaceVerdict.mismatch);
    expect(kycFaceVerdict(-0.1), KycFaceVerdict.mismatch);
  });
}
