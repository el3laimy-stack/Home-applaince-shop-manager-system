part of '../v2_app.dart';

class _ReceiptSettings extends ConsumerStatefulWidget {
  const _ReceiptSettings({required this.shop});
  final ShopSettingsSnapshot shop;
  @override
  ConsumerState<_ReceiptSettings> createState() => _ReceiptSettingsState();
}

class _ReceiptSettingsState extends ConsumerState<_ReceiptSettings> {
  late final Future<ReceiptPrintProfile> _load = ref
      .read(useCasesProvider)
      .receiptPrintProfile();
  ReceiptPrintProfile? _profile;
  bool _busy = false;
  String? _message;
  @override
  Widget build(BuildContext context) => FutureBuilder<ReceiptPrintProfile>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('تعذر قراءة إعدادات الإيصال. أعد فتح الإعدادات.');
      }
      final p = _profile ?? snapshot.data;
      if (p == null) return const LinearProgressIndicator();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الإيصال الحراري',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: p.widthMm,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'عرض ورق الإيصال'),
            items: const [
              DropdownMenuItem(value: 80, child: Text('80 مم')),
              DropdownMenuItem(value: 58, child: Text('58 مم')),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(
                    () => _profile = ReceiptPrintProfile(
                      widthMm: v!,
                      splitPages: p.splitPages,
                      showProductCodes: p.showProductCodes,
                    ),
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('تقسيم الإيصال إلى أجزاء 250 مم'),
            subtitle: const Text(
              'فعّلها إذا كان تعريف الطابعة لا يدعم الإيصال الطويل.',
            ),
            value: p.splitPages,
            onChanged: _busy
                ? null
                : (v) => setState(
                    () => _profile = ReceiptPrintProfile(
                      widthMm: p.widthMm,
                      splitPages: v,
                      showProductCodes: p.showProductCodes,
                    ),
                  ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('طباعة كود كل صنف'),
            value: p.showProductCodes,
            onChanged: _busy
                ? null
                : (v) => setState(
                    () => _profile = ReceiptPrintProfile(
                      widthMm: p.widthMm,
                      splitPages: p.splitPages,
                      showProductCodes: v,
                    ),
                  ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await ref
                              .read(useCasesProvider)
                              .saveReceiptPrintProfile(p);
                          if (mounted) {
                            setState(() => _message = 'تم حفظ إعدادات الإيصال');
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => _message =
                                  'تعذر حفظ إعدادات الإيصال. أعد المحاولة.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.save),
                label: const Text('حفظ إعدادات الإيصال'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final printer = ref.read(
                          receiptDocumentPrinterProvider,
                        );
                        setState(() => _busy = true);
                        try {
                          final sample = SaleReceiptSnapshot(
                            invoice: SaleInvoice(
                              id: 0,
                              invoiceNo: 'TEST-ONLY',
                              subtotalMinor: 35000,
                              discountMinor: 0,
                              interestMinor: 0,
                              totalMinor: 35000,
                              paidMinor: 35000,
                              remainingMinor: 0,
                              createdAt: DateTime.now(),
                            ),
                            lines: const [
                              SaleReceiptLine(
                                productName:
                                    'اختبار عربي — خلاط زجاجي باسم طويل',
                                qty: 2,
                                unitPriceMinor: 15000,
                                lineTotalMinor: 30000,
                              ),
                              SaleReceiptLine(
                                productName: 'صنف تجريبي ثانٍ',
                                qty: 1,
                                unitPriceMinor: 5000,
                                lineTotalMinor: 5000,
                              ),
                            ],
                            payments: const [
                              SaleReceiptPayment(
                                method: PaymentMethod.cash,
                                amountMinor: 35000,
                              ),
                            ],
                            shopSettings: ShopSettingsSnapshot(
                              shopName: widget.shop.shopName,
                              phone: widget.shop.phone,
                              address: widget.shop.address,
                              receiptFooter:
                                  'صفحة اختبار فقط — لم يتم تسجيل بيع',
                            ),
                          );
                          final outcome = await printer(
                            await SaleReceiptPdf.document(sample, profile: p),
                          );
                          if (mounted) {
                            setState(
                              () => _message =
                                  outcome == ReceiptPrintOutcome.submitted
                                  ? 'تم إرسال صفحة الاختبار للطابعة'
                                  : outcome == ReceiptPrintOutcome.cancelled
                                  ? 'أُلغيت الطباعة؛ لم تُسجل عملية'
                                  : 'تعذر إرسال صفحة الاختبار. راجع الطابعة.',
                            );
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(
                              () => _message = 'تعذر تجهيز صفحة الاختبار.',
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.print),
                label: const Text('اختبار الإيصال العربي'),
              ),
            ],
          ),
          if (_message != null) Text(_message!),
          const SizedBox(height: 18),
        ],
      );
    },
  );
}
