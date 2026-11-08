(function () {
  'use strict';
  const E = window.Discovery;
  const Q = JSON.parse(document.getElementById('questionnaire-data').textContent);
  const C = JSON.parse(document.getElementById('capability-data').textContent);
  const KEY = 'alikhlas.client-discovery.v1';
  const root = document.getElementById('app');
  let state = E.newEnvelope(Q, C.projectCommit), mode = 'welcome', current = null;
  let storageOkay = true, storageMessage = '', recoveryRaw = null, importWarnings = [], errors = [];
  let noticeTimer;
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text !== undefined) n.textContent = text; return n; };
  const button = (text, action, cls = '') => { const b = el('button', cls, text); b.type = 'button'; b.addEventListener('click', action); return b; };
  function notify(message) {
    const n = document.getElementById('notice'); n.className = 'notice'; n.textContent = message;
    clearTimeout(noticeTimer); noticeTimer = setTimeout(() => { n.className = ''; n.textContent = ''; }, 6500);
  }
  function readCache() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const checked = E.validateEnvelope(raw, Q, C);
        if (checked.ok) { state = checked.value; current = state.cursor; importWarnings = checked.warnings; }
        else { recoveryRaw = raw; storageOkay = false; storageMessage = 'الإجابات المحفوظة مش مقروءة. نزل نسخة للفحص قبل بدء جديد، أو استورد ملف سليم.'; }
      } else { localStorage.setItem(KEY + '.probe', '1'); localStorage.removeItem(KEY + '.probe'); }
    } catch (_) { storageOkay = false; storageMessage = 'المتصفح مش سامح بالحفظ على الجهاز. تقدر تكمل، لكن نزل ملف الإجابات علشان تستكمل بعدين.'; }
  }
  function save() {
    state.updatedAt = new Date().toISOString(); state.cursor = mode === 'summary' ? '__summary__' : current;
    const raw = JSON.stringify(state);
    try {
      localStorage.setItem(KEY, raw);
      if (localStorage.getItem(KEY) !== raw) throw Error('Storage verification failed');
      storageOkay = true; storageMessage = '';
    } catch (_) { storageOkay = false; storageMessage = 'تعذر الحفظ على الجهاز. آخر إجاباتك لسه في الصفحة: نزل ملف الإجابات قبل ما تقفلها.'; }
    refreshStatus();
  }
  function refreshStatus() {
    const status = document.getElementById('save-line');
    if (status) status.textContent = storageOkay ? 'تم الحفظ على الجهاز ده · تقدر تستكمل من نفس المتصفح أو تستورد ملف الإجابات' : storageMessage;
    const warning = document.getElementById('storage-warning');
    if (warning) { warning.hidden = storageOkay; warning.textContent = storageMessage; }
    const p = E.progress(Q, state), percent = document.getElementById('progress-value'), fill = document.getElementById('progress-fill');
    if (percent) percent.textContent = p.percent + '٪ · ' + p.done + ' من ' + p.total + ' إجابة أو سؤال مؤجل';
    if (fill) { fill.style.width = p.percent + '%'; fill.parentElement.setAttribute('aria-valuenow', p.percent); }
  }
  function update(id, value, rerender = true) {
    state.answers[id] = value; state.skippedIds = state.skippedIds.filter(x => x !== id);
    state.reviewedAt = null; state.completedAt = null; errors = [];
    if (rerender && mode === 'editor') current = E.pages(Q,state.answers).find(p=>p.questions.some(q=>q.id===id))?.id || current;
    save(); if (rerender) render(false);
  }
  function download(name, text, mime) {
    const blob = new Blob([text], { type: mime || 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob), a = document.createElement('a');
    a.href = url; a.download = name; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 30000);
    notify('طلبنا تنزيل الملف. اتأكد إنه ظهر في التنزيلات قبل ما تقفل الصفحة.');
  }
  function exportAnswers() {
    save();
    const checked = E.validateEnvelope(state, Q, C);
    if (!checked.ok) { errors = checked.errors; render(false); notify('فيه مشكلة في البيانات. راجع الرسالة قبل التصدير.'); return; }
    download('alikhlas-answers-' + state.responseId + '.json', JSON.stringify(state, null, 2), 'application/json;charset=utf-8');
  }
  function sharingBox() {
    const box = el('section', 'download-box share-box');
    box.append(el('h2', '', 'ابعت النتيجة على واتساب'), el('p', '', 'الروابط دي بتفتح واتساب مباشرة وتمرر له الإجابات كنص. اختار المحادثة واضغط إرسال داخل واتساب. مش محتاج صلاحية مشاركة ملفات من Chrome.'));
    const links = el('div', 'whatsapp-links');
    try {
      const parts=E.whatsappParts(state,Q,C);
      if(parts.length>1)links.append(el('p','help','علشان الروابط ما تطولش، النتيجة مقسمة إلى '+parts.length+' رسائل. افتح وابعت كل جزء بالترتيب. أو نزّل النتيجة تحت وابعتها كمستند واحد.'));
      for(const part of parts){
        const link=el('a','whatsapp-link',parts.length===1?'فتح واتساب بالنتيجة':'إرسال الجزء '+part.part+' من '+part.total+' على واتساب');
        link.href=part.href;link.target='_blank';link.rel='noopener noreferrer';
        link.addEventListener('click',()=>{save();notify('تم طلب فتح الجزء '+part.part+' في واتساب. اختار المحادثة واضغط إرسال هناك؛ الصفحة لا تؤكد الاستلام.');});
        links.append(link);
      }
    }catch(error){links.append(el('p','help',error.message));}
    box.append(links);
    const fallback = el('div', 'share-fallback'); fallback.hidden = true;
    fallback.append(el('p', '', 'لو مشاركة الملف مش متاحة: نزّل النتيجة، وافتح محادثتنا في واتساب، واضغط المشبك ← مستند ← اختار الملف من التنزيلات.'), button('تنزيل النتيجة لإرفاقها في واتساب', exportAnswers));
    const text = el('textarea', 'share-copy'); text.readOnly = true; text.hidden = true; text.setAttribute('aria-label', 'نص الإجابات كاملًا للنسخ إلى واتساب');
    const copy = button('نسخ الإجابات لإرسالها كنص', async () => {
      save();
      const message = E.shareMessage(state, Q, C);
      if (message.length > 60000) { notify('الإجابات طويلة. نزّل الملف وابعته كمستند علشان توصل كاملة.'); return; }
      try {
        if (!navigator.clipboard?.writeText) throw Error('Clipboard unavailable');
        await navigator.clipboard.writeText(message);
        notify('اتنسخت الإجابات كاملة. افتح محادثتنا في واتساب والصقها وراجعها قبل الإرسال.');
      } catch (_) {
        text.value = message; text.hidden = false; text.focus(); text.select();
        try { if(document.execCommand('copy')) { text.hidden=true; notify('اتنسخت الإجابات كاملة. افتح محادثتنا في واتساب والصقها.'); return; } } catch (_) {}
        notify('اضغط مطولًا على النص، واختار تحديد الكل ثم نسخ، والصقه في واتساب.');
      }
    }, 'quiet');
    fallback.append(copy, text);
    const share = button('مشاركة ملف النتيجة — لو المتصفح بيدعمها', async () => {
      save();
      const checked = E.validateEnvelope(state, Q, C);
      if (!checked.ok) { errors = checked.errors; render(false); return; }
      share.disabled = true;
      try {
        const file = new File([JSON.stringify(checked.value, null, 2)], 'alikhlas-answers-' + state.responseId + '.json', { type: 'application/json' });
        if (!navigator.share || !navigator.canShare?.({ files: [file] })) { fallback.hidden = false; notify('مشاركة الملفات مش متاحة هنا. استخدم روابط واتساب فوق أو نزّل النتيجة كمستند.'); return; }
        await navigator.share({ files: [file], title: 'احتياجات المحل من إخلاص POS', text: 'دي إجاباتي عن شغلي الحالي واللي متوقعه من التطبيق، وخصوصًا تسهيل الفواتير.' });
        notify('راجع محادثة واتساب علشان تتأكد من إرسال الملف للشخص المقصود.');
      } catch (error) {
        if (error.name === 'AbortError') notify('تم إلغاء المشاركة. إجاباتك لسه موجودة، وتقدر تبعتها وقت ما تحب.');
        else { fallback.hidden = false; notify('المتصفح ما قدرش يشارك الملف. استخدم التنزيل أو نسخ الإجابات.'); }
      } finally { share.disabled = false; }
    }, 'quiet');
    box.append(button('تنزيل النتيجة كملف واحد',exportAnswers), share, button('نسخ الإجابات أو مساعدة الإرسال', () => { fallback.hidden = !fallback.hidden; }, 'quiet'), fallback);
    return box;
  }
  async function importFile(file) {
    if (!file) return;
    if (file.size > 1500000) { notify('الملف كبير جدًا. الحد حوالي 1.5 ميجابايت لملف الإجابات.'); return; }
    let checked;
    try { checked = E.validateEnvelope(await file.text(), Q, C); } catch (_) { checked = { ok: false, errors: ['تعذر قراءة الملف. جرب نسخة تانية.'] }; }
    if (!checked.ok) { errors = checked.errors; render(false); notify('ما استوردناش الملف، وإجاباتك الحالية زي ما هي.'); return; }
    if (Object.keys(state.answers).length && !window.confirm('استيراد الملف هيستبدل إجابات الصفحة الحالية. لو محتاجها، اضغط إلغاء ونزل نسخة منها الأول. نكمل؟')) return;
    state = checked.value; current = state.cursor; importWarnings = checked.warnings; recoveryRaw = null; errors = []; mode = 'welcome'; save(); render(); notify('تم استيراد الإجابات، بما فيها الإجابات المؤجلة والمخفية.');
  }
  function importButton() {
    const wrap = el('span'), input = document.createElement('input'); input.type = 'file'; input.accept = '.json,.txt,application/json,text/plain'; input.hidden = true; input.setAttribute('aria-label', 'اختيار ملف إجابات JSON');
    input.addEventListener('change', async () => { await importFile(input.files[0]); input.value = ''; });
    wrap.append(button('استيراد ملف إجابات', () => input.click(), 'quiet'), input); return wrap;
  }
  function warnings(container) {
    const s = el('div', 'warning'); s.id = 'storage-warning'; s.hidden = storageOkay; s.textContent = storageMessage; container.append(s);
    if (errors.length) { const e = el('div', 'error-box'); e.setAttribute('role', 'alert'); for (const m of errors) e.append(el('p', '', m)); container.append(e); }
    for (const m of importWarnings) container.append(el('div', 'warning', m));
  }
  function start(newSession) {
    if (recoveryRaw) newSession = true;
    if (newSession && (Object.keys(state.answers).length || recoveryRaw)) {
      if (!window.confirm('بدء جديد هيمسح النسخة المحفوظة في المتصفح. نزل نسخة من إجاباتك لو محتاجها. نبدأ من جديد؟')) return;
      state = E.newEnvelope(Q, C.projectCommit); recoveryRaw = null; current = null; importWarnings = []; errors = [];
    }
    mode = !newSession && state.cursor === '__summary__' ? 'summary' : 'editor';
    if (!current || current === '__summary__') current = E.pages(Q, state.answers)[0].id;
    save(); render();
  }
  function welcome() {
    const area = el('section', 'welcome'), intro = el('div');
    intro.append(el('span', 'eyebrow', 'قبل ما تستلم التطبيق'), el('h1', '', 'خلّينا نريحك من كتابة الفواتير'), el('p', 'lead', 'عرفنا إن كتابة الفواتير بإيدك بتتعبك. الأسئلة دي علشان نفهم شغلك الحالي، والفاتورة عندك بتتعمل إزاي، وإيه اللي متوقع التطبيق يسهّله عليك. مش مطلوب تكون جرّبت البرنامج.'));
    const facts = el('div', 'welcome-facts');
    for (const [a, b] of [['الفواتير أولًا', 'نفهم اللي بياخد وقتك'], ['تفاصيل باختيارك', 'اللي يخص شغلك بس'], ['إرسال على واتساب', 'بعد ما تراجع إجاباتك']]) { const f = el('div'); f.append(el('strong', '', a), el('small', '', b)); facts.append(f); } intro.append(facts);
    const actions = el('div', 'actions'); const hasWork = Object.keys(state.answers).length > 0;
    actions.append(button(hasWork ? 'استكمال إجاباتك' : 'نبدأ الاستبيان', () => start(false), 'primary'));
    if (hasWork) actions.append(button('بدء استبيان جديد', () => start(true), 'quiet'));
    actions.append(importButton()); intro.append(actions);
    if (hasWork) { const p = E.progress(Q, state); intro.append(el('p', 'privacy', 'فيه إجابات محفوظة على الجهاز ده · أنجزت ' + p.percent + '٪. تقدر تعدل أي إجابة قبل تنزيل الملف.')); }
    intro.append(el('p', 'privacy', 'الإجابات بتتحفظ محليًا في المتصفح لو بيسمح، ومش متشفرة. بلاش أسماء عملاء حقيقية أو كلمات مرور أو بيانات حسابات. لو الجهاز مش جهازك، نزل نسختك وامسح المحفوظ بعد ما تخلص.'));
    const aside = el('div', 'welcome-card'); aside.append(el('h2', '', 'إيه اللي هيحصل بعد ما تجاوب؟'));
    const ol = el('ol'); for (const s of ['نسمع منك عن شغلك الحالي والفواتير اللي بتكتبها.', 'تراجع ملخص إجاباتك وتعدّل اللي تحبه.', 'تشارك النتيجة على واتساب، ونحدد معاك أول نسخة محتاجها.']) ol.append(el('li', '', s)); aside.append(ol, el('div', 'info', 'جاوب من واقع شغلك الحالي وتوقعاتك. مش متأكد؟ تقدر تأجل أي سؤال.'));
    if (recoveryRaw) aside.append(button('تنزيل المحفوظ غير المقروء للفحص', () => download('alikhlas-local-recovery.json', recoveryRaw, 'application/json'), 'quiet'));
    if (hasWork) aside.append(button('تنزيل نسخة من الإجابات الحالية', exportAnswers, 'quiet'));
    warnings(aside); area.append(intro, aside); root.append(area);
  }
  function selectControl(id, label, options, value, change) {
    const select = el('select'); select.id = id; select.setAttribute('aria-label', label);
    const empty = el('option', '', 'اختار المناسب'); empty.value = ''; select.append(empty);
    for (const option of options) { const o = el('option', '', option.label); o.value = String(option.value); select.append(o); }
    select.value = value === undefined ? '' : String(value);
    select.addEventListener('change', () => change(select.value)); return select;
  }
  function questionControl(q) {
    const box = el('fieldset', 'question'); box.dataset.question = q.id;
    const legend = el('legend', '', q.label); if (!q.required) legend.append(el('span', 'optional', 'اختياري')); box.append(legend);
    if (q.help) box.append(el('p', 'help', q.help));
    const value = state.answers[q.id];
    if (q.type === 'single' || q.type === 'multi' || q.type === 'rating') {
      let options = q.options;
      if (q.type === 'rating') { box.append(el('p', 'help', '1 = محتاج تحسين كبير، 5 = مناسب جدًا لطريقة شغلك.')); options = [1, 2, 3, 4, 5, 'unsure', 'na'].map(v => ({ value: v, label: typeof v === 'number' ? String(v) : v === 'unsure' ? 'مش متأكد' : 'لا ينطبق' })); }
      const choices = el('div', q.type === 'rating' ? 'rating' : 'choices');
      for (const o of options.filter(o => !o.legacyOnly)) {
        const label = el('label', 'choice'), input = document.createElement('input'); input.type = q.type === 'multi' ? 'checkbox' : 'radio'; input.name = q.id; input.id = q.id + '__' + o.value; input.value = String(o.value);
        input.checked = q.type === 'multi' ? (value || []).includes(o.value) : value === o.value;
        input.addEventListener('change', () => {
          if (q.type !== 'multi') { update(q.id, o.value); return; }
          let next = Array.isArray(value) ? [...value] : [];
          if (input.checked) {
            if ((q.exclusive || []).includes(o.value)) next = [o.value];
            else { next = next.filter(v => !(q.exclusive || []).includes(v)); if (!next.includes(o.value)) next.push(o.value); }
          } else next = next.filter(v => v !== o.value);
          if (next.length > (q.maxSelections || 100)) { input.checked = false; notify('اختار لحد ' + q.maxSelections + ' اختيارات علشان نركز على الأهم.'); return; }
          update(q.id, next);
        });
        label.append(input, el('span', '', o.label)); choices.append(label);
      }
      box.append(choices);
      if (q.type === 'multi' && q.maxSelections) box.append(el('p', 'help', 'حد أقصى ' + q.maxSelections + ' اختيارات.'));
    } else if (q.type === 'text') {
      const input = q.maxLength > 500 ? el('textarea') : document.createElement('input'); if (input.tagName === 'INPUT') input.type = 'text'; input.id = q.id; input.value = value || ''; input.maxLength = q.maxLength || 4000; input.setAttribute('aria-label', q.label);
      const hint = el('div', 'field-hint', input.value.length + ' / ' + input.maxLength); input.addEventListener('input', () => { update(q.id, input.value, false); hint.textContent = input.value.length + ' / ' + input.maxLength; }); box.append(input, hint);
    } else if (q.type === 'pain') {
      const data = value || {};
      const fields = [
        ['frequency', 'المشكلة دي بتحصل كل قد إيه؟', [{ value: 'daily', label: 'يوميًا أو أغلب الأيام' }, { value: 'weekly', label: 'كل أسبوع تقريبًا' }, { value: 'monthly', label: 'كل شهر تقريبًا' }, { value: 'rare', label: 'نادرًا' }, { value: 'unsure', label: 'مش متأكد' }]],
        ['impact', 'بتأثر على الشغل قد إيه؟', [1, 2, 3, 4, 5].map(v => ({ value: v, label: v + ' — ' + ['بسيط', 'محدود', 'متوسط', 'كبير', 'يعطّل الشغل'][v - 1] })).concat({ value: 'unsure', label: 'مش متأكد' })],
        ['consequence', 'لو ما اتحلتش، إيه النتيجة الأقرب؟', [{ value: 'delay', label: 'وقت ضايع وإعادة شغل' }, { value: 'errors', label: 'أخطاء في الحساب أو المخزون' }, { value: 'loss', label: 'فقد مبيعات أو تكلفة إضافية' }, { value: 'stops', label: 'الشغل ممكن يقف' }, { value: 'minor', label: 'إزعاج بسيط وأقدر أتعامل معاه' }, { value: 'unsure', label: 'مش متأكد' }]]
      ];
      for (const [key, label, options] of fields) {
        const id = q.id + '__' + key, l = el('label', 'field-label', label); l.htmlFor = id;
        const input = selectControl(id, label, options, data[key], v => { const n = { ...(state.answers[q.id] || {}) }; if (!v) delete n[key]; else n[key] = key === 'impact' && v !== 'unsure' ? Number(v) : v; update(q.id, n, false); }); box.append(l, input);
      }
      const label = el('label', 'field-label', 'مثال افتراضي بسيط، وإيه اللي تتوقعه بعد الحل؟ (اختياري)'); label.htmlFor = q.id + '__example';
      const text = el('textarea'); text.id = label.htmlFor; text.maxLength = 1500; text.value = data.example || ''; text.setAttribute('aria-label', label.textContent); text.addEventListener('input', () => update(q.id, { ...(state.answers[q.id] || {}), example: text.value }, false)); box.append(label, el('p', 'help', 'ما تكتبش أسماء أو أرقام عملاء أو مستندات ومبالغ حقيقية.'), text);
    } else if (q.type === 'access') {
      const labels = {finance:'عرض التكلفة والربح والأرصدة',pricing:'تغيير السعر والخصم',returns:'إلغاء أو مرتجع',stock:'تعديل الصنف أو تسوية الجرد',export:'تصدير البيانات أو استعادتها'};
      const options = [{value:'allow',label:'مسموح'},{value:'approve',label:'بموافقة مسؤول'},{value:'deny',label:'غير مسموح'},{value:'unsure',label:'محتاجين نحدده مع بعض'}];
      for (const [key,label] of Object.entries(labels)) {
        const row=el('div','structured-row'),id=q.id+'__'+key,l=el('label','',label);l.htmlFor=id;
        row.append(l,selectControl(id,label,options,value?.[key],v=>{const n={...(state.answers[q.id]||{})};if(!v)delete n[key];else n[key]=v;update(q.id,n,false);}));box.append(row);
      }
    } else if (q.type === 'timeline' || q.type === 'priorities') {
      const rows = q.type === 'timeline' ? ['3', '6', '12', '24'].map(k => ({ id: k, label: 'خلال ' + k + ' شهور' })) : E.needSeeds(Q, state.answers).filter(n=>!q.rowIds || q.rowIds.includes(n.id)).map(n => ({ id: n.id, label: C.capabilities.find(c => c.id === n.id).label }));
      const options = q.type === 'timeline' ? Q.timelineOptions : Q.priorityOptions;
      for (const item of rows) {
        const row = el('div', 'structured-row'), id = q.id + '__' + item.id, l = el('label', '', item.label); l.htmlFor = id;
        const select = selectControl(id, item.label, options, value?.[item.id], v => { const n = { ...(state.answers[q.id] || {}) }; if (!v) delete n[item.id]; else n[item.id] = v; update(q.id, n, q.type === 'timeline'); }); row.append(l, select); box.append(row);
      }
      box.append(button('سيب غير المحدد «مش متأكد»', () => { const n = { ...(state.answers[q.id] || {}) }; for (const item of rows) if (!n[item.id]) n[item.id] = 'unsure'; update(q.id, n); }, 'quiet'));
    }
    if (state.skippedIds.includes(q.id)) box.append(el('div', 'help', 'السؤال ده مؤجل. لو جاوبته هنستخدم الإجابة الجديدة.'));
    return box;
  }
  function go(id) { current = id; mode = 'editor'; errors = []; save(); render(); }
  function next(skip) {
    const ps = E.pages(Q, state.answers), index = Math.max(0, ps.findIndex(p => p.id === current)), page = ps[index];
    const missing = page.questions.filter(q => q.required && !E.answered(q, state.answers[q.id], Q, state.answers));
    if (missing.length && !skip) { errors = ['جاوب السؤال المناسب، أو اختار مش متأكد، أو اضغط «أجّل وكمل» لو محتاج ترجع له بعدين.']; render(false); root.querySelector('[role=alert]')?.scrollIntoView({ block: 'center' }); return; }
    if (skip) for (const q of page.questions) if (!E.answered(q, state.answers[q.id], Q, state.answers) && !state.skippedIds.includes(q.id)) state.skippedIds.push(q.id);
    if (index + 1 < ps.length) go(ps[index + 1].id); else showSummary();
  }
  function showSummary() { mode = 'summary'; errors = []; const qs = E.visibleQuestions(Q, state.answers); state.completedAt = qs.every(q => !q.required || E.answered(q, state.answers[q.id], Q, state.answers)) ? new Date().toISOString() : null; save(); render(); }
  function editor() {
    const ps = E.pages(Q, state.answers); let index = ps.findIndex(p => p.id === current); if (index < 0) index = 0;
    const sections = Q.sections.filter(s => ps.some(p => p.section.id === s.id));
    const page = ps[index]; current = page.id;
    const bench = el('div', 'workbench'), side = el('aside', 'sidebar'); side.setAttribute('aria-label', 'مراحل الاستبيان'); side.append(el('h2', '', 'خطواتنا مع بعض'));
    const list = el('nav', 'section-list');
    for (const [i, s] of sections.entries()) {
      const target = ps.find(p => p.section.id === s.id); if (!target) continue;
      const b = button('', () => go(target.id), 'section-btn' + (s.id === page.section.id ? ' active' : '')); if (s.id === page.section.id) b.setAttribute('aria-current', 'step');
      const questions = E.visibleQuestions(Q, state.answers).filter(q => q.section === s.id); const done = questions.filter(q => E.answered(q, state.answers[q.id], Q, state.answers) || state.skippedIds.includes(q.id)).length;
      b.append(el('span', 'section-num', String(i + 1)), el('span', '', s.label), el('span', 'count', done + '/' + questions.length)); list.append(b);
    }
    const tools = el('div', 'side-tools'); tools.append(button('تنزيل نسخة للاستكمال', exportAnswers), importButton(), button('عرض ملخص الإجابات', showSummary, 'quiet'), button('حفظ ورجوع للبداية', () => { mode = 'welcome'; save(); render(); }, 'quiet'));
    side.append(list, tools); const content = el('section', 'content');
    const ph = el('div', 'progress-head'); ph.append(el('span', '', 'إنجاز الاستبيان'), el('strong', '', '')); ph.lastChild.id = 'progress-value';
    const track = el('div', 'progress-track'); track.setAttribute('role', 'progressbar'); track.setAttribute('aria-label', 'نسبة إنجاز الاستبيان'); track.setAttribute('aria-valuemin', '0'); track.setAttribute('aria-valuemax', '100'); const fill = el('div', 'progress-fill'); fill.id = 'progress-fill'; track.append(fill);
    const saved = el('div', 'save-line'); saved.id = 'save-line'; saved.setAttribute('role', 'status'); saved.setAttribute('aria-live', 'polite');
    content.append(ph, track, saved); warnings(content);
    const head = el('div', 'page-head'); head.append(el('div', 'kicker', 'خطوة ' + (sections.findIndex(s => s.id === page.section.id) + 1) + ' من ' + sections.length + ' · صفحة ' + (index + 1) + ' من ' + ps.length), el('h1', '', page.section.label), el('p', '', page.section.description));
    const mobile = el('div', 'mobile-tools'); mobile.append(button('حفظ ملف للاستكمال', exportAnswers, 'quiet'), button('ملخص الإجابات', showSummary, 'quiet'), importButton()); head.append(mobile); content.append(head);
    const card = el('div', 'card'); for (const q of page.questions) card.append(questionControl(q)); content.append(card);
    const nav = el('div', 'navigation'); const back = button('→ السابق', () => go(ps[Math.max(0, index - 1)].id), 'quiet'); back.disabled = index === 0;
    const actions = el('div', 'actions'); actions.append(button('أجّل وكمل', () => next(true), 'quiet skip'), button(index + 1 === ps.length ? 'راجع ملخص إجاباتك ←' : 'التالي ←', () => next(false), 'primary'));
    nav.append(back, actions); content.append(nav, el('p', 'page-note', 'النسبة وعدد الصفحات بيتغيروا حسب الأسئلة المناسبة لإجاباتك. الرجوع والتعديل متاحين دائمًا.'));
    bench.append(side, content); root.append(bench); refreshStatus();
  }
  function facts(container, items) {
    const dl = el('dl');
    for (const f of items) { const row = el('div', 'fact-row'); row.append(el('dt', '', f.question), el('dd', '', f.display)); const b = button('تعديل', () => { const page = E.pages(Q, state.answers).find(p => p.questions.some(q => q.id === f.questionId)); if (page) go(page.id); }, 'quiet'); row.append(b); dl.append(row); }
    container.append(dl);
  }
  function summary() {
    let report; try { report = E.analyze(state, Q, C); } catch (e) { warnings(root); root.append(el('div', 'error-box', 'تعذر تجهيز الملخص: ' + e.message)); root.append(button('العودة للإجابات', () => go(E.pages(Q, state.answers)[0].id))); return; }
    const head = el('div', 'summary-head'), intro = el('div'); intro.append(el('span', 'eyebrow', 'قبل ما تبعت لنا الملف'), el('h1', '', 'دي الصورة اللي فهمناها من إجاباتك'), el('p', 'muted', 'راجع وعدّل براحتك. الاستنتاجات والمقترحات مبدئية، ومش معناها موافقة على تنفيذ أو سعر.')); head.append(intro, button('الرجوع للاستبيان', () => go(E.pages(Q, state.answers)[0].id), 'quiet')); root.append(head); warnings(root);
    const customerPending = E.visibleQuestions(Q,state.answers).filter(q => {
      const value=state.answers[q.id];
      return (q.required && !E.answered(q,value,Q,state.answers)) || ['unsure','suggest'].includes(value) || (Array.isArray(value) && value.some(v=>['unsure','suggest'].includes(v))) || (value && typeof value==='object' && Object.values(value).some(v=>['unsure','suggest'].includes(v)));
    });
    if (!state.completedAt || customerPending.length) root.append(el('div', 'warning', 'فيه إجابات مؤجلة أو محتاجة نتكلم فيها. تقدر تبعت النتيجة دلوقتي ونكملها معاك.'));
    root.append(sharingBox());
    const grid = el('div', 'summary-grid'), profile = el('section', 'summary-card'), journey = el('section', 'summary-card'); profile.append(el('h2', '', 'ما قلته عن نشاطك وحجم شغلك')); journey.append(el('h2', '', 'ما قلته عن رحلة الشغل')); facts(profile, report.businessProfile); facts(journey, report.workflow); grid.append(profile, journey); root.append(grid);
    const pain = el('section', 'summary-card'); pain.append(el('h2', '', 'المشكلات اللي ذكرتها'));
    if (report.painStatement) pain.append(el('p', '', report.painStatement));
    for (const p of report.painPoints) { const q = E.expandQuestions(Q).find(q => q.id === 'pain.detail.' + p.id); const block = el('div', 'fact-row'); block.append(el('strong', '', p.label), el('p', '', E.optionLabel(q, state.answers[q.id] || {}, Q))); pain.append(block); } root.append(pain);
    const mob = el('section', 'summary-card'); mob.append(el('span', 'tag', 'ترشيح مبدئي، مش اختيار نهائي'), el('h2', '', report.android.label), el('p', '', report.android.reason), el('p', 'help', 'درجة الثقة: ' + report.android.confidence));
    const compare = el('details'); compare.append(el('summary', '', 'قارن بدائل الهاتف والكمبيوتر')); const scroll = el('div', 'table-scroll'), table = el('table', 'summary-table'); const tr = el('tr'); for (const x of ['البديل', 'التعقيد النسبي', 'مناسبته وحدوده']) tr.append(el('th', '', x)); table.append(tr);
    for (const o of report.android.options) { const row = el('tr'); row.append(el('td', '', o.label), el('td', '', o.complexity), el('td', '', o.reliability)); table.append(row); } scroll.append(table); compare.append(scroll); mob.append(compare);
    if (['view','operations'].includes(state.answers['mobile.need']) || state.answers['business.details']?.includes('mobile')) root.append(mob);
    const pending = el('section', 'summary-card'); pending.append(el('h2', '', 'نقاط محتاجين نراجعها معاك')); const ul = el('ul'); for (const q of customerPending) ul.append(el('li', '', q.label)); if (!customerPending.length) ul.append(el('li', '', 'إجاباتك الحالية واضحة. هنتكلم معاك عن شكل الفاتورة وطريقة استخدامها قبل التسليم.')); pending.append(ul); root.append(pending);
    const deferred = E.visibleQuestions(Q,state.answers).filter(q => !E.answered(q,state.answers[q.id],Q,state.answers) && (q.required || state.skippedIds.includes(q.id)));
    if (deferred.length) { const revisit=el('details','summary-card'); revisit.append(el('summary','','ارجع مباشرة للأسئلة الناقصة أو المؤجلة ('+deferred.length+')')); for (const q of deferred) { const row=el('div','fact-row'); row.append(button(q.label,()=>{const page=E.pages(Q,state.answers).find(p=>p.questions.some(x=>x.id===q.id));if(page)go(page.id);},'quiet'));revisit.append(row); } root.append(revisit); }
    const all = el('details', 'summary-card'); all.append(el('summary', '', 'راجع كل الإجابات النشطة وعدلها')); facts(all, report.clientSaid.filter(x => x.active)); root.append(all);
    const old = report.clientSaid.filter(x => !x.active);
    if (old.length || Object.keys(report.unknownAnswers).length) { const hidden = el('details', 'summary-card'); hidden.append(el('summary', '', 'إجابات محفوظة من مسارات سابقة أو نسخة أخرى'), el('p', 'help', 'احتفظنا بيها للتراجع، لكن مش بنستخدمها في الترشيحات وهي مخفية.')); for (const f of old) hidden.append(el('p', '', f.question + ': ' + f.display)); if (Object.keys(report.unknownAnswers).length) hidden.append(el('pre', 'report-text', JSON.stringify(report.unknownAnswers, null, 2))); root.append(hidden); }
    const expert = el('details', 'summary-card'); expert.append(el('summary', '', 'التقرير التفصيلي والخطة المقترحة للمراجعة'), el('p', 'help', 'ده بيفصل كلامك عن الاستنتاجات وخطوات التطوير. مفيش ميزة هتتنفذ منه تلقائيًا.'), el('pre', 'report-text', E.markdown(report))); root.append(expert);
    const downloads = el('details', 'download-box export-options'); downloads.append(el('summary', '', 'خيارات إضافية: حفظ أو استيراد نسخة وتقرير للقراءة'), el('p', '', 'تقدر تحتفظ بنسخة للاستكمال. المشاركة على واتساب موجودة في أول الملخص.'));
    const checked = el('label', 'review-check'), cb = document.createElement('input'); cb.type = 'checkbox'; cb.checked = !!state.reviewedAt; cb.addEventListener('change', () => { state.reviewedAt = cb.checked ? new Date().toISOString() : null; save(); }); checked.append(cb, el('span', '', 'راجعت الملخص، وعارف إن أي نقطة ناقصة هنأكدها قبل التنفيذ. (اختياري؛ تقدر تصدّر مسودة من غيره)')); downloads.append(checked);
    const actions = el('div', 'actions'); actions.append(button('تنزيل ملف الإجابات JSON', exportAnswers, 'primary'), button('تنزيل تقرير للقراءة', () => download('alikhlas-needs-report.html', E.readableHtml(E.analyze(state, Q, C)), 'text/html;charset=utf-8')), button('تقرير Markdown', () => download('alikhlas-needs-report.md', E.markdown(E.analyze(state, Q, C)), 'text/markdown;charset=utf-8'), 'quiet'), importButton()); downloads.append(actions); root.append(downloads);
    root.append(el('p', 'footer-help', 'لو المتصفح منع التنزيل، استخدم متصفحًا كاملًا زي Chrome أو Edge، مش معاينة الملف داخل الرسائل. احتفظ بالـJSON لو هتغيّر الجهاز.'));
    root.append(button('مسح المحفوظ من الجهاز بعد تنزيله', () => { if (window.confirm('اتأكد إنك نزلت ملف الإجابات. هنمسح النسخة من المتصفح ده فقط؛ الملفات اللي نزلتها هتفضل عندك. نكمل؟')) { try { localStorage.removeItem(KEY); if (localStorage.getItem(KEY) !== null) throw Error('Removal failed'); } catch (_) { notify('تعذر مسح المحفوظ. امسحه من إعدادات المتصفح لو الجهاز مش جهازك.'); return; } state = E.newEnvelope(Q, C.projectCommit); mode = 'welcome'; current = null; render(); } }, 'quiet danger'));
  }
  function render(navigate = true) {
    const focusId = document.activeElement?.id;
    root.replaceChildren();
    if (mode === 'welcome') welcome(); else if (mode === 'summary') summary(); else editor();
    if (navigate) { window.scrollTo({ top: 0, behavior: 'instant' }); const h = root.querySelector('h1'); if (h) { h.tabIndex = -1; h.focus({ preventScroll: true }); } }
    else if (focusId) document.getElementById(focusId)?.focus({ preventScroll: true });
  }
  window.addEventListener('beforeunload', event => { if (mode !== 'welcome') save(); if (!storageOkay && Object.keys(state.answers).length) { event.preventDefault(); event.returnValue = ''; } });
  document.addEventListener('visibilitychange', () => { if (document.hidden && mode !== 'welcome') save(); });
  const configErrors = E.validateConfig(Q, C);
  if (configErrors.length) { root.append(el('div', 'error-box', 'تعريف الاستبيان غير سليم. استخدم نسخة كاملة من الملف.')); return; }
  readCache(); render();
})();
