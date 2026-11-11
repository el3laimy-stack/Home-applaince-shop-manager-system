# قدرات المشروع من الكود الفعلي

مرجع الدراسة: `000036742830d7dc37b684ff4c2a9a412c914150`؛ التطبيق 1.2.0+12؛ قاعدة البيانات 13.

قراءة الكود والاختبارات ومراجعة محلية سابقة؛ توافق أجهزة العميل يحتاج تحققًا منفصلًا.

## المعمارية والحدود

نقطة الدخول lib/main.dart تشغل v2/app/v2_app.dart. الواجهة Flutter/Riverpod، طبقة الاستخدام V2UseCases وأجزاؤها، التخزين Drift/SQLite محلي في الخلفية، دفتر أستاذ مزدوج وقيم نقدية بالوحدة الصغرى وتحقيق نطاق الأموال، مفاتيح عمليات لمنع التكرار وحواجز كتابة عند الاستعادة. الطباعة PDF بخط عربي عبر Printing. المسار الحالي يهيئ windowManager دون تكييف هاتف وشاشة دنيا 1024×720. Windows/Linux لهما بناء ومثبتات واختبارات CI؛ وجود هيكل Android لا يثبت قبول التشغيل.

Products يحتفظ برصيد صحيح واحد وقيمة تكلفة دقيقة؛ لا Warehouse/Serial/Role/Sync tables. workbenchSnapshot يجلب قوائم الأصناف والأطراف كاملة، لذلك أحجام أكبر من بيانات الاختبار تحتاج قياسًا فعليًا. لا نغيّر الجداول ولا نقرأ بيانات العملاء لتنفيذ الاستبيان.

## طريقة تصنيف الثقة

«موجودة» تعني أن تدفقًا ووظيفة وجدولًا في نقطة الدخول الحالية يثبتانها، ولا تعني ملاءمة كل سياسة عميل. «غير متاحة» تخص النسخة المفحوصة، وليست حكمًا على إمكانية Flutter. توافق الطابعة والأجهزة والقياس الفعلي على الهاتف يحتاج تحققًا منفصلًا. الأمان المحلي لا يعني تشفير ملف SQLite أو نسخ الاستبيان.

### الأصناف والتصنيفات — موجودة

اسم وتصنيف وصورة وباركود اختياري وسعر بيع وحد تنبيه؛ كميات صحيحة ومتوسط تكلفة مرجح بقيمة مخزون دقيقة.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `Products`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_catalog_party_use_cases.dart` — `createProduct/updateProduct`

### اختيار الأصناف والفواتير الكبيرة — موجودة وتحتاج تحسينًا

جدول كميات وبحث عربي ومراجعة ودفع نقدي/محفظة/تقسيط؛ الحد في المسودة 500 نوع. توجد عيوب حالة واجهة مؤكدة في الدفع والفلترة وTab.

- `Frontend/alikhlas_pos/lib/v2/app/features/v2_pos_view.dart` — `_PosViewState.build`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_purchase_view.dart` — `_PurchaseViewState`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_invoice_draft_use_cases.dart` — `SaleDraft/PurchaseDraft`

### الفواتير المعلقة واستكمال العمل — موجودة وتحتاج تحسينًا

مسودات متعددة وحفظ 500ms ومقارنة مراجعات؛ المسودة ليست حجز مخزون. استعادة طلب غير مرحّل لا تعيد كل حالة الدفع في الواجهة.

- `Frontend/alikhlas_pos/lib/v2/application/invoice_autosave.dart` — `InvoiceAutosave`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_invoice_workspace_use_cases.dart` — `saveInvoiceWorkspace`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_pos_actions.dart` — `_discardPendingSale/_discardDraft`

### الجرد وحركات المخزون — موجودة

جرد كمية فعلية مع سبب وتسوية محاسبية، أرصدة افتتاحية، تنبيه نقص، وحماية من تغير الرصيد أثناء الجرد.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_inventory_adjustment_use_cases.dart` — `reconcileInventory`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_opening_balance_use_cases.dart` — `recordOpeningBalance`

### المشتريات والموردون — موجودة وتحتاج تحسينًا

شراء نقدي وآجل وتكلفة وحدة وأقساط موردين ومرتجع شراء. تعديل الكمية قد يمسح دفعة المحفظة في واجهة الشراء.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_purchase_use_cases.dart` — `createPurchase`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_purchase_return_use_cases.dart` — `createPurchaseReturn`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_purchase_workspace.dart` — `_syncCash`

