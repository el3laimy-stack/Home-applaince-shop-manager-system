"""Development-only browser checks; uses existing Playwright + Chromium, no app dependencies."""
import json, pathlib, shutil, tempfile
from playwright.sync_api import sync_playwright
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/artifacts'
OUT.mkdir(exist_ok=True)
KEY = 'alikhlas.client-discovery.v1'
checks = []

def ok(name, assertion=True):
    assert assertion, name
    checks.append(name)
    print('PASS', name, flush=True)

def stored(p):
    return p.evaluate('(key)=>JSON.parse(localStorage.getItem(key))', KEY)

def download(p, label):
    with p.expect_download() as event:
        p.get_by_role('button', name=label, exact=True).first.click()
    return pathlib.Path(event.value.path()).read_text()

def fill_question(p, q, value):
    qid, kind = q['id'], q['type']
    if value is None: return
    box = p.locator('[data-question="'+qid+'"]')
    if kind in ('single','rating','multi'):
        for v in value if kind == 'multi' else [value]:
            box.locator('input[value="'+str(v)+'"]').check()
    elif kind == 'text': box.locator('textarea,input[type=text]').fill(value)
    else:
        for k,v in value.items():
            control=p.locator('[id="'+qid+'__'+k+'"]')
            if control.count():
                if control.evaluate('(e)=>e.tagName') == 'SELECT': control.select_option(str(v))
                else: control.fill(str(v))

