import 'dart:typed_data';

import 'kyc_auto_match_result.dart';
import 'kyc_auto_match_stub.dart'
    if (dart.library.io) 'kyc_auto_match_io.dart' as impl;

export 'kyc_auto_match_result.dart';

/// Reads the ID and compares it to the rider's name and live selfie.
class KycAutoMatch {
  static Future<KycAutoMatchResult> review({
    required Uint8List idBytes,
    required Uint8List selfieBytes,
    required String firstName,
    required String lastName,
  }) {
    return impl.reviewKycPhotos(
      idBytes: idBytes,
      selfieBytes: selfieBytes,
      firstName: firstName,
      lastName: lastName,
    );
  }

  /// Reads first and last name from the ID only. No selfie needed.
  static Future<KycAutoMatchResult> reviewNameOnId({
    required Uint8List idBytes,
    required String firstName,
    required String lastName,
  }) {
    return impl.reviewNameOnId(
      idBytes: idBytes,
      firstName: firstName,
      lastName: lastName,
    );
  }

  /// Confirms the still has a printed face clear enough to match later.
  static Future<KycAutoMatchResult> probeIdFace({
    required Uint8List idBytes,
  }) {
    return impl.probeIdFace(idBytes: idBytes);
  }

  /// Compares the printed ID face to the live selfie. Name is not rechecked.
  static Future<KycAutoMatchResult> reviewFaces({
    required Uint8List idBytes,
    required Uint8List selfieBytes,
  }) {
    return impl.reviewFaces(
      idBytes: idBytes,
      selfieBytes: selfieBytes,
    );
  }
}
