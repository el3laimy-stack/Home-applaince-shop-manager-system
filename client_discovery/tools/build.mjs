#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url), root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = p => fs.readFileSync(path.join(root,p),'utf8');
const Q = JSON.parse(read('data/questionnaire.json')), C = JSON.parse(read('data/capabilities.json')), E = require('../lib/engine.js');
const errors=E.validateConfig(Q,C);
for(const c of C.capabilities)for(const e of c.sources)if(!fs.existsSync(path.resolve(root,'..',e.path)))errors.push('Missing source '+e.path);
if(errors.length)throw Error(errors.join('\n'));
const json = x => JSON.stringify(x).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
let html=read('app/shell.html');
for(const [marker,value]of Object.entries({STYLES:read('app/styles.css'),QUESTIONNAIRE:json(Q),CAPABILITIES:json(C),ENGINE:read('lib/engine.js'),CLIENT:read('app/client.js')}))html=html.replace('/*__'+marker+'__*/',()=>value);
if(/\/\*__\w+__\*\//.test(html))throw Error('Unresolved build marker');
const conditions=c=>!c?'دائمًا':c.all?'كل الشروط: ('+c.all.map(conditions).join(' و ')+')':c.any?'أي شرط: ('+c.any.map(conditions).join(' أو ')+')':c.repeat?'لكل مشكلة اختارها العميل':c.derived?'عند ظهور احتياج من الإجابات':c.question+' '+c.op+' '+JSON.stringify(c.value);
let md='# أسئلة استبيان إخلاص POS\n\nنسخة '+Q.version+'؛ معرّفات ثابتة. هذا الملف يولَّد من data/questionnaire.json؛ عدّل JSON ثم أعد البناء.\n\nالأساسيات مستهدفة في 15–20 دقيقة، والمسارات التفصيلية مشروطة. كل شاشة تعرض سؤالين كحد أقصى أو بطاقة مشكلة/أولويات واحدة. التوقيت مستهدف ولم يُقَس على عينة عملاء بعد.\n';
for(const s of Q.sections){md+='\n## '+s.label+'\n\n'+s.description+'\n';for(const q of Q.questions.filter(q=>q.section===s.id)){md+='\n### `'+q.id+'` — '+q.label+'\n\n- النوع: '+q.type+'؛ '+(q.required?'جوهرية مع إمكان التأجيل الصريح':'اختيارية')+'\n- الظهور: '+conditions(q.when)+'\n- القرار الذي تخدمه: '+q.decision+'\n';if(q.help)md+='- التوضيح للعميل: '+q.help+'\n';if(q.options)md+='- الاختيارات: '+q.options.map(o=>'`'+o.value+'` '+o.label).join('؛ ')+'\n';if(q.repeatFrom)md+='- يُكرر بمعرّف ثابت `'+q.id+'.<problem-id>` للحد الأقصى المحدد من المشكلات المختارة. التكرار والتأثير والنتيجة مطلوبة لفهم المشكلة؛ المثال اختياري.\n';}}
const titles={available:'موجودة',needs_improvement:'موجودة وتحتاج تحسينًا',unavailable:'غير متاحة',needs_verification:'تحتاج تحققًا'};
let caps='# قدرات المشروع من الكود الفعلي\n\nمرجع الدراسة: `'+C.projectCommit+'`؛ التطبيق '+C.appVersion+'؛ قاعدة البيانات '+C.databaseSchema+'.\n\n'+C.reviewScope+'\n\n## المعمارية والحدود\n\nنقطة الدخول lib/main.dart تشغل v2/app/v2_app.dart. الواجهة Flutter/Riverpod، طبقة الاستخدام V2UseCases وأجزاؤها، التخزين Drift/SQLite محلي في الخلفية، دفتر أستاذ مزدوج وقيم نقدية بالوحدة الصغرى وتحقيق نطاق الأموال، مفاتيح عمليات لمنع التكرار وحواجز كتابة عند الاستعادة. الطباعة PDF بخط عربي عبر Printing. المسار الحالي يهيئ windowManager دون تكييف هاتف وشاشة دنيا 1024×720. Windows/Linux لهما بناء ومثبتات واختبارات CI؛ وجود هيكل Android لا يثبت قبول التشغيل.\n\nProducts يحتفظ برصيد صحيح واحد وقيمة تكلفة دقيقة؛ لا Warehouse/Serial/Role/Sync tables. workbenchSnapshot يجلب قوائم الأصناف والأطراف كاملة، لذلك أحجام أكبر من بيانات الاختبار تحتاج قياسًا فعليًا. لا نغيّر الجداول ولا نقرأ بيانات العملاء لتنفيذ الاستبيان.\n\n## طريقة تصنيف الثقة\n\n«موجودة» تعني أن تدفقًا ووظيفة وجدولًا في نقطة الدخول الحالية يثبتانها، ولا تعني ملاءمة كل سياسة عميل. «غير متاحة» تخص النسخة المفحوصة، وليست حكمًا على إمكانية Flutter. توافق الطابعة والأجهزة والقياس الفعلي على الهاتف يحتاج تحققًا منفصلًا. الأمان المحلي لا يعني تشفير ملف SQLite أو نسخ الاستبيان.\n';
for(const c of C.capabilities)caps+='\n### '+c.label+' — '+titles[c.status]+'\n\n'+c.summary+'\n\n'+c.sources.map(e=>'- `'+e.path+'` — `'+e.symbol+'`').join('\n')+'\n';
caps+='\n## عيوب مؤكدة منفصلة عن أقوال العميل\n\nأعيد إنتاجها في مراجعة سابقة باختبارات واجهة مستقلة؛ لا يقال إن العميل واجهها إلا لو قال ذلك. لا تُصلح في هذه المهمة.\n'+C.knownIssues.map(i=>'- `'+i.id+'` '+i.label+' — `'+i.source+'`؛ اختبار القبول: '+i.acceptance).join('\n')+'\n';
const outputs={'dist/ALIkhlas-Survey.html':html,'docs/QUESTIONS_AR.md':md,'docs/PROJECT_CAPABILITIES.md':caps};
for(const [file,value]of Object.entries(outputs)){if(process.argv.includes('--check')){if(!fs.existsSync(path.join(root,file))||read(file)!==value)throw Error('Generated file out of date: '+file);}else fs.writeFileSync(path.join(root,file),value);}
console.log((process.argv.includes('--check')?'Verified':'Built')+' standalone offline HTML and code-linked documentation; '+Q.questions.length+' definitions.');
