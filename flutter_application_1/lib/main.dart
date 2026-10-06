import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_shell.dart';
import 'app/bootstrap_error_screen.dart';
import 'config/supabase_config.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/legal/terms_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/user_root_shell.dart';
import 'services/notification_service.dart';
import 'services/ride_foreground_task.dart';
import 'services/ride_session_sync.dart';
import 'theme/app_theme.dart';
import 'theme/login_season.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Port for FG task ↔ UI (needed before runApp on Android).
  if (!kIsWeb) FlutterForegroundTask.initCommunicationPort();
  try {
    await loadSavedThemeMode();
    await loadCachedLoginSeason();
    SupabaseConfig.assertConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.effectiveUrl,
      anonKey: SupabaseConfig.effectiveAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
        localStorage: kIsWeb
            ? null
            : RideSessionStorage.forUrl(SupabaseConfig.effectiveUrl),
      ),
    );
    await NotificationService.init();
    if (!kIsWeb) RideForegroundTask.init();
    await syncLoginSeason();
    await NotificationService.requestPermission();
    runApp(const QRideApp());
  } catch (e, st) {
    debugPrint('Bootstrap failed: $e\n$st');
    runApp(QRideBootstrapError(message: '$e'));
  }
}

class QRideApp extends StatelessWidget {
  const QRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightCs = qrideLightScheme();
    final darkCs = qrideDarkScheme();

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'QRide',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: qrideTheme(lightCs),
        darkTheme: qrideTheme(darkCs),
        home: const AppRoot(),
        routes: {
          LoginScreen.routeName: (_) => const LoginScreen(),
          RegisterScreen.routeName: (_) => const RegisterScreen(),
          TermsScreen.routeName: (_) => const TermsScreen(),
          ForgotPasswordScreen.routeName: (_) => const ForgotPasswordScreen(),
          UserRootShell.routeName: (_) => const UserRootShell(),
          AdminDashboardScreen.routeName: (_) => const AdminDashboardScreen(),
        },
      ),
    );
  }
}
