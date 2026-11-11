"""Optional development validation using JSON Schema Draft 2020-12."""
import copy,json,pathlib
from jsonschema import Draft202012Validator,FormatChecker
root=pathlib.Path(__file__).resolve().parents[1]
def read(p):return json.loads((root/p).read_text())
q=Draft202012Validator(read('schemas/questionnaire.schema.json'),format_checker=FormatChecker())
a=Draft202012Validator(read('schemas/answers.schema.json'),format_checker=FormatChecker())
q.check_schema(q.schema);a.check_schema(a.schema)
q.validate(read('data/questionnaire.json'));count=1
for f in (root/'examples').glob('*.answers.json'):
    e=json.loads(f.read_text());a.validate(e);count+=1
    bad=copy.deepcopy(e);bad['answers']['finance.installments']='invalid'
    assert list(a.iter_errors(bad));count+=1
    bad=copy.deepcopy(e);bad['schemaVersion']='2.0.0'
    assert list(a.iter_errors(bad));count+=1
    extra=copy.deepcopy(e);extra['extensions']['future']={'x':[1,'test']};extra['answers']['unknown.future']='preserve'
    a.validate(extra);count+=1
print(f'{count} JSON Schema checks passed')