### العملاء والموردون وكشوف الحساب — موجودة

أسماء وهواتف وأرصدة مشتقة من القيود وكشوف وتفاصيل الفواتير والتحصيل والسداد؛ ليس نظام CRM كاملًا.

- `Frontend/alikhlas_pos/lib/v2/app/features/v2_parties_view.dart` — `_PartiesView`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_snapshot_report_use_cases.dart` — `partyStatement`

### التقسيط والتحصيل — موجودة

مقدم وفائدة إجمالية وجدول بعدد وفترة أيام وتاريخ بداية، تحصيل جزئي وأرصدة وتنبيه استحقاق داخل التطبيق. لا دليل على إعادة جدولة أو فوائد تأخير آلية.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_installment_use_cases.dart` — `_createInstallmentPlan/_settleInstallment`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_installments_view.dart` — `_InstallmentsView`

### قواعد تقسيط إضافية — غير متاحة

لم يُعثر على تدفقات لإعادة الجدولة أو غرامات التأخير أو حساب فائدة متناقصة أو خصم سداد مبكر مخصص.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_installment_use_cases.dart` — `_createInstallmentPlan/_settleInstallment`
- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `InstallmentPlans/InstallmentPayments`

### الخزينة والمصروفات والورديات — موجودة

كاش ومحفظة ووردية وعد فعلي ومصروفات وتصحيحات موثقة قابلة للعكس، مع موافقة رصيد سالب ومنع تكرار مالي.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_auth_shift_use_cases.dart` — `openShift/closeShift`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_financial_correction_use_cases.dart` — `recordFinancialCorrection/reverseFinancialCorrection`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_expense_use_cases.dart` — `recordExpense`

### التقارير الأساسية — موجودة

ملخص يومي ومبيعات وتكلفة وربح ومصروفات وأرصدة ومستحقات وتصدير PDF؛ ليست كل أبعاد التحليل التجارية متاحة.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_snapshot_report_use_cases.dart` — `dashboardSnapshot/periodReport`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_reports_view.dart` — `_ReportsView`
- `Frontend/alikhlas_pos/lib/v2/printing/report_summary_pdf.dart` — `ReportSummaryPdf`

### تقارير تحليلية مخصصة — غير متاحة

لا توجد أبعاد تشغيلية للربح حسب الفرع أو الموظف؛ تقارير البطيء الدوران وتخصيص اللوحات تحتاج تصميمًا وفق القرار المطلوب.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `SaleInvoices/Products`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_reports_view.dart` — `_ReportsView`

### الإيصال الحراري والملصقات — موجودة

PDF عربي 58/80مم ومعاينة وتقسيم 250مم وحفظ ثم طباعة، ملصقات بأبعاد محددة وكشوف وتقارير PDF. الطباعة العامة A4 لا تعني قالب فاتورة ضريبية A4.

- `Frontend/alikhlas_pos/lib/v2/printing/sale_receipt_pdf.dart` — `SaleReceiptPdf/ReceiptPrintJob`
- `Frontend/alikhlas_pos/lib/v2/printing/barcode_labels_pdf.dart` — `BarcodeLabelsPdf`
- `Frontend/alikhlas_pos/lib/v2/app/shared/v2_receipt_settings.dart` — `_ReceiptSettings`

### توافق طابعة ودرج النقدية وأجهزة العميل — تحتاج تحققًا

لم تُختبر أجهزة العميل الفعلية. لا يظهر تحكم مباشر في درج النقدية؛ لا يجوز استنتاج دعمه من وجود طباعة PDF.

- `Frontend/alikhlas_pos/lib/v2/printing/sale_receipt_pdf.dart` — `Printing.layoutPdf`
- `Frontend/alikhlas_pos/lib/main.dart` — `main`

### قوالب فواتير A4 أو متطلبات ضريبية خاصة — غير متاحة

فاتورة البيع الحرارية موجودة؛ لم يُعثر على تكامل ضريبي/فاتورة إلكترونية مصرية أو قالب A4 مخصص بهذه المتطلبات.

- `Frontend/alikhlas_pos/lib/v2/printing/sale_receipt_pdf.dart` — `SaleReceiptPdf.document`
- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `SaleInvoices`

### النسخ الاحتياطي والاستعادة — موجودة

