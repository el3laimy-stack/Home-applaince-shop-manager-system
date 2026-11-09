import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:alikhlas_pos/v2/printing/sale_receipt_pdf.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [58, 80]) {
    for (final count in [1, 100, 500]) {
      test(
        '$width mm receipt with $count complete Arabic items has finite dimensions',
        () async {
          final job = await SaleReceiptPdf.document(
            sample(count),
            profile: ReceiptPrintProfile(widthMm: width),
          );
          expect(job.format.width / PdfPageFormat.mm, closeTo(width, .01));
          expect(job.format.height.isFinite, isTrue);
          expect(job.format.height, lessThanOrEqualTo(14000));
          expect(job.pageCount, greaterThanOrEqualTo(1));
          expect(job.bytes.length, greaterThan(1000));
        },
      );
    }
    test(
      '$width mm split receipt honors 250 mm page height with many pages',
      () async {
        final job = await SaleReceiptPdf.document(
          sample(100),
          profile: ReceiptPrintProfile(
            widthMm: width,
            splitPages: true,
            showProductCodes: true,
          ),
        );
        expect(job.format.height / PdfPageFormat.mm, closeTo(250, .01));
        expect(job.pageCount, greaterThan(1));
        expect(job.profile.showProductCodes, isTrue);
      },
    );
  }
  for (final width in [58, 80]) {
    test(
      '$width mm export keeps every complete row and totals together',
      () async {
        const reviewDir = String.fromEnvironment('THERMAL_REVIEW_DIR');
        final lines = [
          for (var i = 1; i <= 100; i++)
            SaleReceiptLine(
              productName:
                  'صنف عربي للمراجعة ITEM-${i.toString().padLeft(3, '0')}',
              productBarcode: 'ROW-${i.toString().padLeft(3, '0')}',
              qty: 1,
              unitPriceMinor: 123400 + i,
              lineTotalMinor: 123400 + i,
            ),
        ];
        final total = lines.fold<int>(0, (s, l) => s + l.lineTotalMinor);
        final receipt = SaleReceiptSnapshot(
          invoice: SaleInvoice(
            id: 1,
            invoiceNo: 'ATOMIC-$width',
            subtotalMinor: total,
            discountMinor: 0,
            interestMinor: 0,
            totalMinor: total,
            paidMinor: total,
            remainingMinor: 0,
            createdAt: DateTime(2026, 11, 8),
          ),
          lines: lines,
          payments: [
            SaleReceiptPayment(method: PaymentMethod.cash, amountMinor: total),
          ],
          shopSettings: const ShopSettingsSnapshot(
            shopName: 'مراجعة الطباعة STORE-SNAPSHOT',
            branchName:
                'فرع تجريبي باسم عربي طويل لاختبار التفاف السطور BRANCH-SNAPSHOT',
            receiptFooter: 'TOTALS-END',
          ),
        );
        final job = await SaleReceiptPdf.document(
          receipt,
          profile: ReceiptPrintProfile(
            widthMm: width,
            splitPages: true,
            showProductCodes: true,
          ),
        );
        expect(job.pageCount, greaterThan(1));
        if (reviewDir.isNotEmpty) {
          final dir = await Directory(reviewDir).create(recursive: true);
          await File('${dir.path}/atomic-$width.pdf').writeAsBytes(job.bytes);
        }
      },
    );
  }

  test(
    'receipt preferences roundtrip and invalid width never overwrites them',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final uc = V2UseCases(db);
      expect((await uc.receiptPrintProfile()).widthMm, 80);
      await uc.saveReceiptPrintProfile(
        const ReceiptPrintProfile(widthMm: 58, splitPages: true),
      );
      await expectLater(
        uc.saveReceiptPrintProfile(const ReceiptPrintProfile(widthMm: 90)),
        throwsArgumentError,
      );
      final p = await uc.receiptPrintProfile();
      expect(p.widthMm, 58);
      expect(p.splitPages, isTrue);
      expect(p.showProductCodes, isFalse);
    },
  );
}

SaleReceiptSnapshot sample(int count) {
  final lines = [
    for (var i = 0; i < count; i++)
      SaleReceiptLine(
        productName:
            'منتج عربي تجريبي ${i + 1} — ثلاجة شارب نوفروست باسم طويل وموديل مختلف',
        productBarcode: 'DEMO-${i + 1}',
        qty: 2,
        unitPriceMinor: 12345678,
        lineTotalMinor: 24691356,
      ),
  ];
  final total = lines.fold<int>(0, (s, l) => s + l.lineTotalMinor);
  return SaleReceiptSnapshot(
    invoice: SaleInvoice(
      id: 1,
      invoiceNo: 'TEST-$count',
      subtotalMinor: total,
      discountMinor: 0,
      interestMinor: 0,
      totalMinor: total,
      paidMinor: total,
      remainingMinor: 0,
      createdAt: DateTime(2026, 11, 7),
    ),
    lines: lines,
    payments: [
      SaleReceiptPayment(method: PaymentMethod.cash, amountMinor: total),
    ],
    shopSettings: const ShopSettingsSnapshot(
      shopName: 'اختبار حراري',
      receiptFooter: 'عينة اختبار',
    ),
  );
}
