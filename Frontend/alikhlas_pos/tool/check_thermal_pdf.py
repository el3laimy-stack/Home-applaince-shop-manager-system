#!/usr/bin/env python3
"""Verify rendered PDF text across page boundaries; requires Poppler pdftotext.

Generate fixtures with:
flutter test --dart-define=THERMAL_REVIEW_DIR=/tmp/thermal-review test/v2/thermal_receipt_test.dart
python3 tool/check_thermal_pdf.py /tmp/thermal-review
"""
import re
import subprocess
import sys
from pathlib import Path


def verify(path):
    text = subprocess.check_output(['pdftotext', '-layout', str(path), '-'], text=True)
    pages = [p for p in text.split('\f') if p.strip()]
    assert len(pages) > 1, f'{path}: expected split pages'
    seen = []
    for number, page in enumerate(pages, 1):
        rows = [int(i) for i in re.findall(r'ROW-(\d{3})', page)]
        for row in rows:
            price = f'{(123400 + row) / 100:,.2f}'
            assert page.count(price) == 2, f'{path}, page {number}: row {row} split or incomplete'
        seen.extend(rows)
    assert sorted(seen) == list(range(1, 101)), f'{path}: missing or duplicated rows'
    total = sum(123400 + i for i in range(1, 101)) / 100
    total_text = f'{total:,.2f}'
    assert pages[-1].count(total_text) == 4, f'{path}: totals split or incomplete'
    assert 'TOTALS-END' in pages[-1], f'{path}: missing footer'
    assert all(total_text not in p for p in pages[:-1]), f'{path}: premature invoice totals'
    print(f'PASS: {path.name}: 100 complete rows, totals together, {len(pages)} pages')


if __name__ == '__main__':
    root = Path(sys.argv[1])
    for width in (58, 80):
        verify(root / f'atomic-{width}.pdf')
