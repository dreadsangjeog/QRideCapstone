import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_shell.dart';
import 'app/bootstrap_error_screen.dart';
import 'config/supabase_config.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/user_root_shell.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

/// Global theme-mode notifier. Toggle dark/light from anywhere in the app.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    SupabaseConfig.assertConfigured();
    await Supabase.initialize(
      url: SupabaseConfig.effectiveUrl,
      anonKey: SupabaseConfig.effectiveAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
      ),
    );
    await NotificationService.init();
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
    final lightCs = ColorScheme.fromSeed(
      seedColor: kQrideSeedColor,
      brightness: Brightness.light,
    );
    final darkCs = ColorScheme.fromSeed(
      seedColor: kQrideSeedColor,
      brightness: Brightness.dark,
    );

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
          ForgotPasswordScreen.routeName: (_) => const ForgotPasswordScreen(),
          UserRootShell.routeName: (_) => const UserRootShell(),
          AdminDashboardScreen.routeName: (_) => const AdminDashboardScreen(),
        },
      ),
    );
  }
}
