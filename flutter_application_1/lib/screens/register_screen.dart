import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../utils/auth_validators.dart';

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
  final _username = TextEditingController();
  final _otp = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _debugDetails;
  bool _codeSent = false;
  bool _showPassword = false;
  Timer? _sendCooldownTimer;
  DateTime? _nextSendAllowedAt;

  @override
  void dispose() {
    _sendCooldownTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _otp.dispose();
    super.dispose();
  }

  String? _otpValidator(String? v) {
    final s = (v ?? '').trim();
    if (!RegExp(r'^\d{6}$').hasMatch(s)) {
      return 'Enter the 6-digit code from your Gmail';
    }
    return null;
  }

  String? _passwordValidator(String? v) {
    final s = (v ?? '');
    if (s.length < 6) return 'Use at least 6 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) {
      return 'Use letters and numbers';
    }
    return null;
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
      final msg = e.toString();
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
      setState(() {
        _error = e.toString();
        _debugDetails = e.toString();
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
                                    'Register',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Get code emails a 6-digit OTP. Your Auth user is created only when '
                                    'you tap Create account (same password you used for Get code).',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      height: 1.35,
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
                          validator: _passwordValidator,
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
                          validator: _codeSent ? _otpValidator : null,
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
                            'Use the same password as above when you tap Create account—the server checks '
                            'it matches what you used for Get code.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.35,
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
