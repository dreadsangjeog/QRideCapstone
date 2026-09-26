class KycAutoMatchResult {
  const KycAutoMatchResult({
    required this.nameMatch,
    required this.photoMatch,
    required this.note,
    bool? firstNameMatch,
    bool? lastNameMatch,
  })  : firstNameMatch = firstNameMatch ?? nameMatch,
        lastNameMatch = lastNameMatch ?? nameMatch;

  final bool nameMatch;
  final bool firstNameMatch;
  final bool lastNameMatch;
  final bool photoMatch;
  final String note;

  bool get passed => nameMatch && photoMatch;
}
