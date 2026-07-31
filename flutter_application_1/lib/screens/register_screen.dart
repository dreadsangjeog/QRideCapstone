import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../utils/auth_validators.dart';
import '../utils/error_message.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const routeName = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _username = TextEditingController();
  final _otp = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _debugDetails;
  bool _codeSent = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  Timer? _sendCooldownTimer;
  DateTime? _nextSendAllowedAt;

  @override
  void dispose() {
    _sendCooldownTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _username.dispose();
    _otp.dispose();
    super.dispose();
  }

  int get _cooldownSecondsLeft {
    final until = _nextSendAllowedAt;
    if (until == null) return 0;
    final diff = until.difference(DateTime.now()).inSeconds;
    return diff <= 0 ? 0 : diff;
  }

  void _startCooldown([int seconds = 60]) {
    _nextSendAllowedAt = DateTime.now().add(Duration(seconds: seconds));
    _sendCooldownTimer?.cancel();
    _sendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_cooldownSecondsLeft == 0) {
        t.cancel();
      }
      setState(() {});
    });
  }

  Future<void> _sendCode() async {
    setState(() {
      _error = null;
      _debugDetails = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final email = _email.text.trim().toLowerCase();
    final username = _username.text.trim().toLowerCase();
    final password = _password.text;

    setState(() {
      _busy = true;
    });
    try {
      if (_codeSent) {
        await AuthService.resendSignupCode(
          email: email,
          username: username,
          password: password,
        );
      } else {
        await AuthService.sendRegistrationOtp(
          email: email,
          password: password,
          username: username,
        );
      }
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _error = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification code sent. Check your Gmail.')),
      );
      _startCooldown(60);
    } catch (e) {
      if (e is EmailAlreadyRegisteredException) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _debugDetails = null;
        });
        return;
      }
      final raw = e.toString();
      final msg = stripExceptionPrefix(raw);
      setState(() {
        _debugDetails = msg;
        if (msg.contains('over_email_send_rate_limit') || msg.contains('statusCode: 429')) {
          _error =
              'Too many requests. Please wait about 60 seconds before requesting another code.';
          _startCooldown(60);
          return;
        }
        _error = msg.contains('404')
            ? 'Cannot reach Supabase (404). Check supabase_config.dart: '
                'paste Data API → API URL (https://….supabase.co) and anon public key.'
            : msg;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    setState(() {
      _error = null;
      _debugDetails = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      await AuthService.completeSignup(
        email: _email.text,
        username: _username.text,
        password: _password.text,
        otp: _otp.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account created. Sign in with your username and password.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final msg = stripExceptionPrefix(raw);
      setState(() {
        _error = msg;
        _debugDetails = msg;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
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
                                child: Icon(Icons.person_add_alt_1, color: cs.primary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create account',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Fill in your details, then verify your Gmail.',
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: AuthValidators.username,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          enabled: !_codeSent,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Gmail address',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                          validator: AuthValidators.gmailEmail,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: !_showPassword,
                          textInputAction: TextInputAction.next,
                          enabled: !_codeSent,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _showPassword ? 'Hide password' : 'Show password',
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: AuthValidators.passwordRegister,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: !_showConfirmPassword,
                          textInputAction: TextInputAction.next,
                          enabled: !_codeSent,
                          decoration: InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _showConfirmPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () => setState(
                                () => _showConfirmPassword = !_showConfirmPassword,
                              ),
                              icon: Icon(
                                _showConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (v) => AuthValidators.confirmPasswordMatches(
                                v,
                                _password.text,
                              ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _otp,
                          readOnly: !_codeSent,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Verification code',
                            prefixIcon: const Icon(Icons.pin_outlined),
                            hintText: _codeSent ? 'Enter code' : 'Get code',
                            suffixIcon: TextButton(
                              onPressed: (_busy || _cooldownSecondsLeft > 0) ? null : _sendCode,
                              child: Text(
                                _cooldownSecondsLeft > 0
                                    ? 'Wait ${_cooldownSecondsLeft}s'
                                    : (_codeSent ? 'Resend' : 'Get code'),
                              ),
                            ),
                          ),
                          validator: _codeSent ? AuthValidators.otp6 : null,
                          onTap: () {
                            if (!_codeSent && !_busy) {
                              FocusScope.of(context).unfocus();
                            }
                          },
                          onFieldSubmitted: (_) => _busy ? null : (_codeSent ? _finish() : null),
                        ),
                        if (_codeSent) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Enter the 6-digit code sent to your Gmail.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.error,
                            ),
                          ),
                          if (_debugDetails != null) ...[
                            const SizedBox(height: 8),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'Details',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: SelectableText(
                                    _debugDetails!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                        const SizedBox(height: 14),
                        FilledButton(
                          onPressed: (_busy || !_codeSent) ? null : _finish,
                          child: _busy
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Text('Create account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
