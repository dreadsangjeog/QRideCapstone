import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/brand.dart';
import '../utils/auth_validators.dart';
import '../utils/error_message.dart';
import '../widgets/auth_branding.dart';
import '../widgets/login_scene_backdrop.dart';
import 'forgot_password_screen.dart';
import 'legal/terms_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await AuthService.signInWithUsernamePassword(
        username: _username.text,
        password: _password.text,
      );
      if (!mounted) return;
    } on FunctionException catch (e) {
      setState(() {
        if (e.status == 404) {
          _error =
              'Login service not found (404). Deploy the Edge Function '
              '`login-with-username` — see supabase/EDGE_FUNCTIONS.md';
        } else {
          final d = e.details;
          _error = d is Map && d['error'] is String
              ? d['error'] as String
              : 'Could not sign in. Try again.';
        }
      });
    } catch (e) {
      final msg = stripExceptionPrefix(e.toString());
      setState(() {
        if (msg.contains('Email not confirmed') ||
            msg.contains('email_not_confirmed')) {
          _error =
              'Verify your Gmail inbox and confirm your email before logging in.';
        } else {
          _error = msg;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLightTheme(
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;
          return Scaffold(
      backgroundColor: Colors.transparent,
      body: LoginSceneBackdrop(
        child: AuthSceneBody(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AuthBrandHeader(),
                    GlassLoginCard(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 4,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        QrideBrand.accentSoft,
                                        QrideBrand.accent,
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome back',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Text(
                                      'Sign in to continue riding',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _username,
                                    keyboardType: TextInputType.text,
                                    autocorrect: false,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Username',
                                      hintText: 'Enter your username',
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                    validator: AuthValidators.username,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _password,
                                    obscureText: !_showPassword,
                                    textInputAction: TextInputAction.done,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      hintText: 'Enter your password',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      suffixIcon: IconButton(
                                        tooltip: _showPassword
                                            ? 'Hide password'
                                            : 'Show password',
                                        onPressed: () => setState(
                                          () => _showPassword = !_showPassword,
                                        ),
                                        icon: Icon(
                                          _showPassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: (v) {
                                      if ((v ?? '').isEmpty) {
                                        return 'Password required';
                                      }
                                      return null;
                                    },
                                    onFieldSubmitted: (_) =>
                                        _busy ? null : _submit(),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  foregroundColor: cs.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  textStyle: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.onPrimary,
                                        ),
                                      )
                                    : const Text('Login'),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(RegisterScreen.routeName),
                              child: const Text("Don't have an account? Register"),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context)
                                  .pushNamed(ForgotPasswordScreen.routeName),
                              child: const Text('Forgot password?'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const TermsFooterLink(),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}
