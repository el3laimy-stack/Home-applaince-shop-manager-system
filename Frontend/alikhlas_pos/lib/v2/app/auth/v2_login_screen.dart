part of '../v2_app.dart';

class _LoginScreenState extends ConsumerState<_LoginScreen> {
  final _username = TextEditingController(text: 'owner');
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _usernameKey = GlobalKey<FormFieldState<String>>();
  final _passwordKey = GlobalKey<FormFieldState<String>>();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _scroll = ScrollController();
  final _errorAnchor = GlobalKey();
  String? _error;
  bool _loading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    return _GlassStage(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: LayoutBuilder(
            builder: (context, viewport) => Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SingleChildScrollView(
                  key: const ValueKey('login-page-scroll'),
                  controller: _scroll,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: Center(
                      child: _GlassPane(
                        width: 480,
                        padding: EdgeInsets.all(
                          viewport.maxWidth < 480 ? 20 : 28,
                        ),
                        enableBlur: true,
                        child: AutofillGroup(
                          child: Form(
                            key: _form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colors.selected,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: colors.stroke,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Icon(
                                          Icons.lock_outline,
                                          color: colors.primary,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'إخلاص POS',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(color: colors.muted),
                                          ),
                                          Text(
                                            'تسجيل الدخول',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.headlineSmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    ExcludeFocus(
                                      excluding: _loading,
                                      child: AbsorbPointer(
                                        absorbing: _loading,
                                        child: const _ThemeModeControl(
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'أهلًا برجوعك. ادخل لحسابك وكمّل شغل المحل.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: colors.muted),
                                ),
                                const SizedBox(height: 24),
                                TextFormField(
                                  key: _usernameKey,
                                  controller: _username,
                                  focusNode: _usernameFocus,
                                  enabled: !_loading,
                                  textDirection: TextDirection.ltr,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: const [AutofillHints.username],
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                      ? 'اكتب اسم المستخدم'
                                      : null,
                                  onChanged: (_) => _clearError(),
                                  onFieldSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                  decoration: const InputDecoration(
                                    labelText: 'اسم المستخدم',
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.always,
                                    helperText:
                                        'اسم الدخول لحسابك، مش اسمك الشخصي.',
                                    helperMaxLines: 2,
                                    errorMaxLines: 2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  key: _passwordKey,
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  autofocus: true,
                                  enabled: !_loading,
                                  obscureText: !_showPassword,
                                  textDirection: TextDirection.ltr,
                                  enableSuggestions: false,
                                  autocorrect: false,
                                  autofillHints: const [AutofillHints.password],
                                  textInputAction: TextInputAction.done,
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  validator: (v) => v == null || v.isEmpty
                                      ? 'اكتب كلمة المرور'
                                      : null,
                                  onChanged: (_) => _clearError(),
                                  onFieldSubmitted: (_) => _login(),
                                  decoration: InputDecoration(
                                    labelText: 'كلمة المرور',
                                    floatingLabelBehavior:
                                        FloatingLabelBehavior.always,
                                    errorMaxLines: 2,
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword
                                          ? 'إخفاء كلمة المرور'
                                          : 'إظهار كلمة المرور',
                                      onPressed: _loading
                                          ? null
                                          : () {
                                              setState(
                                                () => _showPassword =
                                                    !_showPassword,
                                              );
                                              _passwordFocus.requestFocus();
                                            },
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  _AuthNotice(
                                    key: _errorAnchor,
                                    message: _error!,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  height: 48,
                                  child: FilledButton(
                                    key: const ValueKey('login-submit'),
                                    onPressed: _loading ? null : _login,
                                    child: _loading
                                        ? const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                              SizedBox(width: 10),
                                              Text('جارٍ الدخول...'),
                                            ],
                                          )
                                        : const Text('دخول'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  key: const ValueKey('login-recovery'),
                                  onPressed: _loading
                                      ? null
                                      : () => showDialog<void>(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) =>
                                              const _RecoveryAccessDialog(),
                                        ),
                                  style: TextButton.styleFrom(
                                    disabledForegroundColor: colors.muted
                                        .withValues(alpha: .45),
                                  ),
                                  child: const Text(
                                    'نسيت كلمة المرور؟',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _login() async {
    if (_loading) return;
    if (!(_form.currentState?.validate() ?? false)) {
      final invalid = _usernameKey.currentState?.hasError == true
          ? _usernameKey
          : _passwordKey;
      (invalid == _usernameKey ? _usernameFocus : _passwordFocus)
          .requestFocus();
      _reveal(invalid);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(useCasesProvider)
          .login(_username.text, _password.text);
      if (!mounted) return;
      switch (result) {
        case AppSuccess<User>(value: final owner):
          ref.read(currentOwnerProvider.notifier).setOwner(owner);
        case AppFailure<User>(message: final message):
          setState(() => _error = message);
          _reveal(_errorAnchor);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'تعذر إكمال الدخول. بياناتك موجودة؛ جرّب مرة تانية.',
        );
        _reveal(_errorAnchor);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reveal(GlobalKey key) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: .35,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 160),
          );
        }
      });
}

class _AuthNotice extends StatelessWidget {
  const _AuthNotice({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = LiquidGlassColors.of(context).error;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 19, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message, style: TextStyle(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
