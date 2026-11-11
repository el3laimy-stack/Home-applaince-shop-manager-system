#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require=createRequire(import.meta.url),root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),E=require('../lib/engine.js');
const Q=JSON.parse(fs.readFileSync(path.join(root,'data/questionnaire.json'),'utf8')),C=JSON.parse(fs.readFileSync(path.join(root,'data/capabilities.json'),'utf8'));
const args=process.argv.slice(2),input=args[0],pos=args.indexOf('--out');
if(!input||input.startsWith('--')){console.error('Usage: node tools/analyze.mjs answers.json --out output-directory [--force]');process.exit(2);}
try{
 if(pos>=0&&(!args[pos+1]||args[pos+1].startsWith('--')))throw Error('--out يحتاج مسار مجلد للإخراج.');
 const file=path.resolve(input);if(fs.statSync(file).size>1500000)throw Error('ملف الإجابات أكبر من الحد 1.5MB.');
 const checked=E.validateEnvelope(fs.readFileSync(file,'utf8'),Q,C);if(!checked.ok)throw Error(checked.errors.join('\n'));
 const output=path.resolve(pos>=0?args[pos+1]||'':path.join(path.dirname(file),path.basename(file,'.json')+'-analysis'));
 if(output===file)throw Error('مسار الإخراج لا يمكن أن يكون ملف الإدخال.');
 const report=E.analyze(checked.value,Q,C),files={
 'normalized-answers.json':JSON.stringify(checked.value,null,2)+'\n',
 'analysis.json':JSON.stringify(report,null,2)+'\n',
 'requirements-report.md':E.markdown(report),
 'requirements-report.html':E.readableHtml(report),
 'development-plan.md':E.planMarkdown(report)
 };
 if(Object.keys(files).some(name=>path.resolve(output,name)===file))throw Error('الإخراج قد يستبدل ملف الإدخال؛ اختار مجلدًا آخر.');
 if(!args.includes('--force'))for(const name of Object.keys(files))if(fs.existsSync(path.join(output,name)))throw Error('ملف الإخراج موجود؛ استخدم مجلدًا جديدًا أو --force: '+name);
 fs.mkdirSync(output,{recursive:true});for(const [name,text]of Object.entries(files))fs.writeFileSync(path.join(output,name),text);
 console.log('تم التحقق والتحليل محليًا. المخرجات: '+output);
 for(const w of checked.warnings)console.error('تنبيه: '+w);
 console.log('احتياجات: '+report.gaps.length+'؛ نقاط تحتاج مراجعة: '+report.unresolved.length+'؛ ترشيح: '+report.android.label);
}catch(e){console.error('لم يتم التحليل: '+e.message);process.exitCode=1;}
