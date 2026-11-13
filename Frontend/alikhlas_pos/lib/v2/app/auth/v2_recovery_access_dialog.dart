part of '../v2_app.dart';

class _RecoveryAccessDialog extends ConsumerStatefulWidget {
  const _RecoveryAccessDialog();

  @override
  ConsumerState<_RecoveryAccessDialog> createState() =>
      _RecoveryAccessDialogState();
}

class _RecoveryAccessDialogState extends ConsumerState<_RecoveryAccessDialog> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _fields = List.generate(3, (_) => GlobalKey<FormFieldState<String>>());
  final _focus = List.generate(3, (_) => FocusNode());
  final _errorAnchor = GlobalKey();
  OwnerRecovery? _recovery;
  String? _error;
  var _saving = false;
  var _copied = false;
  var _showPassword = false;
  var _showConfirm = false;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    return PopScope(
      // Escape/back cannot interrupt a write or discard a newly issued code.
      // Explicit Cancel/acknowledgement buttons below can close the dialog.
      canPop: !_saving && _recovery == null,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        title: Row(
          children: [
            Icon(
              _recovery == null
                  ? Icons.key_outlined
                  : Icons.check_circle_outline,
              color: colors.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _recovery == null ? 'استعادة الوصول' : 'رمز الاستعادة الجديد',
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: _recovery == null
              ? Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'اكتب الرمز اللي حفظته عند إعداد المحل، واختار كلمة مرور جديدة.',
                      ),
                      const SizedBox(height: 20),
                      _field(
                        0,
                        _code,
                        'رمز الاستعادة',
                        helper: 'اكتبه أو الصقه كما حفظته.',
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'اكتب رمز الاستعادة'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        1,
                        _password,
                        'كلمة المرور الجديدة',
                        helper: '6 أحرف على الأقل',
                        secret: true,
                        validator: (v) => v == null || v.length < 6
                            ? 'كلمة المرور لازم تكون 6 أحرف على الأقل'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _field(
                        2,
                        _confirm,
                        'تأكيد كلمة المرور',
                        helper: 'اكتب نفس كلمة المرور الجديدة',
                        secret: true,
                        validator: (v) => v == null || v.isEmpty
                            ? 'أكد كلمة المرور'
                            : v != _password.text
                            ? 'كلمتا المرور غير متطابقتين'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _AuthNotice(key: _errorAnchor, message: _error!),
                      ],
                    ],
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'تم تغيير كلمة المرور. احفظ الرمز الجديد في مكان آمن؛ الرمز القديم مبقاش صالح.',
                    ),
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.control,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.stroke),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _recovery!.recoveryCode,
                          key: const ValueKey('recovery-new-code'),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(letterSpacing: 1.2, height: 1.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _copyCode,
                      icon: Icon(
                        _copied ? Icons.check : Icons.copy_outlined,
                        size: 19,
                      ),
                      label: Text(_copied ? 'تم نسخ الرمز' : 'نسخ الرمز'),
                    ),
                  ],
                ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: _recovery == null
            ? [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    disabledForegroundColor: colors.muted.withValues(
                      alpha: .45,
                    ),
                  ),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  key: const ValueKey('recovery-submit'),
                  onPressed: _saving ? null : _recover,
                  child: Text(_saving ? 'جارٍ الاستعادة...' : 'استعادة الدخول'),
                ),
              ]
            : [
                FilledButton(
                  onPressed: () async {
                    final confirmed = await _confirmRecoveryCode(
                      context,
                      _recovery!.recoveryCode,
                    );
                    if (!confirmed || !context.mounted) return;
                    final saved = await ref
                        .read(useCasesProvider)
                        .confirmRecoveryCodeSaved(_recovery!.recoveryCode)
                        .catchError((Object _) => false);
                    if (!context.mounted) return;
                    if (saved) {
                      Navigator.pop(context);
                    } else {
                      _showSnack(context, 'تعذر تأكيد الرمز؛ أعد المحاولة.');
                    }
                  },
                  child: const Text('حفظت الرمز، عودة للدخول'),
                ),
              ],
      ),
    );
  }

  Widget _field(
    int index,
    TextEditingController controller,
    String label, {
    required String helper,
    required FormFieldValidator<String> validator,
    bool secret = false,
  }) {
    final visible = index == 1 ? _showPassword : _showConfirm;
    return TextFormField(
      key: _fields[index],
      controller: controller,
      focusNode: _focus[index],
      autofocus: index == 0,
      enabled: !_saving,
      obscureText: secret && !visible,
      textDirection: TextDirection.ltr,
      textCapitalization: secret
          ? TextCapitalization.none
          : TextCapitalization.characters,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: index == 2 ? TextInputAction.done : TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onFieldSubmitted: (_) =>
          index == 2 ? _recover() : _focus[index + 1].requestFocus(),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helper,
        helperMaxLines: 2,
        errorMaxLines: 2,
        suffixIcon: secret
            ? IconButton(
                tooltip: '${visible ? 'إخفاء' : 'إظهار'} $label',
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          if (index == 1) {
                            _showPassword = !_showPassword;
                          } else {
                            _showConfirm = !_showConfirm;
                          }
                        });
                        _focus[index].requestFocus();
                      },
                icon: Icon(
                  visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
              )
            : null,
      ),
    );
  }

  Future<void> _copyCode() async {
    final code = _recovery?.recoveryCode;
    if (code == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      if (mounted) {
        _showSnack(context, 'تعذر النسخ. تقدر تحدد الرمز وتنسخه يدويًا.');
      }
    }
  }

  Future<void> _recover() async {
    if (_saving || _recovery != null) return;
    if (!(_form.currentState?.validate() ?? false)) {
      final invalid = _fields.indexWhere(
        (field) => field.currentState?.hasError == true,
      );
      if (invalid >= 0) {
        _focus[invalid].requestFocus();
        _reveal(_fields[invalid]);
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(useCasesProvider)
          .recoverOwnerAccess(
            recoveryCode: _code.text,
            newPassword: _password.text,
          );
      if (!mounted) return;
      switch (result) {
        case AppSuccess<OwnerRecovery>(value: final recovery):
          setState(() => _recovery = recovery);
        case AppFailure<OwnerRecovery>(message: final message):
          setState(() => _error = message);
          _reveal(_errorAnchor);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'تعذر إكمال الاستعادة. بياناتك موجودة؛ جرّب مرة تانية.',
        );
        _reveal(_errorAnchor);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
