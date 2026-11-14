import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../application/v2_use_cases.dart';
import '../core/money.dart';
import 'pdf_fonts.dart';

enum ReceiptPrintOutcome { submitted, cancelled, failed }

class ReceiptPrintJob {
  const ReceiptPrintJob({
    required this.receipt,
    required this.bytes,
    required this.format,
    required this.profile,
    required this.pageCount,
  });
  final SaleReceiptSnapshot receipt;
  final Uint8List bytes;
  final PdfPageFormat format;
  final ReceiptPrintProfile profile;
  final int pageCount;
}

class SaleReceiptPdf {
  const SaleReceiptPdf._();

  /// Kept for integrations using the former printing entry point.
  static Future<void> printReceipt(SaleReceiptSnapshot receipt) async {
    final result = await printJob(await document(receipt));
    if (result == ReceiptPrintOutcome.failed) {
      throw StateError('Receipt printing failed');
    }
  }

  static Future<ReceiptPrintOutcome> printJob(ReceiptPrintJob job) async {
    try {
      final sent = await Printing.layoutPdf(
        name: job.receipt.invoice.invoiceNo,
        format: job.format,
        dynamicLayout: false,
        onLayout: (_) async => job.bytes,
      );
      return sent
          ? ReceiptPrintOutcome.submitted
          : ReceiptPrintOutcome.cancelled;
    } catch (_) {
      return ReceiptPrintOutcome.failed;
    }
  }

  static Future<Uint8List> build(
    SaleReceiptSnapshot receipt, {
    ReceiptPrintProfile profile = const ReceiptPrintProfile(),
  }) async => (await document(receipt, profile: profile)).bytes;

  static Future<ReceiptPrintJob> document(
    SaleReceiptSnapshot receipt, {
    ReceiptPrintProfile profile = const ReceiptPrintProfile(),
  }) async {
    if (!profile.isValid) throw ArgumentError('Unsupported thermal width');
    final fonts = await PdfFonts.loadCairo();
    final regular = fonts.regular;
    final bold = fonts.bold;
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final format = PdfPageFormat(
      profile.widthMm * PdfPageFormat.mm,
      profile.splitPages ? 250 * PdfPageFormat.mm : double.infinity,
      // An 80 mm roll typically has a centered 72 mm printable area.
      // Reserve extra space on the right to shift Arabic receipts left.
      // The 70 mm layout leaves room for strokes and Cairo glyph overhang.
      marginLeft: (profile.widthMm == 80 ? 4.5 : 4) * PdfPageFormat.mm,
      marginRight: (profile.widthMm == 80 ? 5.5 : 4) * PdfPageFormat.mm,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
    );
    final style = pw.TextStyle(
      font: regular,
      fontSize: profile.widthMm == 58 ? 8 : 9,
    );
    pw.Widget text(String value, {bool strong = false}) => pw.Text(
      value,
      textDirection: pw.TextDirection.rtl,
      style: strong ? style.copyWith(font: bold) : style,
    );
    pw.Widget amount(String label, int minor) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Wrap(
        alignment: pw.WrapAlignment.spaceBetween,
        children: [text(label, strong: true), text(_number(minor))],
      ),
    );
    pw.Widget header() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(child: text(receipt.shopSettings.shopName, strong: true)),
        pw.Center(child: text('الفرع: ${receipt.shopSettings.branchName}')),
        pw.Center(
          child: text('التاريخ: ${_dateTime(receipt.invoice.createdAt)}'),
        ),
        pw.Center(
          child: text('${receipt.documentTitle} ${receipt.invoice.invoiceNo}'),
        ),
        pw.Divider(),
      ],
    );
    final content = <pw.Widget>[
      if (receipt.shopSettings.phone != null)
        text('هاتف المحل: ${receipt.shopSettings.phone}'),
      if (receipt.shopSettings.address != null)
        text(receipt.shopSettings.address!),
      text(
        '${receipt.documentTitle == 'فاتورة شراء' ? 'المورد' : 'العميل'}: ${receipt.customerName ?? 'نقدي'}',
      ),
      text(
        '${receipt.lines.length} نوع · ${receipt.lines.fold<BigInt>(BigInt.zero, (s, l) => s + BigInt.from(l.qty))} قطعة',
      ),
      text('الأسعار بالجنيه المصري'),
      if (receipt.hasLegacyProductIdentity) text(legacyProductIdentityNotice),
      pw.Divider(),
      for (var index = 0; index < receipt.lines.length; index++)
        pw.Inseparable(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: .3)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                text(
                  '${index + 1}. ${receipt.lines[index].productName}',
                  strong: true,
                ),
                if (profile.showProductCodes &&
                    receipt.lines[index].productBarcode != null)
                  text(receipt.lines[index].productBarcode!),
                pw.SizedBox(height: 2),
                text(
                  '${receipt.lines[index].qty} × ${_number(receipt.lines[index].unitPriceMinor)}',
                ),
                text(
                  'الإجمالي: ${_number(receipt.lines[index].lineTotalMinor)}',
                ),
              ],
            ),
          ),
        ),
      pw.Inseparable(
        child: pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              amount('الإجمالي', receipt.invoice.subtotalMinor),
              if (receipt.invoice.discountMinor > 0)
                amount('الخصم', receipt.invoice.discountMinor),
              if (receipt.invoice.interestMinor > 0)
                amount('فائدة التقسيط', receipt.invoice.interestMinor),
              amount('المطلوب', receipt.invoice.totalMinor),
              amount('المدفوع', receipt.invoice.paidMinor),
              if (receipt.invoice.remainingMinor > 0)
                amount('المتبقي', receipt.invoice.remainingMinor),
              for (final payment in receipt.payments)
                amount(_method(payment.method), payment.amountMinor),
              if (receipt.shopSettings.receiptFooter != null) ...[
                pw.SizedBox(height: 6),
                pw.Center(child: text(receipt.shopSettings.receiptFooter!)),
              ],
            ],
          ),
        ),
      ),
    ];
    pw.Page? continuous;
    if (profile.splitPages) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: format,
          maxPages: 500,
          textDirection: pw.TextDirection.rtl,
          header: (_) => header(),
          footer: (c) => pw.Center(
            child: text(
              '${receipt.invoice.invoiceNo} · ${c.pageNumber}/${c.pagesCount}',
            ),
          ),
          build: (_) => content,
        ),
      );
    } else {
      continuous = pw.Page(
        pageFormat: format,
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [header(), ...content],
        ),
      );
      doc.addPage(continuous);
    }
    final bytes = await doc.save();
    final actualFormat = continuous?.pageFormat ?? format;
    // Very long documents exceed the portable PDF page coordinate range.
    if (!profile.splitPages && actualFormat.height > 14000) {
      return document(
        receipt,
        profile: ReceiptPrintProfile(
          widthMm: profile.widthMm,
          splitPages: true,
          showProductCodes: profile.showProductCodes,
          autoPrintAfterSale: profile.autoPrintAfterSale,
        ),
      );
    }
    return ReceiptPrintJob(
      receipt: receipt,
      bytes: bytes,
      format: actualFormat,
      profile: profile,
      pageCount: doc.document.pdfPageList.pages.length,
    );
  }

  static String _number(int minor) =>
      Money(minor).formatPlain(symbol: '').trim();
  static String _dateTime(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  static String _method(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'كاش',
    PaymentMethod.wallet => 'محفظة',
    PaymentMethod.installment => 'تقسيط',
  };
}
