import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../screens/legal/terms_screen.dart';
import '../utils/auth_validators.dart';
import '../utils/error_message.dart';
import '../widgets/birthdate_picker.dart';
import '../widgets/login_scene_backdrop.dart';

enum _Step { about, account, verify }

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
  _Step _step = _Step.about;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _agreedTerms = false;
  Timer? _sendCooldownTimer;
  DateTime? _nextSendAllowedAt;
  final _touched = <String>{};

  bool get _codeSent => _step == _Step.verify;

  AutovalidateMode _mode(String id) => _touched.contains(id)
      ? AutovalidateMode.always
      : AutovalidateMode.disabled;

  /// A field shows its error once the rider leaves it or taps Next, then
  /// stays live so the error clears as soon as the input is fixed.
  Widget _field(String id, Widget field) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused && mounted && !_touched.contains(id)) {
          setState(() => _touched.add(id));
        }
      },
      child: field,
    );
  }

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

  /// [context] must sit under [AuthLightTheme] so the picker stays light.
  Future<void> _pickBirthdate(BuildContext context) async {
    final now = DateTime.now();
    final initial =
        DateTime.tryParse(_birthdate.text) ??
        DateTime(now.year - 18, now.month, now.day);
    final picked = await showBirthdatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)),
      startWithYear: _birthdate.text.isEmpty,
    );
    if (picked == null || !mounted) return;
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    setState(() => _birthdate.text = '${picked.year}-$m-$d');
  }

  void _next() {
    setState(() {
      _error = null;
      _touched.addAll(const ['first', 'middle', 'last', 'birthdate']);
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _step = _Step.account);
  }

  void _back() {
    if (_busy) return;
    setState(() {
      _error = null;
      if (_step == _Step.verify) {
        _otp.clear();
        _touched.remove('otp');
        _step = _Step.account;
      } else {
        _step = _Step.about;
      }
    });
  }

  Future<void> _continue() async {
    setState(() {
      _error = null;
      _touched.addAll(const ['username', 'password', 'confirm', 'email']);
    });
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedTerms) {
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              const AuthLightTheme(child: TermsScreen(requireAccept: true)),
        ),
      );
      if (accepted != true || !mounted) return;
      setState(() => _agreedTerms = true);
    }
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
      // Offer to save the login while the account fields are still mounted.
      if (!_codeSent) TextInput.finishAutofillContext();
      setState(() {
        _step = _Step.verify;
        _error = null;
      });
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
      _touched.add('otp');
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
    return PopScope(
      canPop: _step == _Step.about,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AuthLightTheme(
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _StepProgress(step: _step),
                              const SizedBox(height: 16),
                              _StepFade(
                                key: ValueKey(_step),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _StepTitle(
                                      step: _step,
                                      email: _email.text.trim(),
                                    ),
                                    const SizedBox(height: 18),
                                    switch (_step) {
                                      _Step.about => _aboutFields(context),
                                      _Step.account => _accountFields(),
                                      _Step.verify => _codeField(),
                                    },
                                  ],
                                ),
                              ),
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
                              _actions(cs),
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
      ),
    );
  }

  Widget _aboutFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          'first',
          TextFormField(
            controller: _firstName,
            autovalidateMode: _mode('first'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'First name'),
            validator: (v) => AuthValidators.legalName(v, label: 'First name'),
          ),
        ),
        const SizedBox(height: 12),
        _field(
          'middle',
          TextFormField(
            controller: _middleName,
            autovalidateMode: _mode('middle'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Middle name (optional)',
            ),
            validator: (v) => AuthValidators.legalName(
              v,
              label: 'Middle name',
              required: false,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _field(
          'last',
          TextFormField(
            controller: _lastName,
            autovalidateMode: _mode('last'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Last name'),
            validator: (v) => AuthValidators.legalName(v, label: 'Last name'),
            onFieldSubmitted: (_) {
              if (_birthdate.text.isEmpty) unawaited(_pickBirthdate(context));
            },
          ),
        ),
        const SizedBox(height: 12),
        // Not wrapped in _field: the picker takes focus when it opens, which
        // would flag the field before the rider has chosen anything.
        TextFormField(
          controller: _birthdate,
          autovalidateMode: _mode('birthdate'),
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Birthdate',
            prefixIcon: Icon(Icons.cake_outlined),
            suffixIcon: Icon(Icons.calendar_month_outlined),
          ),
          validator: AuthValidators.birthdate,
          onTap: () => _pickBirthdate(context),
        ),
      ],
    );
  }

  /// Username sits right above the password: riders sign in with that pair,
  /// and password managers save the field before the password as the login.
  Widget _accountFields() {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            'username',
            TextFormField(
              controller: _username,
              autovalidateMode: _mode('username'),
              autofocus: _username.text.isEmpty,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newUsername],
              decoration: const InputDecoration(
                labelText: 'Username',
                helperText: 'Letters, numbers, and underscores',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: AuthValidators.username,
            ),
          ),
          const SizedBox(height: 12),
          _field(
            'password',
            TextFormField(
              controller: _password,
              autovalidateMode: _mode('password'),
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: _visibilityToggle(
                  shown: _showPassword,
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: AuthValidators.passwordRegister,
            ),
          ),
          const SizedBox(height: 8),
          _PasswordRules(password: _password),
          const SizedBox(height: 12),
          _field(
            'confirm',
            TextFormField(
              controller: _confirmPassword,
              autovalidateMode: _mode('confirm'),
              obscureText: !_showConfirmPassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: _visibilityToggle(
                  shown: _showConfirmPassword,
                  onPressed: () => setState(
                    () => _showConfirmPassword = !_showConfirmPassword,
                  ),
                ),
              ),
              validator: (v) =>
                  AuthValidators.confirmPasswordMatches(v, _password.text),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            'email',
            TextFormField(
              controller: _email,
              autovalidateMode: _mode('email'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'you@gmail.com',
                helperText: "We'll send your 6-digit code here",
                prefixIcon: Icon(Icons.alternate_email),
              ),
              validator: AuthValidators.gmailEmail,
              onFieldSubmitted: (_) => _busy ? null : _continue(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeField() {
    return TextFormField(
      controller: _otp,
      autovalidateMode: _mode('otp'),
      autofocus: true,
      keyboardType: TextInputType.number,
      autofillHints: const [AutofillHints.oneTimeCode],
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
      onFieldSubmitted: (_) => _busy ? null : _finish(),
    );
  }

  Widget _visibilityToggle({
    required bool shown,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: shown ? 'Hide password' : 'Show password',
      onPressed: onPressed,
      icon: Icon(
        shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    );
  }

  Widget _actions(ColorScheme cs) {
    final spinner = SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
    );
    return switch (_step) {
      _Step.about => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: _next, child: const Text('Next')),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text.rich(
              TextSpan(
                text: 'Already have an account? ',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(
                    text: 'Sign in',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      _Step.account => Row(
        children: [
          OutlinedButton(
            onPressed: _busy ? null : _back,
            child: const Text('Back'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _continue,
              child: _busy ? spinner : const Text('Continue'),
            ),
          ),
        ],
      ),
      _Step.verify => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: _busy ? null : _finish,
            child: _busy ? spinner : const Text('Verify and create account'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: (_busy || _cooldownSecondsLeft > 0) ? null : _sendCode,
            child: Text(
              _cooldownSecondsLeft > 0
                  ? 'Resend code in ${_cooldownSecondsLeft}s'
                  : 'Resend code',
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _back,
            child: const Text('Edit details'),
          ),
        ],
      ),
    };
  }
}

/// Three-segment bar across the top of the card.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Step ${step.index + 1} of ${_Step.values.length}',
      child: Row(
        children: [
          for (final s in _Step.values) ...[
            if (s != _Step.values.first) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 5,
                decoration: BoxDecoration(
                  color: s.index <= step.index
                      ? cs.primary
                      : cs.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.step, required this.email});

  final _Step step;
  final String email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (title, subtitle) = switch (step) {
      _Step.about => (
        'About you',
        'Use your name exactly as it appears on your ID. '
            'We match it when you verify your ID.',
      ),
      _Step.account => (
        'Your account',
        'You will sign in with your username and password.',
      ),
      _Step.verify => (
        'Check your email',
        'Enter the 6-digit code sent to $email. '
            'After this you will sign in and verify your ID.',
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create account · Step ${step.index + 1} of ${_Step.values.length}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// Fades and lifts each step in. Only the current step is ever mounted, so
/// the form never validates fields from a step the rider has left.
class _StepFade extends StatelessWidget {
  const _StepFade({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Live checklist for [AuthValidators.passwordRegister].
class _PasswordRules extends StatelessWidget {
  const _PasswordRules({required this.password});

  final TextEditingController password;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: password,
      builder: (context, value, _) {
        final text = value.text;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Rule(label: '6+ characters', met: text.length >= 6),
              _Rule(label: 'A letter', met: text.contains(RegExp('[A-Za-z]'))),
              _Rule(label: 'A number', met: text.contains(RegExp(r'\d'))),
            ],
          ),
        );
      },
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = met
        ? const Color(0xFF16A34A)
        : theme.colorScheme.onSurfaceVariant;
    return Semantics(
      label: '$label, ${met ? 'done' : 'not yet'}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: met ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
