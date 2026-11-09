part of '../v2_app.dart';

class _InitialOwnerScreenState extends ConsumerState<_InitialOwnerScreen> {
  final _shopName = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _errorAnchor = GlobalKey();
  final _fields = List.generate(4, (i) => GlobalKey<FormFieldState<String>>());
  final _focus = List.generate(4, (i) => FocusNode());
  final _scroll = ScrollController();
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _copied = false;
  bool _pickingBackup = false;
  bool get _busy => _saving || _restoring || _testingPrinter || _pickingBackup;
  InitialOwnerSetup? _setup;
  String? _backupDirectory;
  String? _backupNotice;
  String? _printerNotice;
  String? _error;
  var _saving = false;
  var _restoring = false;
  var _testingPrinter = false;

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _focus) {
      node.dispose();
    }
    _shopName.dispose();
    _name.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GlassStage(
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
                key: const ValueKey('setup-page-scroll'),
                controller: _scroll,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Center(
                    child: _GlassPane(
                      width: 640,
                      padding: EdgeInsets.all(
                        viewport.maxWidth < 480 ? 20 : 28,
                      ),
                      enableBlur: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(),
                          const SizedBox(height: 20),
                          if (_setup == null) _details() else _recovery(),
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
  );

  Widget _header() {
    final colors = LiquidGlassColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.selected,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.stroke),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  _setup == null
                      ? Icons.storefront_outlined
                      : Icons.key_outlined,
                  color: colors.primary,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إخلاص POS',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: colors.muted),
                  ),
                  Text(
                    _setup == null ? 'إعداد المحل' : 'احفظ رمز الاستعادة',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            ExcludeFocus(
              excluding: _busy,
              child: AbsorbPointer(
                absorbing: _busy,
                child: const _ThemeModeControl(compact: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _setup == null
              ? 'أدخل بيانات محلك، ثم احفظ رمز الاستعادة.'
              : 'الرمز ده يساعدك ترجع لحسابك لو نسيت كلمة المرور.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _stepLabel(1, 'بيانات المحل', active: _setup == null),
            Icon(
              Icons.arrow_back,
              textDirection: TextDirection.ltr,
              size: 15,
              color: colors.muted,
            ),
            _stepLabel(2, 'حفظ الرمز', active: _setup != null),
          ],
        ),
      ],
    );
  }

  Widget _stepLabel(int number, String label, {required bool active}) {
    final colors = LiquidGlassColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? colors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '$number. $label',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: active ? colors.primary : colors.muted,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _details() => AutofillGroup(
    child: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final identity = [
                _field(
                  0,
                  _shopName,
                  'اسم المحل',
                  helper: 'هيظهر في فواتيرك',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'اكتب اسم المحل' : null,
                ),
                _field(
                  1,
                  _name,
                  'اسم المالك',
                  helper: 'اسمك كما تحب يظهر في البرنامج',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'اكتب اسم المالك' : null,
                ),
              ];
              final passwords = [
                _field(
                  2,
                  _password,
                  'كلمة المرور',
                  helper: '6 أحرف على الأقل',
                  secret: true,
                  validator: (v) => v == null || v.length < 6
                      ? 'كلمة المرور لازم تكون 6 أحرف على الأقل'
                      : null,
                ),
                _field(
                  3,
                  _confirm,
                  'تأكيد كلمة المرور',
                  helper: 'اكتب نفس كلمة المرور',
                  secret: true,
                  validator: (v) => v == null || v.isEmpty
                      ? 'أكد كلمة المرور'
                      : v != _password.text
                      ? 'كلمتا المرور غير متطابقتين'
                      : null,
                ),
              ];
              Widget pair(List<Widget> fields) => box.maxWidth >= 480
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: fields[0]),
                        const SizedBox(width: 16),
                        Expanded(child: fields[1]),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        fields[0],
                        const SizedBox(height: 14),
                        fields[1],
                      ],
                    );
              return Column(
                children: [
                  pair(identity),
                  const SizedBox(height: 16),
                  pair(passwords),
                ],
              );
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _notice(_error!, error: true),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              key: const ValueKey('setup-submit'),
              onPressed: _busy ? null : _save,
              child: _saving
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('جارٍ الحفظ...'),
                      ],
                    )
                  : const Text('حفظ ومتابعة'),
            ),
          ),
          const SizedBox(height: 16),
          _optionalSettings(),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _busy ? null : _restoreExistingShop,
            style: TextButton.styleFrom(
              disabledForegroundColor: LiquidGlassColors.of(
                context,
              ).muted.withValues(alpha: .45),
            ),
            icon: const Icon(Icons.restore, size: 19),
            label: Text(
              _restoring ? 'جارٍ استرجاع النسخة...' : 'لدي نسخة احتياطية سابقة',
            ),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    int index,
    TextEditingController controller,
    String label, {
    required String helper,
    required FormFieldValidator<String> validator,
    bool secret = false,
  }) {
    final visible = index == 2 ? _showPassword : _showConfirm;
    return TextFormField(
      key: _fields[index],
      controller: controller,
      focusNode: _focus[index],
      enabled: !_busy,
      autofocus: index == 0,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      obscureText: secret && !visible,
      textDirection: secret ? TextDirection.ltr : TextDirection.rtl,
      enableSuggestions: !secret,
      autocorrect: !secret,
      textInputAction: index == 3 ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: (_) {
        if (index == 3) {
          _save();
        } else {
          _focus[index + 1].requestFocus();
        }
      },
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: helper,
        helperMaxLines: 2,
        errorMaxLines: 2,
        suffixIcon: secret
            ? IconButton(
                tooltip: '${visible ? 'إخفاء' : 'إظهار'} $label',
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          if (index == 2) {
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

  Widget _optionalSettings() {
    final colors = LiquidGlassColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: colors.stroke),
    );
    return ExpansionTile(
      key: const ValueKey('setup-optional'),
      maintainState: true,
      enabled: !_busy,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: shape,
      collapsedShape: shape,
      title: const Text('تجهيزات إضافية'),
      subtitle: Text(
        'النسخ الاحتياطي والطابعة — ممكن بعدين',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'النسخ الاحتياطي',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              _backupDirectory == null
                  ? 'يمكنك اختيار مجلد الآن أو ضبطه لاحقًا من شاشة النسخ الاحتياطي.'
                  : 'تم اختيار مجلد للنسخ الاحتياطي.',
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickBackupDirectory,
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: colors.muted.withValues(alpha: .45),
              ),
              icon: const Icon(Icons.folder_open),
              label: Text(
                _pickingBackup ? 'جارٍ اختيار المجلد...' : 'اختيار مجلد النسخ',
              ),
            ),
            const SizedBox(height: 16),
            Text('الطابعة', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              'اختبر صفحة عربية A4 الآن، أو أكمل واضبط الطابعة لاحقًا من شاشة المساعدة.',
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _busy ? null : _testInitialPrinter,
              icon: const Icon(Icons.print_outlined),
              label: Text(
                _testingPrinter ? 'جارٍ فتح الطباعة...' : 'اختبار الطابعة الآن',
              ),
            ),
            if (_printerNotice != null) ...[
              const SizedBox(height: 8),
              _notice(_printerNotice!),
            ],
          ],
        ),
      ],
    );
  }

  Widget _notice(String message, {bool error = false}) {
    final colors = LiquidGlassColors.of(context);
    final color = error ? colors.error : colors.muted;
    return Semantics(
      key: error ? _errorAnchor : null,
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
              Icon(
                error ? Icons.error_outline : Icons.info_outline,
                size: 19,
                color: color,
              ),
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

  Widget _recovery() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'احتفظ بالرمز في مكان آمن. بيظهر مرة واحدة، وهتحتاجه لو نسيت كلمة المرور.',
      ),
      const SizedBox(height: 8),
      Text('اسم الدخول: owner', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 16),
      DecoratedBox(
        decoration: BoxDecoration(
          color: LiquidGlassColors.of(context).control,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LiquidGlassColors.of(context).stroke),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            _setup!.recoveryCode,
            key: const ValueKey('setup-recovery-code'),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(letterSpacing: 1.2, height: 1.8),
          ),
        ),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _copyRecoveryCode,
        icon: Icon(_copied ? Icons.check : Icons.copy_outlined, size: 19),
        label: Text(_copied ? 'تم نسخ الرمز' : 'نسخ الرمز'),
      ),
      if (_backupNotice != null) ...[
        const SizedBox(height: 16),
        _notice(_backupNotice!),
      ],
      const SizedBox(height: 20),
      SizedBox(
        height: 48,
        child: FilledButton(
          onPressed: _finishSetup,
          child: const Text('حفظت الرمز، ابدأ العمل'),
        ),
      ),
    ],
  );

  Future<void> _copyRecoveryCode() async {
    final code = _setup?.recoveryCode;
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

  Future<void> _save() async {
    if (_busy || _setup != null) return;
    if (!(_form.currentState?.validate() ?? false)) {
      final index = _fields.indexWhere(
        (field) => field.currentState?.hasError ?? false,
      );
      if (index >= 0) {
        _focus[index].requestFocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final fieldContext = _fields[index].currentContext;
          if (mounted && fieldContext != null) {
            Scrollable.ensureVisible(
              fieldContext,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              alignment: .25,
            );
          }
        });
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
          .setupInitialOwner(
            fullName: _name.text,
            password: _password.text,
            shopName: _shopName.text,
          );
      if (!mounted) return;
      switch (result) {
        case AppSuccess<InitialOwnerSetup>(value: final setup):
          final backupNotice = await _configureInitialBackup();
          if (!mounted) return;
          setState(() {
            _setup = setup;
            _backupNotice = backupNotice;
          });
          _scroll.jumpTo(0);
        case AppFailure<InitialOwnerSetup>(message: final message):
          setState(() => _error = message);
          _revealError();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'تعذر إكمال الحفظ. بياناتك لسه موجودة في الشاشة؛ جرّب مرة تانية.',
        );
        _revealError();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _revealError() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _errorAnchor.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
        );
      }
    });
  }

  void _finishSetup() {
    final setup = _setup;
    if (setup == null) return;
    ref.read(currentOwnerProvider.notifier).setOwner(setup.owner);
    ref.invalidate(initialOwnerRequiredProvider);
  }

  Future<void> _pickBackupDirectory() async {
    if (_busy) return;
    setState(() => _pickingBackup = true);
    try {
      final directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد النسخ الاحتياطي',
      );
      if (mounted && directory != null) {
        setState(() => _backupDirectory = directory);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'تعذر فتح اختيار المجلد. تقدر تضبط النسخ الاحتياطي بعدين.',
        );
      }
    } finally {
      if (mounted) setState(() => _pickingBackup = false);
    }
  }

  Future<void> _testInitialPrinter() async {
    if (_busy) return;
    final shopName = _shopName.text.trim();
    if (shopName.isEmpty) {
      setState(
        () => _error = 'أدخل اسم المحل أولًا لاستخدامه في صفحة الاختبار.',
      );
      return;
    }
    final print = ref.read(printerTestPageProvider);
    setState(() {
      _testingPrinter = true;
      _printerNotice = null;
      _error = null;
    });
    try {
      final accepted = await print(ShopSettingsSnapshot(shopName: shopName));
      if (!mounted) return;
      setState(
        () => _printerNotice = accepted
            ? 'أُرسل طلب الطباعة. تأكد من خروج الصفحة ووضوح العربية، ثم جرّب الإيصال والباركود بالحجم الفعلي.'
            : 'لم تكتمل الطباعة. يمكنك إعادة الاختبار أو ضبط الطابعة لاحقًا من شاشة المساعدة.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _printerNotice =
            'تعذر فتح نافذة الطباعة. يمكنك إكمال الإعداد وضبط الطابعة لاحقًا.',
      );
    } finally {
      if (mounted) setState(() => _testingPrinter = false);
    }
  }

  Future<String> _configureInitialBackup() async {
    final directory = _backupDirectory;
    if (directory == null || directory.trim().isEmpty) {
      return 'لم يتم اختيار مجلد للنسخ. يمكنك ضبطه لاحقًا من شاشة النسخ الاحتياطي.';
    }

    final useCases = ref.read(useCasesProvider);
    try {
      await useCases.setBackupDirectory(directory);
      final backup = await useCases.tryAutomaticBackup();
      if (backup != null) {
        return 'تم إنشاء النسخة الاحتياطية الأولى في المجلد المختار.';
      }
      return useCases.backupWarning ??
          'تم حفظ المجلد. ستتم محاولة النسخ تلقائيًا عند تشغيل التطبيق.';
    } catch (_) {
      return 'تم إنشاء حساب المالك، لكن تعذر ضبط النسخ الآن. اضبطه من شاشة النسخ الاحتياطي.';
    }
  }

  Future<void> _restoreExistingShop() async {
    if (_busy) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر النسخة الاحتياطية للمحل',
        type: FileType.custom,
        allowedExtensions: ['db', 'zip'],
      );
      if (!mounted || picked == null || picked.files.single.path == null) {
        return;
      }
      final backupPath = picked.files.single.path!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('استرجاع محل سابق'),
          content: const Text(
            'سيستبدل هذا بيانات الإعداد الحالي ببيانات النسخة المختارة. سنفحص الملف أولًا ونحتفظ بنسخة رجوع قبل الاستبدال.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('استرجاع النسخة'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final useCases = ref.read(useCasesProvider);
      final backup = File(backupPath);
      if (backupPath.toLowerCase().endsWith('.zip')) {
        await useCases.restoreFromPortableBackup(backup);
      } else {
        await useCases.restoreFromBackup(backup);
      }
      if (!mounted) return;
      ref.read(currentOwnerProvider.notifier).setOwner(null);
      ref.invalidate(databaseProvider);
      ref.invalidate(bootstrapProvider);
      ref.invalidate(initialOwnerRequiredProvider);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'تعذر استرجاع النسخة. تأكد من اختيار نسخة المحل السليمة.',
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }
}