def main():
    with tempfile.TemporaryDirectory(prefix='alikhlas-html-alone-') as temp, sync_playwright() as pw:
        # Deliberately copy only the HTML; no scripts, data or sibling folders.
        isolated=pathlib.Path(temp)/'Survey.html'
        shutil.copy(ROOT/'dist/ALIkhlas-Survey.html',isolated)
        url='http://localhost:31460/ALIkhlas-Survey.html'
        standalone=isolated.read_text()
        def local_document(route):
            if route.request.url==url: route.fulfill(status=200,content_type='text/html; charset=utf-8',body=standalone)
            else: route.abort()
        def context_for(**kwargs):
            ctx=browser.new_context(**kwargs)
            ctx.route('**/*',local_document)
            return ctx
        browser=pw.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
        for case,width in [('small-shop',1280),('medium-service-installments',390),('multi-branch',360)]:
            fixture=json.loads((ROOT/'examples'/f'{case}.answers.json').read_text())
            context=context_for(viewport={'width':width,'height':900},offline=True,accept_downloads=True)
            page=context.new_page(); errors=[]; external=[]
            page.on('pageerror',lambda e:errors.append(str(e)))
            page.on('request',lambda r:external.append(r.url) if r.url.startswith(('http:','https:')) and r.url!=url else None)
            page.goto(url)
            ok(case+' offline welcome',page.get_by_role('button',name='نبدأ الاستبيان',exact=True).is_visible())
            page.screenshot(path=str(OUT/f'{case}-welcome.png'),full_page=True)
            page.get_by_role('button',name='نبدأ الاستبيان',exact=True).click()
            for step in range(100):
                if page.locator('.summary-head').count(): break
                if step==0:
                    # Missing required data never silently advances.
                    page.locator('.navigation .primary').click()
                    ok(case+' missing answers message',page.locator('[role=alert]').count()==1)
                done=set()
                # Conditional insertion may move the former second card to the next page.
                for _ in range(12):
                    qids=page.locator('[data-question]').evaluate_all('(es)=>es.map(e=>e.dataset.question)')
                    pending=[qid for qid in qids if qid not in done]
                    if not pending: break
                    qid=pending[0];done.add(qid)
                    q=page.evaluate('(id)=>Discovery.expandQuestions(JSON.parse(document.getElementById("questionnaire-data").textContent)).find(q=>q.id===id)',qid)
                    if qid in fixture['answers']: fill_question(page,q,fixture['answers'][qid])
                ok_overflow=page.evaluate('document.documentElement.scrollWidth <= innerWidth + 1')
                assert ok_overflow, (case,step,qids,'horizontal overflow')
                if step==2: page.screenshot(path=str(OUT/f'{case}-questions.png'),full_page=True)
                if step==3:
                    before=stored(page)['answers'];page.reload()
                    page.get_by_role('button',name='استكمال إجاباتك',exact=True).click()
                    ok(case+' reload resumes all answers',stored(page)['answers']==before)
                page.locator('.navigation .primary').click()
                if page.locator('[role=alert]').count():
                    raise AssertionError((case,step,qids,page.locator('[role=alert]').inner_text()))
            else: raise AssertionError('Questionnaire did not terminate')
            ok(case+' completes real UI path',page.locator('.summary-head').count()==1)
            state=stored(page)
            ok(case+' required answers complete',state['completedAt'] is not None)
            active=set(page.evaluate('(a)=>Discovery.visibleQuestions(JSON.parse(document.getElementById("questionnaire-data").textContent),a).map(q=>q.id)',state['answers']))
            for qid,v in fixture['answers'].items():
                if qid not in active: continue
                assert state['answers'].get(qid)==v,(case,qid,state['answers'].get(qid),v)
            ok(case+' all scenario answers match',True)
            raw=download(page,'تنزيل ملف الإجابات JSON'); exported=json.loads(raw)
            ok(case+' exported JSON preserves answers',exported['answers']==state['answers'])
            html=download(page,'تنزيل تقرير للقراءة')
            ok(case+' readable report exported','<!doctype html>' in html and 'ما قاله العميل' in html)
            page.evaluate('window.scrollTo(0,0)')
            page.screenshot(path=str(OUT/f'{case}-summary.png'),full_page=False)
            # Reimport exact file and resume through UI, then re-export.
            imp=pathlib.Path(temp)/(case+'.json');imp.write_text(raw)
            page.once('dialog',lambda d:d.accept())
            page.locator('input[type=file]').first.set_input_files(str(imp))
            page.get_by_role('button',name='استكمال إجاباتك',exact=True).wait_for()
            page.get_by_role('button',name='استكمال إجاباتك',exact=True).click()
            ok(case+' import resumes summary',page.locator('.summary-head').count()==1)
            ok(case+' import/export lossless',json.loads(download(page,'تنزيل ملف الإجابات JSON'))['answers']==exported['answers'])
            # Invalid import must retain current answers.
            imp.write_text('{"schemaVersion":"2.0.0"}')
            page.locator('input[type=file]').first.set_input_files(str(imp))
            page.locator('[role=alert]').wait_for()
            ok(case+' invalid import does not replace data',stored(page)['answers']==exported['answers'])
            ok(case+' no JS errors / external requests',not errors and not external)
            ok(case+' Arabic RTL',page.locator('html').get_attribute('dir')=='rtl' and page.locator('html').get_attribute('lang')=='ar')
            # Cancel a valid replacement; current response remains intact.
            imp.write_text(json.dumps(fixture))
            page.once('dialog',lambda d:d.dismiss())
            page.locator('input[type=file]').first.set_input_files(str(imp))
            page.wait_for_timeout(100)
            ok(case+' cancelled import preserves response',stored(page)['responseId']==exported['responseId'])
            # Read the exported report in a fresh offline browser context.
            rc=browser.new_context(offline=True,viewport={'width':width,'height':900})
            rc.route('**/*',lambda route:route.fulfill(status=200,content_type='text/html; charset=utf-8',body=html))
            rp=rc.new_page();rp.goto('http://localhost:31460/report.html')
            ok(case+' report responsive Arabic',rp.locator('html').get_attribute('dir')=='rtl' and rp.evaluate('document.documentElement.scrollWidth <= innerWidth + 1'))
            rc.close()
            context.close()
        # Hidden answers and immediate persistence use actual form changes.
        c=context_for(offline=True,viewport={'width':1280,'height':900},accept_downloads=True)
        p=c.new_page();p.goto(url);p.get_by_role('button',name='نبدأ الاستبيان',exact=True).click()
        p.locator('input[type=text]').fill('اسم افتراضي <script>اختبار</script>')
        p.reload();p.get_by_role('button',name='استكمال إجاباتك',exact=True).click()
        ok('text is saved immediately before leaving field',stored(p)['answers']['business.alias'].startswith('اسم افتراضي'))
        p.locator('.section-btn').filter(has_text='الهاتف').click()
        p.locator('[data-question="mobile.need"] input[value="operations"]').check()
        p.locator('.navigation .primary').click()
        # User/task questions now visible. Persist an actual task, then hide its branch.
        qids=p.locator('[data-question]').evaluate_all('(es)=>es.map(e=>e.dataset.question)')
        if 'mobile.tasks' not in qids:
            p.locator('.navigation .skip').click()
        p.locator('[data-question="mobile.tasks"] input[value="sale"]').check()
        p.locator('.section-btn').filter(has_text='الهاتف').click()
        p.locator('[data-question="mobile.need"] input[value="none"]').check()
        ok('conditional child disappears',p.locator('[data-question="mobile.tasks"]').count()==0)
        p.locator('[data-question="mobile.noReason"] input').first.check()
        ok('hidden task retained',stored(p)['answers']['mobile.tasks']==['sale'])
        p.locator('.side-tools').get_by_role('button',name='عرض ملخص الإجابات',exact=True).click()
        ok('partial review remains draft',stored(p)['completedAt'] is None)
        ok('deferred questions can be revisited directly',p.get_by_text('ارجع مباشرة للأسئلة الناقصة أو المؤجلة',exact=False).count()==1)
        ok('stale task not used to infer mobile need',p.get_by_role('heading',level=2,name='الاكتفاء بسطح المكتب',exact=True).count()==1)
        # Keyboard can leave inputs and reach navigation without a focus trap.
        p.get_by_role('button',name='الرجوع للاستبيان',exact=True).click()
        p.locator('input[type=text]').focus(); seen=set()
        for _ in range(35):
            p.keyboard.press('Tab');seen.add(p.evaluate('document.activeElement.tagName'))
        ok('keyboard reaches buttons outside question controls','BUTTON' in seen)
        p.locator('.side-tools').get_by_role('button',name='عرض ملخص الإجابات',exact=True).click()
        p.evaluate("()=>{Storage.prototype.removeItem=function(){throw Error('blocked remove')}}")
        p.once('dialog',lambda d:d.accept())
        p.get_by_role('button',name='مسح المحفوظ من الجهاز بعد تنزيله',exact=True).click()
        ok('failed deletion does not claim data cleared',p.locator('.summary-head').count()==1 and bool(stored(p)['answers']))
        c.close()
        # Disabled storage and quota failures remain visible and permit download.
        for failure in ('blocked','quota','corrupt'):
            c=context_for(offline=True,accept_downloads=True)
            if failure=='blocked':
                c.add_init_script("Object.defineProperty(window,'localStorage',{get(){throw Error('blocked')}})")
            elif failure=='quota':
                c.add_init_script("Storage.prototype.setItem=function(){throw Error('quota')}")
            else: c.add_init_script("localStorage.setItem('alikhlas.client-discovery.v1','{broken')")
            p=c.new_page();p.goto(url)
            ok(failure+' persistent warning',p.locator('#storage-warning').is_visible())
            if failure=='corrupt':
                ok('corrupt saved data can be recovered','{broken'==download(p,'تنزيل المحفوظ غير المقروء للفحص'))
                p.once('dialog',lambda d:d.accept())
            p.get_by_role('button',name='نبدأ الاستبيان',exact=True).click()
            p.locator('input[type=text]').fill('اختبار حفظ')
            raw=download(p,'تنزيل نسخة للاستكمال')
            ok(failure+' export still works',json.loads(raw)['answers']['business.alias']=='اختبار حفظ')
            c.close()
        browser.close()
    (OUT/'browser-results.json').write_text(json.dumps({'checks':checks,'passed':len(checks),'browser':'Chromium, Linux; offline routed standalone document at permitted localhost; 360/390/1280 widths','limitation':'Managed Chromium blocks file:// by policy; raw file protocol not verified in this environment.'},ensure_ascii=False,indent=2))
    print('TOTAL',len(checks),'checks passed')

if __name__=='__main__':main()
