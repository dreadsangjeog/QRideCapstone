import 'package:flutter/material.dart';

import '../../services/kyc_repository.dart';
import 'kyc_wizard_screen.dart';

class KycScope extends InheritedWidget {
  const KycScope({
    super.key,
    required this.profile,
    required this.reload,
    required super.child,
  });

  final KycProfile profile;
  final Future<void> Function() reload;

  bool get canUseFeatures => profile.isVerified;

  static KycScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<KycScope>();
  }

  static KycScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'KycScope not found');
    return scope!;
  }

  Future<void> openWizard(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => KycWizardScreen(
          onSubmitted: () {
            Navigator.of(context).pop();
            reload();
          },
          rejectedNote: profile.isRejected ? profile.note : null,
        ),
      ),
    );
    await reload();
  }

  @override
  bool updateShouldNotify(KycScope oldWidget) {
    return oldWidget.profile.status != profile.status ||
        oldWidget.profile.note != profile.note;
  }
}
