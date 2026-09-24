import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../utils/auth_validators.dart';
import '../utils/error_message.dart';
import '../widgets/login_scene_backdrop.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _codeSent = false;

  @override
  void dispose() {
    _username.dispose();
    _otp.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.sendRecoveryOtpByUsername(_username.text);
      if (!mounted) return;
      setState(() => _codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If that username exists, we sent a recovery code to the Gmail on file.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AuthService.resetPasswordWithRecoveryOtp(
        username: _username.text,
        token: _otp.text.trim(),
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Password updated'),
          content: const Text(
            'You can sign in with your username and the new password.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = stripExceptionPrefix(e.toString()));
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
      extendBodyBehindAppBar: true,
      appBar: authSceneAppBar(),
      body: LoginSceneBackdrop(
        showRider: false,
        child: AuthSceneBody(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: GlassLoginCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.lock_reset_rounded,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Forgot password',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: -0.3,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _codeSent
                                          ? 'Enter the 6-digit code from your Gmail and choose a new password.'
                                          : 'Enter your username. We will email the Gmail you used when you registered.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _username,
                            enabled: !_codeSent,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: AuthValidators.username,
                            onFieldSubmitted: (_) {
                              if (_codeSent || _busy) return;
                              _sendCode();
                            },
                          ),
                          if (_codeSent) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _otp,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Verification code',
                                prefixIcon: Icon(Icons.pin_outlined),
                              ),
                              validator: AuthValidators.otp6,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _newPassword,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'New password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: AuthValidators.passwordMin6,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          if (!_codeSent)
                            FilledButton(
                              onPressed: _busy ? null : _sendCode,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Send 6-digit code'),
                            )
                          else ...[
                            FilledButton(
                              onPressed: _busy ? null : _reset,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Reset password'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      setState(() {
                                        _codeSent = false;
                                        _otp.clear();
                                        _newPassword.clear();
                                        _error = null;
                                      });
                                    },
                              child: const Text('Start over'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
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
