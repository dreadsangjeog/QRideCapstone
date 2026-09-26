import 'dart:typed_data';

import 'kyc_auto_match_result.dart';

Future<KycAutoMatchResult> reviewKycPhotos({
  required Uint8List idBytes,
  required Uint8List selfieBytes,
  required String firstName,
  required String lastName,
}) async {
  return const KycAutoMatchResult(
    nameMatch: false,
    photoMatch: false,
    note: 'Automatic ID check runs on the Android app.',
  );
}

Future<KycAutoMatchResult> reviewNameOnId({
  required Uint8List idBytes,
  required String firstName,
  required String lastName,
}) async {
  return const KycAutoMatchResult(
    nameMatch: false,
    photoMatch: false,
    note: 'Automatic ID check runs on the Android app.',
  );
}

Future<KycAutoMatchResult> probeIdFace({
  required Uint8List idBytes,
}) async {
  return const KycAutoMatchResult(
    nameMatch: true,
    photoMatch: false,
    note: 'Automatic face check runs on the Android app.',
  );
}

Future<KycAutoMatchResult> reviewFaces({
  required Uint8List idBytes,
  required Uint8List selfieBytes,
}) async {
  return const KycAutoMatchResult(
    nameMatch: true,
    photoMatch: false,
    note: 'Automatic face check runs on the Android app.',
  );
}
