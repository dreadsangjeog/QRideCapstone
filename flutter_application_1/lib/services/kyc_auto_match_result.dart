import 'dart:typed_data';

/// How the live selfie compared with the face printed on the ID.
enum KycFaceVerdict {
  /// Clearly the same person. Staff still make the final call.
  match,

  /// Too close to call, so staff compare the photos.
  unsure,

  /// Clearly a different person.
  mismatch,
}

/// Photo in which no usable face was found.
enum KycFaceStep { idPhoto, liveSelfie }

class KycAutoMatchResult {
  const KycAutoMatchResult({
    required this.nameMatch,
    required this.photoMatch,
    required this.note,
    bool? firstNameMatch,
    bool? lastNameMatch,
    this.faceVerdict,
    this.faceScore,
    this.unreadable,
    this.idFace,
    this.liveFace,
  })  : firstNameMatch = firstNameMatch ?? nameMatch,
        lastNameMatch = lastNameMatch ?? nameMatch;

  final bool nameMatch;
  final bool firstNameMatch;
  final bool lastNameMatch;
  final bool photoMatch;
  final String note;

  /// Set when both faces were read and compared.
  final KycFaceVerdict? faceVerdict;

  /// Face similarity, about 0 (different people) to 1 (same photo).
  final double? faceScore;

  /// Set when the check stopped because a photo had no usable face.
  final KycFaceStep? unreadable;

  /// Close-up crops (PNG) of the two faces that were compared.
  final Uint8List? idFace;
  final Uint8List? liveFace;

  bool get passed => nameMatch && photoMatch;
}
