import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../widgets/qride_brand.dart';

/// Cold-start splash. Starts on the same frame as Android's launch screen,
/// reveals the wordmark, then hands over once [ready] completes.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.onFinished, this.ready});

  final VoidCallback onFinished;

  /// Work to finish before leaving the splash, such as looking up where a
  /// signed-in user belongs. The splash never waits longer than [maxWait].
  final Future<void>? ready;

  static const Duration intro = Duration(milliseconds: 1000);
  static const Duration maxWait = Duration(seconds: 6);

  /// Decodes the bike before the first frame, so the splash never draws the
  /// plate without it while Android's launch screen hands over.
  static Future<void> precacheMark() async {
    final done = Completer<void>();
    final stream = const AssetImage(QrideBrand.bikeLight)
        .resolve(ImageConfiguration.empty);
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    final listener = ImageStreamListener(
      (_, _) => finish(),
      onError: (_, _) => finish(),
    );
    stream.addListener(listener);
    await done.future.timeout(
      const Duration(milliseconds: 800),
      onTimeout: () {},
    );
    stream.removeListener(listener);
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: SplashScreen.intro,
  );

  late final Animation<double> _lift = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.12, 0.72, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _reveal = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.32, 0.9, curve: Curves.easeOutCubic),
  );

  late final Animation<double> _glow = CurvedAnimation(
    parent: _intro,
    curve: const Interval(0.12, 1, curve: Curves.easeOut),
  );

  bool _ready = false;
  bool _finished = false;
  bool _showSpinner = false;
  Timer? _spinnerTimer;
  Timer? _maxWait;

  @override
  void initState() {
    super.initState();
    final ready = widget.ready;
    if (ready == null) {
      _ready = true;
    } else {
      ready.then((_) => _markReady(), onError: (_) => _markReady());
    }
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _maybeFinish();
    });
    _spinnerTimer = Timer(
      SplashScreen.intro + const Duration(milliseconds: 600),
      () {
        if (mounted && !_finished) setState(() => _showSpinner = true);
      },
    );
    _maxWait = Timer(SplashScreen.intro + SplashScreen.maxWait, _markReady);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _maybeFinish();
    } else {
      _intro.forward();
    }
  }

  void _markReady() {
    if (_ready) return;
    _ready = true;
    _maybeFinish();
  }

  void _maybeFinish() {
    if (_finished || !_ready || !_intro.isCompleted || !mounted) return;
    _finished = true;
    _spinnerTimer?.cancel();
    _maxWait?.cancel();
    widget.onFinished();
  }

  @override
  void dispose() {
    _spinnerTimer?.cancel();
    _maxWait?.cancel();
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Semantics(
        label: 'QRide',
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) => QrideLaunchLayout(
            lift: _lift.value,
            reveal: _reveal.value,
            glow: _glow.value,
            footer: AnimatedOpacity(
              opacity: _showSpinner ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: const QrideLaunchSpinner(),
            ),
          ),
        ),
      ),
    );
  }
}
