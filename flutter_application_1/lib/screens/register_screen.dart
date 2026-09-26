import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../screens/legal/terms_screen.dart';
import '../utils/auth_validators.dart';
import '../utils/error_message.dart';
import '../widgets/login_scene_backdrop.dart';

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
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _birthdate = TextEditingController();
  final _otp = TextEditingController();

  bool _busy = false;
  String? _error;
  bool _codeSent = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _agreedTerms = false;
  Timer? _sendCooldownTimer;
  DateTime? _nextSendAllowedAt;

  @override
  void dispose() {
    _sendCooldownTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _username.dispose();
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _birthdate.dispose();
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

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_birthdate.text) ??
        DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1)),
    );
    if (picked == null) return;
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    setState(() => _birthdate.text = '${picked.year}-$m-$d');
  }

  Future<void> _continue() async {
    setState(() {
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AuthLightTheme(
          child: TermsScreen(requireAccept: true),
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _agreedTerms = true);
    await _sendCode();
  }

  Future<void> _sendCode() async {
    setState(() {
      _error = null;
    });
    if (!_agreedTerms) {
      setState(() {
        _error = 'Please agree to the Terms & Privacy to continue.';
      });
      return;
    }

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
          firstName: _firstName.text,
          middleName: _middleName.text,
          lastName: _lastName.text,
          birthdate: _birthdate.text,
        );
      } else {
        await AuthService.sendRegistrationOtp(
          email: email,
          password: password,
          username: username,
          firstName: _firstName.text,
          middleName: _middleName.text,
          lastName: _lastName.text,
          birthdate: _birthdate.text,
        );
      }
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _error = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code sent. Check your email.'),
        ),
      );
      _startCooldown(60);
    } catch (e) {
      if (e is EmailAlreadyRegisteredException) {
        if (!mounted) return;
        setState(() => _error = e.toString());
        return;
      }
      final raw = e.toString();
      final msg = stripExceptionPrefix(raw);
      setState(() {
        if (msg.contains('over_email_send_rate_limit') ||
            msg.contains('statusCode: 429')) {
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
    });
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTerms) {
      setState(() {
        _error = 'Please agree to the Terms & Privacy to continue.';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      await AuthService.completeSignup(
        email: _email.text,
        username: _username.text,
        password: _password.text,
        otp: _otp.text.trim(),
        firstName: _firstName.text,
        middleName: _middleName.text,
        lastName: _lastName.text,
        birthdate: _birthdate.text,
      );
      await AuthService.signInWithUsernamePassword(
        username: _username.text,
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final msg = stripExceptionPrefix(raw);
      setState(() => _error = msg);
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
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GlassLoginCard(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _codeSent ? 'Check your email' : 'Create account',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _codeSent
                                  ? 'Step 2 of 2 · enter the code we sent'
                                  : 'Step 1 of 2 · name and account',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (!_codeSent) ...[
                              _sectionLabel(context, 'Name on your ID'),
                              TextFormField(
                                controller: _firstName,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'First name',
                                ),
                                validator: (v) => AuthValidators.legalName(
                                  v,
                                  label: 'First name',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _middleName,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Middle name',
                                  hintText: 'Optional',
                                ),
                                validator: (v) => AuthValidators.legalName(
                                  v,
                                  label: 'Middle name',
                                  required: false,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _lastName,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Last name',
                                ),
                                validator: (v) => AuthValidators.legalName(
                                  v,
                                  label: 'Last name',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _birthdate,
                                readOnly: true,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Birthdate',
                                  prefixIcon: Icon(Icons.cake_outlined),
                                ),
                                validator: AuthValidators.birthdate,
                                onTap: _pickBirthdate,
                              ),
                              const SizedBox(height: 18),
                              _sectionLabel(context, 'Account'),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Email address',
                                  prefixIcon: Icon(Icons.alternate_email),
                                ),
                                validator: AuthValidators.gmailEmail,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _username,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: AuthValidators.username,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _password,
                                obscureText: !_showPassword,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
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
                                validator: AuthValidators.passwordRegister,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmPassword,
                                obscureText: !_showConfirmPassword,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _showConfirmPassword
                                        ? 'Hide password'
                                        : 'Show password',
                                    onPressed: () => setState(
                                      () => _showConfirmPassword =
                                          !_showConfirmPassword,
                                    ),
                                    icon: Icon(
                                      _showConfirmPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                ),
                                validator: (v) =>
                                    AuthValidators.confirmPasswordMatches(
                                      v,
                                      _password.text,
                                    ),
                                onFieldSubmitted: (_) =>
                                    _busy ? null : _continue(),
                              ),
                            ] else ...[
                              Text(
                                'Enter the 6-digit code sent to ${_email.text.trim()}. After this you will sign in and verify your ID.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _otp,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Verification code',
                                  prefixIcon: Icon(Icons.pin_outlined),
                                ),
                                validator: AuthValidators.otp6,
                                onFieldSubmitted: (_) =>
                                    _busy ? null : _finish(),
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
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _busy
                                  ? null
                                  : (_codeSent ? _finish : _continue),
                              child: _busy
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      _codeSent
                                          ? 'Verify code'
                                          : 'Continue',
                                    ),
                            ),
                            if (_codeSent) ...[
                              TextButton(
                                onPressed: (_busy || _cooldownSecondsLeft > 0)
                                    ? null
                                    : _sendCode,
                                child: Text(
                                  _cooldownSecondsLeft > 0
                                      ? 'Resend code in ${_cooldownSecondsLeft}s'
                                      : 'Resend code',
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _codeSent = false;
                                          _otp.clear();
                                          _error = null;
                                        }),
                                child: const Text('Edit details'),
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

Widget _sectionLabel(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );
}
