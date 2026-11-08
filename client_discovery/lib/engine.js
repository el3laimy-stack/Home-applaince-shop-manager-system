/* Shared, dependency-free rules and validation. Used unchanged in the browser and Node. */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.Discovery = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const VERSION = '1.0.0';
  const UNKNOWN = new Set(['unsure', 'suggest', 'na']);
  const TYPES = new Set(['single', 'multi', 'text', 'rating', 'pain', 'timeline', 'priorities', 'access']);
  const PHASES = ['المرحلة 0 — الثبات ومخاطر التشغيل', 'المرحلة 1 — ضروريات العميل', 'المرحلة 2 — الإنتاجية وسهولة الاستخدام', 'المرحلة 3 — التوسع والتكامل والهاتف عند ثبوت الحاجة', 'المرحلة 4 — اختيارات مستقبلية'];
  const clone = x => JSON.parse(JSON.stringify(x));
  const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
  const present = x => x !== undefined && x !== null && x !== '' && (!Array.isArray(x) || x.length > 0);
  const has = (a, k, v) => Array.isArray(a[k]) && a[k].includes(v);
  const picked = (a, k) => present(a[k]) && !UNKNOWN.has(a[k]);
  const includesAny = (a, k, vs) => vs.some(v => has(a, k, v));
  const frequencyLabel = v => ({daily:'يوميًا',weekly:'أسبوعيًا',monthly:'شهريًا',rare:'نادرًا',unsure:'غير متأكد'}[v] || 'غير محدد');
  const consequenceLabel = v => ({delay:'تأخير وإعادة عمل',errors:'أخطاء حساب أو مخزون',loss:'فقد مبيعات أو تكلفة إضافية',stops:'توقف الشغل',minor:'إزعاج محدود',unsure:'غير متأكد'}[v] || 'غير محددة');
  const priorityLabel = v => ({must:'ضروري للتشغيل',soon:'مهم قريبًا',nice:'تحسين مرغوب',future:'فكرة مستقبلية',no:'غير مطلوب',unsure:'غير متأكد',unconfirmed:'لم يعتمدها العميل'}[v] || 'لم تُحدد');
  const htmlSafeMarkdown = x => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\|/g, '\\|').replace(/[\r\n]+/g, ' / ');
  function baseMatch(c, a, readable) {
    if (!c) return true;
    if (c.repeat) return true;
    if (c.all) return c.all.every(x => baseMatch(x, a, readable));
    if (c.any) return c.any.some(x => baseMatch(x, a, readable));
    if (c.not) return !baseMatch(c.not, a, readable);
    if (readable && !readable(c.question)) return false;
    const v = a[c.question];
    if (!present(v)) return false;
    if (c.op === 'eq') return Array.isArray(v) ? v.includes(c.value) : v === c.value;
    if (c.op === 'neq') return Array.isArray(v) ? !v.includes(c.value) : v !== c.value;
    if (c.op === 'contains') return Array.isArray(v) && v.includes(c.value);
    if (c.op === 'in') return c.value.includes(v);
    if (c.op === 'timelineContains') return object(v) && Object.values(v).includes(c.value);
    return false;
  }
  function expandQuestions(config) {
    const out = [];
    for (const q of config.questions) {
      if (!q.repeatFrom) out.push(q);
      else {
        const source = config.questions.find(x => x.id === q.repeatFrom);
        for (const value of q.repeatOptions) {
          const option = source.options.find(x => x.value === value);
          out.push({ ...q, id: q.id + '.' + value, label: option.label, when: { question: q.repeatFrom, op: 'contains', value }, problem: value });
        }
      }
    }
    return out;
  }
  function baseVisible(config, answers) {
    const qs = expandQuestions(config), map = new Map(qs.map(q => [q.id, q])), cache = new Map(), visiting = new Set();
    function visible(id) {
      if (cache.has(id)) return cache.get(id);
      const q = map.get(id);
      if (!q || q.when?.derived || visiting.has(id)) return false;
      visiting.add(id);
      const result = baseMatch(q.when, answers, visible);
      visiting.delete(id); cache.set(id, result); return result;
    }
    return qs.filter(q => visible(q.id));
  }
  function baseAnswers(config, answers) {
    const out = {};
    for (const q of baseVisible(config, answers)) if (Object.hasOwn(answers, q.id)) out[q.id] = answers[q.id];
    return out;
  }
  function needSeeds(config, raw) {
    const a = baseAnswers(config, raw), needs = new Map();
    function add(id, q, why, direct = true) {
      if (!present(a[q]) || UNKNOWN.has(a[q])) return;
      if (!needs.has(id)) needs.set(id, { id, evidence: [], reasons: [], direct });
      const n = needs.get(id);
      if (!n.evidence.includes(q)) n.evidence.push(q);
      if (!n.reasons.includes(why)) n.reasons.push(why);
      n.direct = n.direct && direct;
    }
    if (present(a['business.activity']) && !has(a, 'business.activity', 'unsure')) add('catalog', 'business.activity', 'مطابقة تعريف الأصناف لنوع النشاط');
    if (picked(a, 'volume.lines')) add('checkout', 'volume.lines', 'اختيار واختبار فاتورة بحجم العمل المعلن');
    if (has(a, 'workflow.sale', 'quote')) add('drafts', 'workflow.sale', 'طلبات أو عروض قبل البيع: المسودة الحالية لا تكفي لإثبات دورة عروض أسعار كاملة');
    if (includesAny(a, 'workflow.sale', ['deposit', 'delivery'])) add('warehouses', 'workflow.sale', 'الحجز أو التسليم اللاحق يحتاج فصل المتاح والمحجوز');
    if (present(a['workflow.entry']) && !UNKNOWN.has(a['workflow.entry'])) add(a['workflow.entry'] === 'sheet' ? 'import' : 'purchases', 'workflow.entry', 'مطابقة استلام البضاعة والتكلفة لطريقة العمل');
    if (includesAny(a, 'workflow.pricing', ['customer', 'offers', 'negotiated'])) add('checkout', 'workflow.pricing', 'تحديد قواعد التسعير والخصم قبل تغيير الواجهة');
    const painMap = { search: 'checkout', invoice: 'checkout', stock: 'stock', collections: 'installments', accounting: 'reports', returns: 'returns', printing: 'printing', learning: 'checkout', backup: 'backup', manual: 'import' };
    for (const p of a['pain.selected'] || []) if (painMap[p]) add(painMap[p], 'pain.selected', 'وردت مشكلة تشغيلية محددة: ' + p);
    const manualMap = { stock: 'stock', debts: 'installments', service: 'services', reports: 'reports', customers: 'parties', documents: 'printing' };
    for (const v of a['workflow.manual'] || []) if (manualMap[v]) add(manualMap[v], 'workflow.manual', 'يوجد عمل يدوي مرتبط بهذا المجال');
    if (includesAny(a, 'printing.formats', ['80', '58', 'digital'])) add('printing', 'printing.formats', 'تجربة قالب ومقاس الفاتورة المطلوبة');
    if (has(a, 'printing.formats', 'a4') || has(a, 'printing.fields', 'tax')) add('invoice_layout', has(a, 'printing.formats', 'a4') ? 'printing.formats' : 'printing.fields', 'قالب فاتورة أو متطلبات ضريبية محددة تحتاج اعتمادًا مستقلًا');
    if (has(a, 'printing.fields', 'serial')) add('serials', 'printing.fields', 'طلب عرض الرقم التسلسلي على المستند');
    if (includesAny(a, 'printing.hardware', ['receipt', 'a4', 'scanner', 'label', 'drawer'])) add('hardware', 'printing.hardware', 'التحقق من أجهزة العميل الفعلية');
    if (a['printing.shared'] === 'yes') add('hardware', 'printing.shared', 'مشاركة طابعة من أجهزة متعددة ليست مزامنة بيانات بالضرورة');
    if (includesAny(a, 'finance.methods', ['cash', 'wallet', 'mixed'])) add('treasury', 'finance.methods', 'مطابقة تسجيل طرق الدفع والأرصدة الفعلية');
    if (has(a, 'finance.methods', 'card')) add('integrations', 'finance.methods', 'يلزم توضيح: تسجيل تحويل يدوي أم تسوية مزود دفع، ولا يُفترض ربط آلي');
    if (['rare', 'some', 'most'].includes(a['finance.installments'])) add('installments', 'finance.installments', 'تقسيط أو آجل مستخدم بالفعل');
    if (has(a, 'finance.methods', 'installment') && a['finance.installments'] === 'never' && a['clarify.finance'] === 'rare') add('installments', 'clarify.finance', 'تم توضيح وجود حالات تقسيط نادرة');
    if (includesAny(a, 'finance.rule', ['variable', 'declining']) || includesAny(a, 'finance.exceptions', ['early', 'late', 'reschedule'])) add('installment_rules', includesAny(a, 'finance.rule', ['variable', 'declining']) ? 'finance.rule' : 'finance.exceptions', 'قاعدة عقد أو تسوية إضافية غير مثبتة في المحرك الحالي');
    if (['calendar','negotiated'].includes(a['finance.schedule'])) add('installment_rules', 'finance.schedule', 'مواعيد تقويمية أو متغيرة تختلف عن جدول فترة الأيام الثابتة');
    if (has(a, 'finance.receipts', 'receipt')) add('collection_receipts', 'finance.receipts', 'إيصال تحصيل مستقل يحتاج نموذجًا متفقًا عليه، لا استنتاج دعم من فاتورة البيع');
    if (has(a, 'finance.receipts', 'statement')) add('parties', 'finance.receipts', 'مراجعة كشف الحساب والتحصيل');
    if (has(a, 'finance.receipts', 'external')) add('notifications', 'finance.receipts', 'طلب تنبيه أو رسالة خارج البرنامج');
    if (has(a, 'finance.receipts', 'field')) add('android', 'finance.receipts', 'محصل خارج المحل: تقييم وسيلة عمل مناسبة دون إلزام Android كامل', false);
    if (includesAny(a, 'finance.profit', ['gross','net','cash'])) add('reports', 'finance.profit', 'اعتماد تعريف الربح والتكلفة والمصروفات وحركة النقدية');
    if (['paper','approval'].includes(a['finance.expenses'])) add('treasury','finance.expenses','طريقة تسجيل أو اعتماد المصروف تحتاج مطابقة الموجود.');
    if (['per_shift','per_user'].includes(a['finance.shifts'])) add('treasury','finance.shifts','عهدة أو وردية مستقلة تحتاج حدودًا وصلاحيات واضحة.');
    if (includesAny(a,'inventory.catalogDetails',['brand','model','variant','accessories'])) add('catalog','inventory.catalogDetails','حقول تمييز الأصناف تحتاج تجربة البحث ثم تحديد الفرق عن الاسم والتصنيف الحاليين.');
    if (picked(a,'priority.backup')) add('backup','priority.backup','مكان النسخة واختبار استرجاعها يحتاجان خطة تناسب فقد الجهاز.');
    if (picked(a,'priority.recovery')) add('backup','priority.recovery','حد فقد البيانات المعلن معيار قبول، لا وعد بأن النسخ الحالية تمنع الفقد.');
    if (has(a, 'finance.profit', 'collected')) add('advanced_reports', 'finance.profit', 'تعريف ربح التقسيط المحقق بالتحصيل يختلف عن ربح الفاتورة ويلزم مراجعته');
    if (includesAny(a, 'finance.reports', ['sales', 'debts', 'stock'])) add('reports', 'finance.reports', 'تقارير تُستخدم لاتخاذ قرار لدى العميل');
    if (includesAny(a, 'finance.reports', ['slow', 'branch', 'employee', 'custom'])) add('advanced_reports', 'finance.reports', 'طلب أبعاد أو تقرير مخصص يحتاج تعريف أرقام ومصدرها');
    if (['serial', 'future'].includes(a['inventory.identity'])) add('serials', 'inventory.identity', 'تتبع هوية كل جهاز؛ المستقبل لا يعني ضرورة فورية');
    if (['separate', 'branches', 'future'].includes(a['inventory.locations'])) add('warehouses', 'inventory.locations', 'أرصدة مواقع منفصلة أو تحويلات');
    if (includesAny(a, 'inventory.units', ['packs', 'fractions', 'variants', 'bundles'])) add('units', 'inventory.units', 'تحويل وحدات أو كسور أو متغيرات وملحقات لها رصيد');
    if (includesAny(a, 'inventory.states', ['reserved', 'display', 'damaged', 'consignment'])) add('warehouses', 'inventory.states', 'فصل حالات الرصيد عن المتاح للبيع');
    if (present(a['inventory.count']) && !UNKNOWN.has(a['inventory.count'])) add('stock', 'inventory.count', 'اختبار طريقة الجرد الحالية');
    if (includesAny(a, 'inventory.returnPolicy', ['invoice', 'refund', 'condition'])) add('returns', 'inventory.returnPolicy', 'مراجعة مرتجع مرتبط بالفاتورة والتسوية المالية');
    if (has(a, 'inventory.returnPolicy', 'exchange')) add('services', 'inventory.returnPolicy', 'طلب استبدال بفرق سعر يحتاج تدفقًا واضحًا وربط المستندات');
    if (['manual', 'system', 'informal', 'suggest'].includes(a['service.workflow']) && a['service.workflow'] !== 'suggest') add('services', 'service.workflow', 'تسجيل وتتبع خدمات قائمة بالفعل');
    if (present(a['people.roles']) && !includesAny(a, 'people.roles', ['none', 'unsure'])) add('roles', 'people.roles', 'حسابات مستقلة لأدوار محددة');
    if (present(a['people.permissions']) && !includesAny(a, 'people.permissions', ['none', 'suggest'])) add('roles', 'people.permissions', 'قواعد تقييد أو اعتماد صريحة');
    for (const [id,value] of Object.entries(a)) if(id.startsWith('people.access.') && object(value) && Object.keys(value).length) add('roles', id, 'سياسة دور كما حددها العميل');
    if (a['people.audit'] === 'yes') add('audit', 'people.audit', 'سجل من نفذ وعدل واعتمد العملية');
    if (a['mobile.need'] === 'view' && a['clarify.mobileScope'] !== 'operations') add('owner_dashboard', 'mobile.need', 'متابعة فقط؛ لا يُفترض Android أصلي أو محرك مزامنة كتابة');
    else if (['view', 'operations'].includes(a['mobile.need'])) add('android', 'mobile.need', 'تنفيذ مهام على الهاتف يحتاج تحديد نطاق التطبيق وتكييف المنصة');
    if (a['mobile.sync'] === 'yes' && (a['mobile.need'] !== 'view' || a['clarify.mobileScope'] === 'operations')) add('sync', 'mobile.sync', 'طلب تبادل بيانات النشاط بين الهاتف والكمبيوتر، ونطاق الكتابة يحتاج اعتمادًا');
    if (a['workflow.shared'] === 'shared') add('sync', 'workflow.shared', 'طلب صريح لنفس البيانات والأرصدة بين الأجهزة أو الفروع');
    if (present(a['mobile.notifications']) && !includesAny(a, 'mobile.notifications', ['none', 'suggest'])) add('notifications', 'mobile.notifications', 'أحداث مطلوب وصول تنبيه عنها');
    if (present(a['future.integrations']) && !includesAny(a, 'future.integrations', ['none', 'unsure'])) add(has(a, 'future.integrations', 'tax') ? 'invoice_layout' : 'integrations', 'future.integrations', 'تكامل له استخدام معلن؛ موعده وأولوية تنفيذه يحتاجان تأكيدًا');
    return [...needs.values()];
  }
  function visibleQuestions(config, answers) {
    const active = new Set(baseVisible(config, answers).map(q => q.id));
    const needs = needSeeds(config, answers).length > 0;
    return expandQuestions(config).filter(q => q.when?.derived === 'hasNeeds' ? needs : active.has(q.id));
  }
  function pages(config, answers) {
    const visible = visibleQuestions(config, answers), result = [];
    for (const section of config.sections) {
      const rows = visible.filter(q => q.section === section.id);
      let chunk = [];
      const flush = () => { if (chunk.length) { result.push({ id: chunk[0].id, section, questions: chunk }); chunk = []; } };
      for (const q of rows) {
        if (q.type === 'priorities') {
          flush(); const ns=needSeeds(config,answers);
          for(let i=0;i<ns.length;i+=6){const rowIds=ns.slice(i,i+6).map(n=>n.id);result.push({id:q.id+'.'+rowIds[0],section,questions:[{...q,rowIds,label:q.label+' — جزء '+(Math.floor(i/6)+1)+' من '+Math.ceil(ns.length/6)}]});}
        }
        else if (['pain', 'timeline', 'access'].includes(q.type)) { flush(); result.push({ id: q.id, section, questions: [q] }); }
        else { chunk.push(q); if (chunk.length === 2) flush(); }
      }
      flush();
    }
    return result;
  }
  function answered(q, value, config, answers) {
    if (!present(value)) return false;
    if (q.type === 'pain') return present(value.frequency) && present(value.impact) && present(value.consequence);
    if (q.type === 'access') return ['finance','pricing','returns','stock','export'].every(k => present(value[k]));
    if (q.type === 'timeline') return ['3', '6', '12', '24'].every(k => present(value[k]));
    if (q.type === 'priorities') return (q.rowIds || needSeeds(config, answers).map(n=>n.id)).every(id => present(value[id]));
    return true;
  }
  function progress(config, envelope) {
    const qs = visibleQuestions(config, envelope.answers);
    const done = qs.filter(q => answered(q, envelope.answers[q.id], config, envelope.answers) || envelope.skippedIds.includes(q.id)).length;
    return { total: qs.length, done, percent: qs.length ? Math.round(100 * done / qs.length) : 0, unanswered: qs.filter(q => q.required && !answered(q, envelope.answers[q.id], config, envelope.answers) && !envelope.skippedIds.includes(q.id)).map(q => q.id) };
  }
  function newEnvelope(config, commit) {
    const now = new Date().toISOString();
    return { schemaVersion: VERSION, questionnaireId: config.id, questionnaireVersion: config.version, projectCommit: commit, responseId: 'r-' + (typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : now.replace(/\W/g, '') + '-' + Math.random().toString(36).slice(2)), createdAt: now, updatedAt: now, completedAt: null, reviewedAt: null, answers: {}, skippedIds: [], cursor: null, extensions: {} };
  }
  function validateConfig(config, catalog) {
    const errors = [], ids = new Set(), sections = new Set(config.sections?.map(s => s.id));
    if (config.schemaVersion !== VERSION || !Array.isArray(config.questions)) return ['صيغة تعريف الأسئلة غير مدعومة'];
    for (const q of config.questions) {
      if (!/^[a-z][a-zA-Z0-9_.-]{1,80}$/.test(q.id) || ids.has(q.id)) errors.push('معرّف سؤال مكرر أو غير صحيح: ' + q.id);
      ids.add(q.id);
      if (!sections.has(q.section) || !TYPES.has(q.type) || !q.decision || !q.label) errors.push('تعريف سؤال غير مكتمل: ' + q.id);
      if (['single', 'multi'].includes(q.type) && (!Array.isArray(q.options) || new Set(q.options.map(o => o.value)).size !== q.options.length)) errors.push('اختيارات غير صحيحة: ' + q.id);
    }
    function condition(c) {
      if (!c) return;
      if (c.question && !ids.has(c.question)) errors.push('شرط يشير لسؤال غير موجود: ' + c.question);
      if (c.derived && c.derived !== 'hasNeeds') errors.push('شرط مشتق غير معروف');
      if (c.op && !['eq', 'neq', 'contains', 'in', 'timelineContains'].includes(c.op)) errors.push('عامل شرط غير معروف');
      for (const key of ['all', 'any']) for (const x of c[key] || []) condition(x);
      if (c.not) condition(c.not);
    }
    for (const q of config.questions) { condition(q.when); if (q.repeatFrom && !ids.has(q.repeatFrom)) errors.push('مصدر تكرار غير معروف'); }
    const dependency = new Map(config.questions.map(q=>[q.id,[]]));
    function refs(c,out) { if(!c)return; if(c.question)out.push(c.question); for(const key of ['all','any'])for(const x of c[key]||[])refs(x,out); if(c.not)refs(c.not,out); }
    for(const q of config.questions){refs(q.when,dependency.get(q.id));if(q.repeatFrom)dependency.get(q.id).push(q.repeatFrom);}
    const done=new Set(),visiting=new Set();
    function visit(id){if(done.has(id))return;if(visiting.has(id)){errors.push('دورة في شروط الظهور: '+id);return;}visiting.add(id);for(const x of dependency.get(id)||[])visit(x);visiting.delete(id);done.add(id);}
    for(const id of dependency.keys())visit(id);
    if (catalog && new Set(catalog.capabilities.map(c => c.id)).size !== catalog.capabilities.length) errors.push('معرّفات قدرات مكررة');
    return errors;
  }
  function validateEnvelope(input, config, catalog) {
    const errors = [], warnings = [];
    let raw;
    try { raw = typeof input === 'string' ? JSON.parse(input) : clone(input); } catch (_) { return { ok: false, errors: ['ملف الإجابات مش JSON سليم. احتفظ بالملف الأصلي وجرب نسخة تانية.'], warnings, value: null }; }
    function safe(x, depth = 0) {
      if (depth > 20) throw Error('تداخل البيانات أكبر من المسموح');
      if (typeof x === 'string' && x.length > 10000) throw Error('نص أطول من المسموح');
      if (Array.isArray(x) && x.length > 500) throw Error('قائمة أطول من المسموح');
      if (object(x) && Object.keys(x).length > 500) throw Error('عدد حقول أكبر من المسموح');
      if (x && typeof x === 'object') for (const [k, v] of Object.entries(x)) { if (['__proto__', 'prototype', 'constructor'].includes(k)) throw Error('مفتاح بيانات غير آمن'); safe(v, depth + 1); }
    }
    try { safe(raw); if (JSON.stringify(raw).length > 1500000) throw Error('حجم الملف أكبر من المسموح'); } catch (e) { errors.push(e.message); }
    if (!object(raw)) return { ok: false, errors: ['محتوى الملف لازم يكون كائن إجابات.'], warnings, value: null };
    if (!/^1\.\d+\.\d+$/.test(raw.schemaVersion || '')) errors.push('إصدار الملف غير مدعوم. الإصدار المدعوم 1.x؛ مفيش بيانات اتغيرت.');
    if (raw.questionnaireId !== config.id) errors.push('الملف يخص استبيانًا مختلفًا.');
    for (const key of ['questionnaireVersion', 'projectCommit', 'responseId', 'createdAt', 'updatedAt']) if (typeof raw[key] !== 'string' || !raw[key]) errors.push('حقل مطلوب ناقص: ' + key);
    for (const key of ['schemaVersion','questionnaireId','questionnaireVersion','projectCommit','responseId','createdAt','updatedAt','completedAt','reviewedAt','answers','skippedIds','cursor','extensions']) if (!Object.hasOwn(raw,key)) errors.push('حقل مطلوب ناقص: ' + key);
    if (typeof raw.questionnaireVersion === 'string' && !/^1\.\d+\.\d+$/.test(raw.questionnaireVersion)) errors.push('نسخة الأسئلة غير مدعومة؛ يلزم ترحيل معتمد قبل استخدام إصدار رئيسي مختلف.');
    for (const key of ['createdAt', 'updatedAt', 'completedAt', 'reviewedAt']) if (raw[key] != null && (typeof raw[key] !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(raw[key]) || !Number.isFinite(Date.parse(raw[key])))) errors.push('تاريخ غير صالح: ' + key);
    if (!object(raw.answers)) errors.push('قسم answers غير صحيح.');
    if (!Array.isArray(raw.skippedIds) || raw.skippedIds.some(x => typeof x !== 'string')) errors.push('قائمة الأسئلة المؤجلة غير صحيحة.');
    if (raw.cursor !== null && typeof raw.cursor !== 'string') errors.push('موضع الاستكمال غير صحيح.');
    if (!object(raw.extensions)) errors.push('قسم extensions غير صحيح.');
    if (errors.length) return { ok: false, errors, warnings, value: null };
    if (raw.schemaVersion !== VERSION || raw.questionnaireVersion !== config.version) warnings.push('نسخة الملف أو الأسئلة مختلفة؛ احتفظنا بالحقول الإضافية، ولازم تراجع الملاءمة قبل اعتماد التقرير.');
    if (catalog && raw.projectCommit !== catalog.projectCommit) warnings.push('الإجابات مرتبطة بنسخة مشروع مختلفة؛ القدرات المذكورة هنا تخص مرجع الكود المرفق، لا جهاز العميل بالضرورة.');
    const all = expandQuestions(config), map = new Map(all.map(q => [q.id, q]));
    const allowedPriority = new Set(config.priorityOptions.map(o => o.value));
    const caps = new Set(catalog?.capabilities.map(c => c.id) || []);
    for (const [id, v] of Object.entries(raw.answers)) {
      const q = map.get(id);
      if (!q) { warnings.push('إجابة من نسخة أخرى محفوظة بدون تحليل: ' + id); continue; }
      if (v === null) continue;
      const invalid = reason => errors.push(q.label + ': ' + reason);
      if (q.type === 'text') { if (typeof v !== 'string' || v.length > (q.maxLength || 4000)) invalid('النص أو طوله غير صحيح'); }
      else if (q.type === 'single') { if (!q.options.some(o => o.value === v)) invalid('اختيار غير معروف'); }
      else if (q.type === 'multi') {
        if (!Array.isArray(v) || v.some(x => !q.options.some(o => o.value === x)) || new Set(v).size !== v.length || v.length > (q.maxSelections || 100)) invalid('اختيارات متعددة غير صحيحة');
        else if ((q.exclusive || []).some(x => v.includes(x)) && v.length > 1) invalid('اختيار مستقل متعارض مع بقية الاختيارات');
      } else if (q.type === 'rating') { if (![1, 2, 3, 4, 5, 'unsure', 'na'].includes(v)) invalid('التقييم غير صحيح'); }
      else if (q.type === 'pain') {
        if (!object(v)) invalid('تفاصيل المشكلة غير صحيحة');
        else {
          if (v.frequency !== undefined && !['daily', 'weekly', 'monthly', 'rare', 'unsure'].includes(v.frequency)) invalid('تكرار غير معروف');
          if (v.impact !== undefined && ![1, 2, 3, 4, 5, 'unsure'].includes(v.impact)) invalid('تأثير غير صحيح');
          if (v.consequence !== undefined && !['delay', 'errors', 'loss', 'stops', 'minor', 'unsure'].includes(v.consequence)) invalid('نتيجة غير معروفة');
          if (v.example !== undefined && (typeof v.example !== 'string' || v.example.length > 1500)) invalid('المثال أطول من المسموح');
        }
      } else if (q.type === 'access') {
        if (!object(v) || Object.entries(v).some(([k,x]) => !['finance','pricing','returns','stock','export'].includes(k) || !['allow','approve','deny','unsure'].includes(x))) invalid('سياسة دور غير صحيحة');
      } else if (q.type === 'timeline') {
        if (!object(v) || Object.entries(v).some(([k, x]) => !['3', '6', '12', '24'].includes(k) || !config.timelineOptions.some(o => o.value === x))) invalid('خطة الفترات غير صحيحة');
      } else if (q.type === 'priorities') {
        if (!object(v) || Object.entries(v).some(([k, x]) => (caps.size && !caps.has(k)) || !allowedPriority.has(x))) invalid('أولويات غير صحيحة');
      }
    }
    return { ok: errors.length === 0, errors, warnings: [...new Set(warnings)], value: errors.length ? null : raw };
  }
  function optionLabel(q, v, config) {
    if (v === undefined || v === null || v === '') return 'لم يُحدد';
    if (q.type === 'pain') return 'التكرار: ' + ({ daily: 'يوميًا', weekly: 'أسبوعيًا', monthly: 'شهريًا', rare: 'نادرًا', unsure: 'غير متأكد' }[v.frequency] || 'لم يُحدد') + '؛ التأثير: ' + (typeof v.impact === 'number' ? v.impact + '/5' : v.impact === 'unsure' ? 'غير متأكد' : 'لم يُحدد') + '؛ النتيجة: ' + ({ delay: 'تأخير وإعادة عمل', errors: 'أخطاء حساب أو مخزون', loss: 'فقد مبيعات أو تكلفة إضافية', stops: 'توقف الشغل', minor: 'إزعاج محدود', unsure: 'غير متأكد' }[v.consequence] || 'لم تُحدد') + (v.example ? '؛ المثال: ' + v.example : '');
    if (q.type === 'access') return Object.entries(v).map(([k,x])=>({finance:'عرض الربح والأرصدة',pricing:'السعر والخصم',returns:'الإلغاء والمرتجع',stock:'الصنف والجرد',export:'التصدير والاستعادة'}[k]||k)+': '+({allow:'مسموح',approve:'بموافقة مسؤول',deny:'غير مسموح',unsure:'غير محسوم'}[x]||x)).join('؛ ');
    if (q.type === 'timeline') return Object.entries(v).map(([k, x]) => k + ' شهور: ' + (config.timelineOptions.find(o => o.value === x)?.label || x)).join('؛ ');
    if (q.type === 'priorities') return Object.entries(v).map(([k, x]) => k + ': ' + (config.priorityOptions.find(o => o.value === x)?.label || x)).join('؛ ');
    if (q.type === 'rating') return typeof v === 'number' ? v + '/5' : (v === 'na' ? 'لا ينطبق' : 'غير متأكد');
    const label = x => q.options?.find(o => o.value === x)?.label || String(x);
    return Array.isArray(v) ? v.map(label).join('، ') : label(v);
  }
  function contradictions(config, a) {
    const result = [];
    function flag(id, text, resolved, answerId) { result.push({ id, text, resolved, answerId, clarification: a[answerId] || null }); }
    if (a['mobile.offline'] === 'write' && a['mobile.realtime'] === 'instant' && ['view', 'operations', 'unsure'].includes(a['mobile.need'])) flag('offline-instant', 'طلب تسجيل عمليات دون إنترنت وتحديث أجهزة أخرى فورًا: لا يمكن ضمان الفورية أثناء انقطاع الاتصال.', ['queue', 'online'].includes(a['clarify.offline']), 'clarify.offline');
    if (a['finance.installments'] === 'never' && has(a, 'finance.methods', 'installment')) flag('finance-scope', 'اختيار التقسيط ضمن الدفع مع نفي استخدامه حاليًا.', ['future', 'rare', 'no'].includes(a['clarify.finance']), 'clarify.finance');
    if (a['mobile.need'] === 'none' && Object.values(a['future.goals'] || {}).includes('mobile')) flag('mobile-timing', 'نفي احتياج الهاتف حاليًا مع وجوده ضمن هدف مستقبلي.', ['future', 'no'].includes(a['clarify.mobile']), 'clarify.mobile');
    if (a['mobile.need'] === 'view' && includesAny(a, 'mobile.tasks', ['sale','collect','count','delivery','all'])) flag('mobile-scope', 'طلب عرض فقط مع طلب تنفيذ عمليات على الهاتف.', ['operations','view'].includes(a['clarify.mobileScope']), 'clarify.mobileScope');
    return result;
  }
  function androidAnalysis(a, conflicts) {
    const options = [
      { id: 'desktop', label: 'الاكتفاء بسطح المكتب', effort: 'S', complexity: 'منخفضة', reliability: 'أبسط تشغيل محلي؛ لا متابعة بعيدة تلقائية', security: 'تأمين الجهاز والنسخ والاستعادة', architecture: 'Flutter + SQLite محلي، دون خادم جديد' },
      { id: 'owner_panel', label: 'لوحة متابعة للمالك على الهاتف', effort: 'M–L', complexity: 'متوسطة', reliability: 'قراءة مع إظهار آخر تحديث؛ البيانات قد تتأخر دون اتصال', security: 'وصول قراءة فقط وصلاحيات للبيانات المنشورة', architecture: 'واجهة هاتف للعرض + قناة نشر آمنة أو API؛ ليست مشاركة ملف SQLite' },
      { id: 'companion', label: 'Android مكمل لمهام محددة', effort: 'L', complexity: 'مرتفعة عند السماح بكتابة دون اتصال', reliability: 'عمليات محددة، طابور إعادة إرسال وحل تعارض عند الحاجة', security: 'هوية جهاز ودور وتدقيق وتقليل البيانات على الهاتف', architecture: 'تكييف واجهات المنصة وعقود بيانات ومزامنة حسب نطاق المهام' },
      { id: 'full_android', label: 'Android كامل', effort: 'XL', complexity: 'مرتفعة', reliability: 'بديل تشغيل كامل يحتاج قبول جميع التدفقات والطباعة والاستعادة', security: 'كل صلاحيات التشغيل والأجهزة والنسخ وفقد الهاتف', architecture: 'إعادة تكييف التفاعل والتخزين والطباعة وجميع اختبارات دورة العمل؛ ليس تفعيل منصة فقط' },
      { id: 'central_sync', label: 'حل متعدد الأجهزة ببيانات مشتركة وخادم', effort: 'XL', complexity: 'الأعلى', reliability: 'تصميم لانقطاع الشبكة وتنافس المخزون والتحصيل، دون وعد فورية أثناء الانقطاع', security: 'هوية وصلاحيات وتدقيق ونسخ خادم وأجهزة وقناة آمنة', architecture: 'خادم/مزامنة بمعرفات عالمية وعدم تكرار موزع وإدارة تعارض؛ Android اختياري بحسب الدور' }
    ];
    let recommendation = null, reason = 'المعلومات غير كافية لاختيار منصة أو مزامنة.', confidence = 'منخفضة';
    const multiple = ['two', '3_5', 'gt5'].includes(a['volume.devices']) || ['two', '3_5', 'gt5'].includes(a['volume.branches']);
    const effectiveNeed = a['mobile.need'] === 'view' && a['clarify.mobileScope'] === 'operations' ? 'operations' : a['mobile.need'];
    const writes = a['clarify.mobileScope'] !== 'view' && includesAny(a, 'mobile.tasks', ['sale', 'collect', 'count', 'delivery', 'all']);
    if ((multiple && a['workflow.shared'] === 'shared') || (a['mobile.sync'] === 'yes' && writes && effectiveNeed === 'operations')) {
      recommendation = 'central_sync'; reason = 'هناك حاجة لعمليات أو أرصدة مشتركة من أجهزة متعددة؛ لا يعني ذلك إلزام العميل بتطبيق Android كامل.'; confidence = 'متوسطة';
    } else if (a['mobile.need'] === 'none') { recommendation = 'desktop'; reason = 'العميل لا يحتاج استخدام الهاتف حاليًا؛ لا نقترح Android لمجرد أن Flutter يدعمه نظريًا.'; confidence = 'مرتفعة'; }
    else if (a['mobile.need'] === 'view' && !writes) { recommendation = 'owner_panel'; reason = 'الاحتياج متابعة فقط، فلا مبرر لنقل كل عمليات البيع والمحاسبة إلى الهاتف.'; confidence = present(a['mobile.sync']) && present(a['mobile.offline']) ? 'مرتفعة' : 'متوسطة'; }
    else if (effectiveNeed === 'operations' && has(a, 'mobile.tasks', 'all')) { recommendation = 'full_android'; reason = 'العميل طلب إدارة العمل بالكامل من الهاتف؛ يلزم إثبات هذا النطاق وتجربة الطباعة والمنصة قبل الالتزام.'; confidence = 'متوسطة'; }
    else if (effectiveNeed === 'operations' && writes) { recommendation = 'companion'; reason = 'المطلوب مهام محددة على الهاتف، ويمكن أن يكفي تطبيق مكمل بدل نسخة كاملة.'; confidence = 'متوسطة'; }
    const unresolved = conflicts.filter(x => !x.resolved);
    if (unresolved.length || (recommendation === 'desktop' && multiple && !['independent','summary'].includes(a['workflow.shared']))) confidence = 'منخفضة';
    return { recommendation, label: options.find(o => o.id === recommendation)?.label || 'نحتاج توضيحًا قبل الاختيار', reason, confidence, options, unresolved: unresolved.map(c => c.text), assumptions: ['الجهد نسبي وليس سعرًا أو مدة تنفيذ.', 'الإشعارات والرسائل الآلية تحتاج مزودًا وموافقة عند اختيارها؛ المشاركة اليدوية لا تبرر وحدها بناء خادم.', 'استخدام خادم أو Android لا يُنفذ تلقائيًا بناءً على هذا التقرير.'] };
  }
  function analyze(input, config, catalog) {
    const checked = validateEnvelope(input, config, catalog);
    if (!checked.ok) throw Error(checked.errors.join('\n'));
    const e = checked.value, a = baseAnswers(config, e.answers), qs = expandQuestions(config), visible = new Set(visibleQuestions(config, e.answers).map(q => q.id));
    const conflicts = contradictions(config, a), seeds = needSeeds(config, e.answers), frequencies = { daily: 4, weekly: 3, monthly: 2, rare: 1 };
    const painMap = { search: ['checkout'], invoice: ['checkout', 'drafts'], stock: ['stock'], collections: ['installments', 'installment_rules'], accounting: ['reports', 'treasury'], returns: ['returns', 'services', 'serials'], printing: ['printing', 'hardware'], learning: ['checkout'], backup: ['backup'], manual: ['import', 'services'] };
    const painPoints = (a['pain.selected'] || []).filter(p => !['none', 'unsure'].includes(p)).map(p => {
      const q = qs.find(x => x.id === 'pain.detail.' + p), v = a[q.id] || {};
      const score = frequencies[v.frequency] && typeof v.impact === 'number' ? frequencies[v.frequency] * v.impact : null;
      return { id: p, label: q.label, frequency: v.frequency || null, impact: v.impact || null, consequence: v.consequence || null, example: v.example || null, score, confidence: score !== null && v.consequence && v.consequence !== 'unsure' ? 'مرتفعة' : 'منخفضة', evidence: [q.id, 'pain.selected'] };
    }).sort((x, y) => (y.score ?? -1) - (x.score ?? -1));
    function contextualAcceptance(c) {
      const fields={checkout:['volume.products','volume.lines','volume.peak'],backup:['priority.backup','priority.recovery'],installments:['finance.rule','finance.schedule','finance.openPlans'],installment_rules:['finance.schedule','finance.exceptions'],treasury:['finance.methods','finance.expenses','finance.shifts'],roles:['people.roles','people.permissions','people.approval'],printing:['printing.formats','printing.policy','printing.fields'],hardware:['printing.model','printing.shared'],services:['service.workflow','service.needs'],serials:['inventory.serialUse'],warehouses:['inventory.locations','inventory.states'],reports:['finance.profit','finance.reports'],android:['mobile.tasks','mobile.offline','mobile.camera'],owner_dashboard:['mobile.tasks','mobile.realtime'],sync:['workflow.shared','mobile.offline','mobile.realtime','clarify.offline']}[c.id]||[];
      const stated=fields.filter(id=>present(a[id])).map(id=>{const q=qs.find(q=>q.id===id);return q.label+': '+optionLabel(q,a[id],config);});
      return c.acceptance+(stated.length?' معيار تجربة مخصص من إجابات العميل: '+stated.join('؛ ')+'. لا تعتمد نتيجة القبول إن كانت سياسة التنفيذ غير محسومة.':'');
    }
    const priorities = e.answers['priority.features'] || {};
    const gaps = seeds.map(n => {
      const c = catalog.capabilities.find(c => c.id === n.id);
      const priority = priorities[n.id] || 'unconfirmed';
      const relatedPain = painPoints.filter(p => (painMap[p.id] || []).includes(n.id));
      const knownScores = relatedPain.filter(p => p.score !== null).map(p => p.score);
      const score = knownScores.length ? Math.max(...knownScores) : null;
      return { id: n.id, label: c.label, clientEvidence: n.evidence, clientPriority: priority, reasons: n.reasons, currentStatus: c.status, currentAbility: c.summary, fit: ({ available: 'موجود ويحتاج تجربة ملاءمة', needs_improvement: 'توافق جزئي وتحسين مطلوب', unavailable: 'فجوة وظيفية', needs_verification: 'لا يمكن الجزم قبل التحقق' })[c.status], decision: priority === 'no' ? 'لا يُنفذ بناءً على طلب العميل' : c.status === 'available' ? 'تجربة الموجود أولًا وتحديد الفرق فقط' : c.status === 'needs_verification' ? 'تحقق أو نموذج أولي قبل وعد دعم' : c.status === 'needs_improvement' ? 'تحسين أو تبسيط التدفق الحالي' : 'إضافة وظيفة بعد اعتماد النطاق', confidence: n.direct && !n.evidence.some(id => UNKNOWN.has(a[id])) ? 'مرتفعة في وجود الاحتياج، وليس في تفاصيل التنفيذ' : 'متوسطة وتحتاج تأكيد الاستنتاج', painScore: score, effort: c.effort, risk: c.risk, screen: c.screen, database: c.database || 'تُحدد بعد اعتماد التفاصيل؛ لا يُفترض تغيير قاعدة البيانات.', acceptance: contextualAcceptance(c), sources: c.sources };
    });
    const priorityOrder = { must: 0, soon: 1, nice: 2, unconfirmed: 3, unsure: 3, future: 4, no: 5 };
    gaps.sort((x, y) => priorityOrder[x.clientPriority] - priorityOrder[y.clientPriority] || (y.painScore ?? -1) - (x.painScore ?? -1) || ({ S: 1, M: 2, L: 3, XL: 4 }[x.effort] - { S: 1, M: 2, L: 3, XL: 4 }[y.effort]));
    const mobile = androidAnalysis(a, conflicts);
    const unknowns = [...checked.warnings, ...conflicts.filter(x => !x.resolved).map(x => x.text)];
    for (const q of visibleQuestions(config, e.answers)) {
      const value = e.answers[q.id];
      if (q.required && !answered(q, value, config, e.answers)) unknowns.push('إجابة غير مكتملة أو مؤجلة: ' + q.label);
      else if (['unsure','suggest'].includes(value) || (Array.isArray(value) && value.some(v=>['unsure','suggest'].includes(v))) || (object(value) && Object.values(value).some(v=>['unsure','suggest'].includes(v)))) unknowns.push('يحتاج توضيحًا أو اقتراحًا: ' + q.label);
    }
    for (const g of gaps.filter(g => ['unconfirmed', 'unsure'].includes(g.clientPriority))) unknowns.push('أولوية تحتاج اعتمادًا: ' + g.label);
    if (present(a['priority.finalNote'])) unknowns.push('راجع الملاحظة الحرة قبل حصر النطاق: ' + a['priority.finalNote']);
    if (mobile.confidence === 'منخفضة') unknowns.push('لا تعتمد منصة الهاتف أو المزامنة قبل استكمال النقاط المفتوحة.');
    const phases = PHASES.map((label, phase) => ({ phase, label, items: [] }));
    for (const issue of catalog.knownIssues) phases[issue.phase].items.push({ id: issue.id, label: issue.label, origin: 'عيب مؤكد من مراجعة الكود؛ ليس ادعاءً بأن العميل واجهه', effort: 'S–M', risk: issue.phase === 0 ? 'مرتفعة على صحة إدخال الدفع' : 'متوسطة على سهولة التشغيل', acceptance: issue.acceptance, source: issue.source, dependency: 'إعادة إنتاج مستقلة ثم إصلاح واختبارات عدم تراجع قبل اعتماد توسع جديد.' });
    for (const g of gaps.filter(g => g.clientPriority !== 'no')) {
      let phase = g.clientPriority === 'future' ? 4 : g.clientPriority === 'must' ? 1 : ['sync', 'android', 'owner_dashboard', 'integrations', 'notifications'].includes(g.id) ? 3 : 2;
      phases[phase].items.push({ id: g.id, label: g.label, origin: g.clientEvidence.join('، '), priority: g.clientPriority, effort: g.effort, risk: g.risk, decision: g.decision, screen: g.screen, database: g.database, acceptance: g.acceptance, dependency: ['sync', 'android'].includes(g.id) ? 'اعتماد المستخدمين ونطاق الكتابة والاتصال وحل التعارض والهوية أولًا. لا تنفيذ قبل الاعتماد.' : g.currentStatus === 'available' ? 'تجربة وظيفة قائمة ببيانات افتراضية قبل طلب تغيير.' : 'اعتماد حالة استخدام وبياناتها واختبار قبولها؛ ترحيل قابل للاستعادة إن لزم.', gated: ['unconfirmed', 'unsure'].includes(g.clientPriority) || (['sync','android','owner_dashboard'].includes(g.id) && mobile.confidence === 'منخفضة') });
    }
    const facts = qs.filter(q => Object.hasOwn(e.answers, q.id)).map(q => ({ questionId: q.id, question: q.label, value: clone(e.answers[q.id]), display: optionLabel(q, e.answers[q.id], config), active: visible.has(q.id) }));
    const workflowMap = [['استلام البضاعة',['workflow.entry']],['تحديد السعر',['workflow.pricing']],['البيع والتسليم',['workflow.sale']],['التحصيل والمراجعة',['finance.methods','finance.installments','finance.close']],['ما بعد البيع',['inventory.returnPolicy','service.workflow']],['العمل اليدوي ونقاط التعطيل',['workflow.manual','pain.selected']],['الاستثناءات',['workflow.exception','finance.exceptions']]].map(([step,ids])=>({step,evidence: facts.filter(f=>f.active && ids.includes(f.questionId)).map(f=>({questionId:f.questionId,statement:f.display})),status:ids.some(id=>present(a[id]))?'وصف العميل؛ لا يُفترض ترتيب خطوات لم يذكره':'لم يُحدد؛ يلزم التوضيح'}));
    const unknownAnswers = Object.fromEntries(Object.entries(e.answers).filter(([id]) => !qs.some(q => q.id === id)));
    return { schemaVersion: VERSION, sourceResponseId: e.responseId, sourceQuestionnaireVersion: e.questionnaireVersion, projectCommit: catalog.projectCommit, limitations: ['تقرير قواعد محلية قابل للمراجعة وليس اعتماد تنفيذ أو التزام تكلفة/وقت.', 'وجود وظيفة في الكود لا يثبت ملاءمتها أو توافق جهاز العميل.'], businessProfile: facts.filter(f => f.active && /^(business|volume)\./.test(f.questionId)), workflowMap, workflow: facts.filter(f => f.active && /^(workflow|service)\./.test(f.questionId)), rolePolicies: facts.filter(f=>f.active && f.questionId.startsWith('people.access.')), clientSaid: facts, painPoints, painStatement: a['pain.selected']?.includes('none') ? 'العميل صرّح بعدم وجود مشكلات حالية ضمن الاختيارات.' : a['pain.selected']?.includes('unsure') ? 'العميل غير متأكد من المشكلات؛ لا نستنتج غيابها.' : !present(a['pain.selected']) ? 'لم يحدد العميل المشكلات؛ لا نستنتج غيابها.' : null, gaps, android: mobile, contradictions: conflicts, unresolved: [...new Set(unknowns)], plan: phases, nonFunctional: ['عدم تكرار بيع أو تحصيل عند إعادة الإرسال، ومطابقة القيود والأرصدة بعد الاستعادة.', 'تجربة حمل وفق حجم الأصناف والفواتير ومضاعف الموسم المعلن؛ زمن استجابة مقبول يحدده العميل في التجربة.', 'واجهة عربية واضحة واختبار هاتف/كمبيوتر ولوحة مفاتيح حسب الاستخدام الفعلي.', 'صلاحيات تنفيذ على مصدر البيانات عند تعدد المستخدمين، وتسجيل من نفذ واعتمد العملية.', 'نسخ احتياطي واسترجاع مجرّب وخطة فقد جهاز، دون ادعاء تشفير غير منفذ.', 'لا مشاركة ملف SQLite الحي بين الأجهزة كحل مزامنة.'], priorityMethod: 'تصنيف العميل أولًا، ثم أثر المشكلة الموثق (التكرار 1–4 × التأثير 1–5)، ثم الجهد النسبي للمفاضلة. الإلحاح وحجم المستخدمين والجهد والمخاطر ظاهرة للمراجعة؛ القيم الناقصة لا تتحول تلقائيًا لصفر أو احتياج مؤكد.', beneficiaries: optionLabel(qs.find(q=>q.id==='volume.staff'),a['volume.staff'],config), urgency: optionLabel(qs.find(q=>q.id==='priority.deadline'),a['priority.deadline'],config), unknownAnswers, inputPreserved: clone(e), engineeringBaseline: 'عيوب النسخة المعروفة في خطة الثبات منفصلة عن المشكلات التي صرّح بها العميل.' };
  }
  function markdown(report) {
    const md = htmlSafeMarkdown, lines = ['# تحليل احتياجات ALIkhlas POS', '', '> تقرير أولي للمراجعة والاعتماد. لا تنفيذ تلقائي ولا أسعار أو مواعيد مختلقة.', '', 'مرجع الكود: `' + report.projectCommit + '`؛ ملف الإجابة: `' + report.sourceResponseId + '`.', '', '## أ. ما قاله العميل — الملف التشغيلي', ''];
    const facts = fs => { if (!fs.length) lines.push('لم تتوفر إجابات كافية.'); else for (const f of fs) lines.push('- **' + md(f.question) + '**: ' + md(f.display) + ' (`' + f.questionId + '`).'); };
    facts(report.businessProfile); lines.push('', '## ب. ما قاله العميل — رحلة العمل', ''); facts(report.workflow);
    lines.push('', '| مرحلة العمل | ما وصفه العميل | دليل الإجابة |', '|---|---|---|');
    for (const step of report.workflowMap) lines.push('| '+md(step.step)+' | '+md(step.evidence.map(f=>f.statement).join('؛ ')||step.status)+' | '+md(step.evidence.map(f=>f.questionId).join('، '))+' |');
    if (report.rolePolicies.length) { lines.push('', 'سياسات الأدوار كما أجاب العميل:'); facts(report.rolePolicies); }
    lines.push('', '## ج. تحليل المشكلات الفعلية', '');
    if (report.painStatement) lines.push(md(report.painStatement));
    for (const p of report.painPoints) lines.push('- **' + md(p.label) + '**؛ التكرار: ' + md(frequencyLabel(p.frequency)) + '؛ التأثير: ' + md(p.impact || 'غير محدد') + '؛ نتيجة عدم الحل: ' + md(consequenceLabel(p.consequence)) + '؛ درجة الترتيب: ' + (p.score ?? 'لا تُحسب قبل اكتمال التكرار والتأثير') + '؛ الثقة: ' + p.confidence + '.', '  - مثال العميل: ' + md(p.example || 'لم يقدم مثالًا، ولا نخترع مثالًا على لسانه.'));
    lines.push('', '## د. ما استنتجه التحليل — خريطة الفجوات', '', '| الاحتياج ودليله | القدرة الحالية | التوافق | القرار المقترح | أولوية العميل | الثقة |', '|---|---|---|---|---|---|');
    for (const g of report.gaps) lines.push('| ' + md(g.label + ' [' + g.clientEvidence.join(', ') + ']') + ' | ' + md(g.currentAbility) + ' | ' + g.fit + ' | ' + md(g.decision) + ' | ' + md(priorityLabel(g.clientPriority)) + ' | ' + md(g.confidence) + ' |');
    if (!report.gaps.length) lines.push('| لا معلومات كافية | — | غير محسوم | استكمال الأسئلة، لا افتراض خصائص | غير محددة | منخفضة |');
    lines.push('', '## هـ. قرارات التطوير والأولوية', '', md(report.priorityMethod), '', 'الجهد النسبي: S صغير، M متوسط، L كبير، XL كبير جدًا؛ للمقارنة فقط، وليس أيام عمل أو تكلفة.', '', '- حجم المستفيدين كما أعلنه العميل: ' + md(report.beneficiaries), '- الإلحاح كما أعلنه العميل: ' + md(report.urgency));
    for (const g of report.gaps) lines.push('- ' + md(g.label) + ': ' + md(g.decision) + '؛ جهد ' + g.effort + '؛ مخاطر ' + g.risk + '.');
    lines.push('', '## و. الهاتف والمزامنة — اقتراح النظام', '', '**الترشيح الأولي: ' + report.android.label + '**؛ الثقة: ' + report.android.confidence + '.', '', md(report.android.reason), '', '| البديل | الجهد النسبي | التعقيد | الاعتمادية والقيود | الأمان | الأثر المعماري |', '|---|---|---|---|---|---|');
    for (const o of report.android.options) lines.push('| ' + [o.label, o.effort, o.complexity, o.reliability, o.security, o.architecture].map(md).join(' | ') + ' |');
    lines.push('', ...report.android.assumptions.map(x => '- ' + md(x)), '', '## ز. غير محسوم — مطلوب تأكيده', '');
    lines.push(...(report.unresolved.length ? report.unresolved.map(x => '- ' + md(x)) : ['لا تعارض ظاهر في الحقول المجابة؛ لا يعني ذلك اعتماد كل تفاصيل التنفيذ.']));
    lines.push('', '## ح. الخطة المقترحة للمراجعة فقط', '', md(report.engineeringBaseline));
    for (const phase of report.plan) {
      lines.push('', '### ' + phase.label, '');
      if (!phase.items.length) lines.push('لا بنود مثبتة في هذه المرحلة من الإجابات الحالية.');
      for (const item of phase.items) lines.push('- **' + md(item.label) + '** (`' + item.id + '`)' + (item.gated ? ' — مؤجل لحين الاعتماد/استكمال المعلومات' : ''), '  - المصدر: ' + md(item.origin), '  - التغيير: ' + md(item.decision || 'إصلاح عيب مثبت ثم اختبار عدم تراجع.'), '  - الشاشة: ' + md(item.screen || 'وفق مصدر العيب'), '  - قاعدة البيانات: ' + md(item.database || 'لا تغيير مفترض قبل تحديد سبب العيب.'), '  - القبول: ' + md(item.acceptance), '  - الجهد: ' + item.effort + '؛ المخاطر: ' + item.risk, '  - التبعيات: ' + md(item.dependency));
    }
    lines.push('', '## ط. متطلبات غير وظيفية وبوابة الاعتماد', '', ...report.nonFunctional.map(x => '- ' + md(x)), '- اعتماد صاحب النشاط لحالات الاستخدام ومعيار النجاح، وتجربة بيانات افتراضية، ثم موافقة على النطاق قبل تنفيذ أي ميزة.', '', '## ملحق: كل الإجابات دون حذف', '', 'الإجابات المخفية محفوظة للتراجع، ولا تدخل في الاستنتاج ما لم يعد مسارها نشطًا.');
    for (const f of report.clientSaid) lines.push('- [' + (f.active ? 'نشطة' : 'مخفية — لا تُستخدم للتحليل') + '] `' + f.questionId + '` ' + md(f.question) + ': ' + md(f.display));
    if (Object.keys(report.unknownAnswers).length) lines.push('', 'حقول من نسخة أخرى محفوظة ولا تُحلل:', '', '```json', JSON.stringify(report.unknownAnswers, null, 2), '```');
    lines.push('', 'الأصل الكامل للإجابات (للحفاظ على كل القيم والحقول الإضافية):', '', '```json', JSON.stringify(report.inputPreserved.answers, null, 2), '```');
    return lines.join('\n') + '\n';
  }
  function readableHtml(report) {
    const h = x => String(x ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
    const listFacts = rows => '<dl>' + rows.map(f=>'<dt>'+h(f.question)+'</dt><dd>'+h(f.display)+'</dd>').join('')+'</dl>';
    const section = (title, body) => '<section><h2>'+h(title)+'</h2>'+body+'</section>';
    let body = '<header><p>إخلاص POS · تحليل احتياجات أولي</p><h1>ملخص نشاطك والخطوة المناسبة</h1><p>بيانات ومقترحات للمراجعة، مش موافقة على التنفيذ أو وعد تكلفة أو وقت.</p></header>';
    body += section('ما قاله العميل — النشاط وحجم العمل',listFacts(report.businessProfile));
    body += section('ما قاله العميل — طريقة الشغل',listFacts(report.workflow)+'<ol>'+report.workflowMap.map(s=>'<li><strong>'+h(s.step)+'</strong>: '+h(s.evidence.map(f=>f.statement).join('؛ ')||s.status)+'</li>').join('')+'</ol>');
    if(report.rolePolicies.length)body += section('ما قاله العميل — سياسة كل دور',listFacts(report.rolePolicies));
    body += section('المشكلات المعلنة',report.painStatement?'<p>'+h(report.painStatement)+'</p>':report.painPoints.map(p=>'<article><h3>'+h(p.label)+'</h3><p>التكرار: '+h(frequencyLabel(p.frequency))+' · التأثير: '+h(p.impact||'غير محدد')+' · النتيجة: '+h(consequenceLabel(p.consequence))+'</p><p>'+h(p.example||'لم يقدم العميل مثالًا.')+'</p></article>').join(''));
    body += section('ما استنتجه التحليل — مدى التوافق', '<table><tr><th>الاحتياج</th><th>المتاح حاليًا</th><th>القرار المقترح</th><th>الثقة</th></tr>'+report.gaps.map(g=>'<tr><td>'+h(g.label)+'</td><td>'+h(g.currentAbility)+'</td><td>'+h(g.decision)+'</td><td>'+h(g.confidence)+'</td></tr>').join('')+'</table>');
    body += section('اقتراح النظام — الهاتف وربط الأجهزة','<h3>'+h(report.android.label)+'</h3><p>'+h(report.android.reason)+'</p><p>درجة الثقة: '+h(report.android.confidence)+'</p><table><tr><th>البديل</th><th>التعقيد والجهد النسبي</th><th>القيود والأمان</th></tr>'+report.android.options.map(o=>'<tr><td>'+h(o.label)+'</td><td>'+h(o.complexity+' / '+o.effort)+'</td><td>'+h(o.reliability+'؛ '+o.security)+'</td></tr>').join('')+'</table>');
    body += section('النقاط غير المحسومة','<ul>'+report.unresolved.map(x=>'<li>'+h(x)+'</li>').join('')+'</ul>');
    body += section('خطة مقترحة تحتاج اعتمادًا',report.plan.map(p=>'<h3>'+h(p.label)+'</h3><ul>'+p.items.map(i=>'<li><strong>'+h(i.label)+'</strong><p>'+h(i.decision||i.origin)+'</p><p>القبول: '+h(i.acceptance)+'</p><p>الجهد: '+h(i.effort)+' · المخاطر: '+h(i.risk)+'</p><details><summary>تفاصيل لفريق التطوير</summary><p>'+h(i.database||i.source||'لا تغيير مفترض في البيانات.')+'</p><p>'+h(i.dependency)+'</p></details></li>').join('')+'</ul>').join(''));
    body += section('كل الإجابات والتفاصيل للتدقيق','<details><summary>التقرير الكامل بما فيه الإجابات المخفية والأصل المحفوظ</summary><pre>'+h(markdown(report))+'</pre></details>');
    return '<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'"><title>تحليل احتياجات إخلاص POS</title><style>body{font:17px/1.8 Tahoma,Arial,sans-serif;color:#173f3d;background:#f0f6f4;max-width:1050px;padding:24px;margin:auto}section,header{padding:24px;margin:18px 0;background:white;border:1px solid #d3e1dc;border-radius:16px}h1,h2{line-height:1.6}h2{font-size:1.3em}dt{font-size:.9em;color:#55736f}dd{margin:4px 0 16px;white-space:pre-wrap;overflow-wrap:anywhere}table{width:100%;border-collapse:collapse;font-size:.85em}td,th{border:1px solid #c7d8d2;padding:10px;text-align:start;vertical-align:top;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;font-family:inherit;font-size:.85em}summary{cursor:pointer;color:#087d75}@media(max-width:500px){body{padding:10px}section,header{padding:14px}table{font-size:.72em}td,th{padding:5px}}@media print{body{background:white}section{break-inside:avoid}details>pre{display:block}}</style>'+body+'</html>';
  }
  function planMarkdown(report) { const text = markdown(report); return '# خطة تطوير مقترحة — تحتاج اعتمادًا\n\n' + text.slice(text.indexOf('## ح. الخطة المقترحة للمراجعة فقط')); }
  return { VERSION, PHASES, clone, present, baseMatch, expandQuestions, visibleQuestions, pages, progress, newEnvelope, validateConfig, validateEnvelope, optionLabel, needSeeds, contradictions, androidAnalysis, analyze, markdown, readableHtml, planMarkdown, answered };
});
