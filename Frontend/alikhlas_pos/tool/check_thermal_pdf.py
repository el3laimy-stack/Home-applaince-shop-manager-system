#!/usr/bin/env python3
"""Validate text and pagination of Dart-generated thermal PDFs without Poppler.

This parser deliberately handles the PDF features emitted by package:pdf for
our fixture receipts (FlateDecode page streams, Identity-H fonts, ToUnicode
CMaps). Unsupported PDF encodings fail closed instead of silently passing.

Generate fixtures with:
  flutter test --dart-define=THERMAL_REVIEW_DIR=/tmp/thermal-review test/v2/thermal_receipt_test.dart
  python3 tool/check_thermal_pdf.py /tmp/thermal-review
"""

import re
import sys
import zlib
from pathlib import Path


OBJECT_RE = re.compile(rb"(?m)^(\d+) 0 obj\s*(.*?)\bendobj\b", re.DOTALL)
PAGE_RE = re.compile(rb"/Type\s*/Page(?!s)\b")
OBJECT_REF = rb"(\d+)\s+0\s+R"


def pdf_objects(raw):
    assert raw.startswith(b"%PDF-"), "Not a PDF document"
    objects = {int(m.group(1)): m.group(2) for m in OBJECT_RE.finditer(raw)}
    assert objects, "PDF contains no readable objects"
    return objects


def inflate(obj):
    assert b"/Filter/FlateDecode" in obj or b"/Filter /FlateDecode" in obj, (
        "Unsupported PDF stream compression"
    )
    header = re.search(rb"/Length\s+(\d+)", obj)
    marker = re.search(rb"\bstream\r?\n", obj)
    assert header and marker, "PDF stream or byte count is missing"
    start = marker.end()
    size = int(header.group(1))
    assert b"endstream" in obj[start + size:start + size + 20], "Truncated PDF stream"
    return zlib.decompress(obj[start:start + size])


def glyph_map(font, objects):
    ref = re.search(rb"/ToUnicode\s+" + OBJECT_REF, font)
    assert ref, "Font has no ToUnicode mapping"
    source = inflate(objects[int(ref.group(1))])
    # Decode the embedded CID font's actual Unicode map, not OCR.
    mapping = {}
    for body in re.findall(rb"\bbeginbfchar\s*(.*?)\s*endbfchar\b", source, re.DOTALL):
        for cid, ucs in re.findall(rb"<([\dA-Fa-f]+)>\s*<([\dA-Fa-f]+)>", body):
            mapping[int(cid, 16)] = bytes.fromhex(ucs.decode()).decode("utf-16-be")
    for body in re.findall(rb"\bbeginbfrange\s*(.*?)\s*endbfrange\b", source, re.DOTALL):
        for begin, end, first in re.findall(
            rb"<([\dA-Fa-f]+)>\s*<([\dA-Fa-f]+)>\s*<([\dA-Fa-f]+)>", body
        ):
            lo, hi, code = int(begin, 16), int(end, 16), int(first, 16)
            for cid in range(lo, hi + 1):
                mapping[cid] = chr(code + cid - lo)
    assert mapping, "Empty or unsupported ToUnicode font mapping"
    return mapping


def extract_pages(path):
    objects = pdf_objects(path.read_bytes())
    page_dicts = [obj for obj in objects.values() if PAGE_RE.search(obj)]
    assert page_dicts, "PDF has no pages"
    pages = []
    for page in page_dicts:
        content_ref = re.search(rb"/Contents\s+" + OBJECT_REF, page)
        assert content_ref, "Page has no single content stream"
        content = inflate(objects[int(content_ref.group(1))])
        resources = re.search(rb"/Font\s*<<(.+?)>>", page, re.DOTALL)
        assert resources, "Page has no font resources"
        fonts = {}
        for name, number in re.findall(rb"/(F\w+)\s+" + OBJECT_REF, resources.group(1)):
            fonts[name] = glyph_map(objects[int(number)], objects)
        assert fonts, "Page has no extractable fonts"
        strings = []
        for block in re.findall(rb"\bBT\b(.*?)\bET\b", content, re.DOTALL):
            font = re.search(rb"/(F\w+)\s+[\d.]+\s+Tf\b", block)
            assert font and font.group(1) in fonts, "PDF text uses an unknown font"
            cmap = fonts[font.group(1)]
            # Do not assemble identifiers or amounts across unrelated text runs.
            runs = re.findall(rb"\[(.*?)\]\s*TJ\b|<([\dA-Fa-f]+)>\s*Tj\b", block, re.DOTALL)
            assert runs, "Unsupported PDF text operator"
            for sequence, single in runs:
                chunks = re.findall(rb"<([\dA-Fa-f]+)>", sequence) if sequence else [single]
                text = []
                for chunk in chunks:
                    binary = bytes.fromhex(chunk.decode())
                    assert len(binary) % 2 == 0, "Odd CID string length"
                    for i in range(0, len(binary), 2):
                        cid = int.from_bytes(binary[i:i + 2], "big")
                        assert cid in cmap, f"Missing ToUnicode glyph {cid}"
                        text.append(cmap[cid])
                strings.append("".join(text))
        pages.append("\n".join(strings))
    return pages


def verify(path):
    pages = extract_pages(path)
    assert len(pages) > 1, f"{path}: expected split pages"
    assert "STORE-SNAPSHOT" in pages[0], f"{path}: missing shop header"
    assert "BRANCH-SNAPSHOT" in pages[0], f"{path}: missing branch header"
    assert "08-11-2026" in pages[0], f"{path}: missing original invoice date"
    seen = []
    for number, page in enumerate(pages, 1):
        rows = [int(i) for i in re.findall(r"ROW-(\d{3})", page)]
        for row in rows:
            assert 1 <= row <= 100, f"{path}, page {number}: unknown row {row}"
            assert page.count(f"ITEM-{row:03}") == 1, (
                f"{path}, page {number}: missing or split product identity {row}"
            )
            price = f"{(123400 + row) / 100:,.2f}"
            assert page.count(price) == 2, (
                f"{path}, page {number}: row {row} split or incomplete"
            )
        seen.extend(rows)
    assert sorted(seen) == list(range(1, 101)), f"{path}: missing or duplicated rows"
    total = sum(123400 + i for i in range(1, 101)) / 100
    total_text = f"{total:,.2f}"
    assert pages[-1].count(total_text) == 4, f"{path}: totals split or incomplete"
    assert "TOTALS-END" in pages[-1], f"{path}: missing footer"
    assert all(total_text not in p for p in pages[:-1]), f"{path}: premature invoice totals"
    print(f"PASS: {path.name}: 100 complete rows, totals together, {len(pages)} pages")


if __name__ == "__main__":
    root = Path(sys.argv[1])
    for width in (58, 80):
        verify(root / f"atomic-{width}.pdf")