نسخ محلي تلقائي بفاصل 30 دقيقة وإدارة احتفاظ، ونسخة محمولة بصور وفحص وترحيل مرحلي واستعادة مع حواجز كتابة وتعافٍ.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_backup_settings_use_cases.dart` — `runAutomaticBackupIfDue/restoreFromBackup`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_portable_backup_use_cases.dart` — `createPortableBackup/restoreFromPortableBackup`

### إدخال ونقل بيانات قديمة — موجودة

استيراد أصناف CSV مع معاينة والتحقق. لا دليل على استيراد شامل تلقائي لأرصدة وعقود وفواتير قديمة؛ الأرصدة الافتتاحية لها مستندات مستقلة.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_product_csv_import_use_cases.dart` — `previewProductCsv/importProductCsv`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_opening_balance_use_cases.dart` — `recordOpeningBalance`

### حسابات موظفين وصلاحيات واعتمادات — غير متاحة

تدفق مالك واحد؛ جدول Users لا يحتوي أدوارًا أو صلاحيات، ولا توجد إدارة موظفين أو اعتماد حسب الدور.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `Users`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_auth_shift_use_cases.dart` — `createInitialOwner/login`
- `Frontend/alikhlas_pos/lib/v2/app/shell/v2_shell.dart` — `_WorkbenchShell`

### سجل مراجعة منسوب لكل موظف — غير متاحة

توجد قيود ومستندات وتصحيحات وسجل تشخيصي؛ لا تعادل سجل مراجعة مفصلًا قبل/بعد لكل موظف وصلاحية واعتماد.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `LedgerEntries/FinancialCorrections/Users`
- `Frontend/alikhlas_pos/lib/v2/application/v2_diagnostic_logger.dart` — `V2DiagnosticLogger`

### أمان الوصول المحلي — موجودة

PBKDF2 بكلمات مرور مملحة واستعادة وصول وحد محاولات وقفل ملف لمنع فتح نفس البيانات مرتين. قاعدة البيانات ليست موثقة كتشفير شامل.

- `Frontend/alikhlas_pos/lib/v2/application/v2_use_cases.dart` — `_passwordIterations/_hashPassword`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_auth_shift_use_cases.dart` — `login/recoverOwnerAccess`
- `Frontend/alikhlas_pos/lib/v2/data/application_lock.dart` — `ApplicationLock`

### تتبع كل جهاز برقمه التسلسلي — غير متاحة

المخزون مجمّع حسب productId؛ لا جداول لأفراد الأجهزة أو ربط الرقم التسلسلي بضمان وبيع ومرتجع.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `Products/SaleItems/PurchaseItems`

### الصيانة والتوصيل والتركيب والضمان — غير متاحة

لا تدفقات أو جداول أوامر صيانة وتوصيل وتركيب أو مطالبات ضمان أو قطع غيار؛ المرتجع المالي موجود ولا يمثل خدمة ما بعد البيع.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `tables`
- `Frontend/alikhlas_pos/lib/v2/app/shell/v2_shell.dart` — `_Section`

### المخازن المتعددة والحجز وحالات المخزون — غير متاحة

رصيد واحد لكل صنف؛ لا warehouseId أو تحويل مخازن أو حجز للطلبات أو حالات معروض/تالف مستقلة.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `Products/StockMovements`

### وحدات ومقاسات وبيع بالكسر — غير متاحة

الكميات IntColumn وخطوط الفواتير أعداد صحيحة، ولا تحويل وحدات أو متغيرات مستقلة مهيكلة.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `Products.stockQty/SaleItems.qty/PurchaseItems.qty`

### تطبيق Android تشغيلي — تحتاج تحققًا

Flutter وملفات منصة لا تكفي لإثبات الدعم. main يهيئ windowManager وشاشة دنيا 1024×720، والاختبارات ومسار الإصدار موجهان لسطح المكتب؛ يحتاج تكييفًا واختبار أجهزة.

- `Frontend/alikhlas_pos/lib/main.dart` — `main/windowManager/minimumSize`
- `Frontend/alikhlas_pos/pubspec.yaml` — `window_manager/printing`
- `.github/workflows/windows-build.yml` — `build-windows/build-linux`

### تعدد الأجهزة والفروع والمزامنة — غير متاحة

SQLite محلي وقفل لبيانات جهاز واحد؛ لا API أو خادم أو هوية أجهزة أو بروتوكول مزامنة. لا يُستخدم نسخ ملف SQLite كبديل للمزامنة.

- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `openAppConnection`
- `Frontend/alikhlas_pos/lib/v2/data/application_lock.dart` — `ApplicationLock`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_operation_receipt_helpers.dart` — `_runIdempotentFinancialOperation`

### تنبيهات خارج التطبيق والتواصل التلقائي — غير متاحة

تنبيه الاستحقاق داخل الواجهة موجود؛ لا push أو SMS أو WhatsApp آلي موثق.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_snapshot_report_use_cases.dart` — `installmentAlerts`
- `Frontend/alikhlas_pos/lib/v2/app/features/v2_installments_view.dart` — `_InstallmentsView`

### تجارة إلكترونية وتكاملات خارجية — غير متاحة

لا طبقة تكامل تجارة إلكترونية أو دفع خارجي أو API متزامن في النسخة الحالية.

- `Frontend/alikhlas_pos/lib/v2/application/v2_use_cases.dart` — `V2UseCases`
- `Frontend/alikhlas_pos/lib/v2/data/app_database.dart` — `tables`

### المرتجعات المالية المرتبطة بالفاتورة — موجودة

مرتجع بيع وشراء مرتبط بسطر الفاتورة مع حدود الكمية السابقة ورد نقدي أو خصم مديونية وفائض مسترد؛ ليس سير خدمة ضمان أو استبدال مستقلًا.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_sale_return_use_cases.dart` — `createSaleReturn`
- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_purchase_return_use_cases.dart` — `createPurchaseReturn`

### متابعة للمالك من الهاتف بدون تنفيذ عمليات — غير متاحة

التقارير محلية في تطبيق سطح المكتب؛ لا لوحة متابعة بعيدة أو قناة نشر آمنة حاليًا. احتياج القراءة فقط لا يبرر نقل محرك البيع أو بناء مزامنة كتابة كاملة.

- `Frontend/alikhlas_pos/lib/v2/application/use_cases/v2_snapshot_report_use_cases.dart` — `dashboardSnapshot`
- `Frontend/alikhlas_pos/lib/main.dart` — `main`

### إيصال تحصيل مستقل — غير متاحة

التحصيل وكشف الحساب موجودان، لكن مسار التقسيط الحالي لا يطبع مستند إيصال مستقل لكل دفعة؛ إيصال البيع الحراري لا يثبت هذه الوظيفة.

- `Frontend/alikhlas_pos/lib/v2/app/features/v2_installments_view.dart` — `_InstallmentsViewState._payInstallment`
- `Frontend/alikhlas_pos/lib/v2/printing/party_statement_pdf.dart` — `PartyStatementPdf`

## عيوب مؤكدة منفصلة عن أقوال العميل

أعيد إنتاجها في مراجعة سابقة باختبارات واجهة مستقلة؛ لا يقال إن العميل واجهها إلا لو قال ذلك. لا تُصلح في هذه المهمة.
- `PAY-01` مسح دفعة المحفظة عند تعديل كمية شراء — `Frontend/alikhlas_pos/lib/v2/app/features/v2_purchase_workspace.dart:76`؛ اختبار القبول: دفعة محفظة 25 تظل 25 بعد تغيير الكمية، وتوزيع الدفع يظل ظاهرًا وصحيحًا.
- `PAY-02` فقد حالة الكاش التلقائي بعد إعادة طلب غير مرحل للتعديل — `Frontend/alikhlas_pos/lib/v2/app/features/v2_pos_actions.dart:136`؛ اختبار القبول: الرجوع من طلب غير مرحل ثم تغيير الإجمالي 200 إلى 300 يُعيد الكاش التلقائي إلى 300.
- `PAY-03` بقاء طريقة المحفظة بعد مسح المسودة — `Frontend/alikhlas_pos/lib/v2/app/features/v2_pos_actions.dart:538`؛ اختبار القبول: مسح مسودة محفظة يبدأ فاتورة نقدية افتراضية جديدة بقيم نظيفة.
- `UX-01` فلتر المختار فقط ينتقل لفاتورة جديدة فارغة — `Frontend/alikhlas_pos/lib/v2/app/features/v2_pos_workspace.dart:190`؛ اختبار القبول: تعليق فاتورة بفلتر المختار فقط يبدأ أخرى تُظهر المخزون المتاح في البيع والشراء.
- `UX-02` Tab يحبس التركيز عند حافة جدول الكميات — `Frontend/alikhlas_pos/lib/v2/app/shared/v2_checkout_widgets.dart:94`؛ اختبار القبول: Tab وShift+Tab عند حافة الجدول ينتقلان إلى عنصر مناسب دون حبس التركيز.
