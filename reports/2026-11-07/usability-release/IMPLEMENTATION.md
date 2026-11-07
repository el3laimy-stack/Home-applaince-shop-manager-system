# Usability release 1.2.0+12

Approved scope: one release for all screens; unified quantity table for sale/purchase;
retain glass style; cash-full default; multiple suspended drafts; 500ms autosave;
save then preview; thermal 58/80 mm; optional 250mm segments; no invoice CSV import.

Baseline: 3da28cf34d402a8c5eb73fff19efe8656809857a plus the preceding local visual-layout fixes.
Implementation/review continued on 8 November 2026 (Cairo).

## Implemented

- Schema 13 and byte-preserving legacy draft migration. Multiple sale/purchase
  workspaces, names, suspension/resumption, delete/export and CAS revisions.
- Serialized autosave and departure flushing. Raw invalid quantities, purchase
  costs and payment text survive editing/restart. Storage errors retain dirty
  text and expose retry. Unreadable payloads remain preserved until explicit action.
- Pending operation/workspace association uses the operation key; acknowledgement
  removes only the matching submitting workspace. Existing recovery/idempotency
  and negative-balance consent remain in force.
- Unified virtual quantity tables, Arabic/digit-normalized search, categories,
  selected-only filtering, review/payment stages and cash default. F2, arrows,
  Enter and Tab/Shift+Tab work with virtual rows; Ctrl+Enter advances review.
- Responsive navigation, daily shortcuts, optional inventory fields, parties/
  installment layout fixes, payment preview, sale/purchase invoice history,
  settings/backup/help improvements and Arabic operating guide.
- Thermal profiles, finite PDF jobs, exact preview/print bytes, long/split
  receipts, test page and explicit submitted/cancelled/failed outcomes.
  Purchase receipts include initial payments only, excluding later collections.

## Verification recorded so far

- Workspaces/legacy drafts/pending requests: 11 initial tests passed, followed
  by added storage-failure and CAS recovery coverage.
- Actual 100 selections from 200 products: sale and purchase scenarios implemented;
  Arabic keyboard/virtual-row traversal and raw invalid suspend/resume covered.
- Thermal widths 58/80, 1/100/500 Arabic lines, long/split pages and preferences:
  9 tests; with receipt UI/reprinting/cancellation: final targeted run 11 passed.
- Schema12->13 payload preservation and prior migration/recovery/backup coverage;
  portable restore now verifies suspended raw workspaces and print preferences.
- Updated 10 golden/responsive tests passed during generation; complete rerun
  without updates is running. Final whole-suite and CI outcomes are recorded in
  the delivery report when complete, not inferred from targeted runs.
- Static analysis: no issues. Process lock: contender rejected, successor acquired.

## Native visual review

Ran compiled Dart AOT on Linux using Flutter 3.44.2 and the existing matching
runner/plugins in an isolated demo directory. Inspected daily screen, a 200-item
catalog with 100 selected lines at 1280x800 and 1024x720, review/payment, purchases,
suspended invoices, history, receipt details/PDF preview and thermal settings.
Reviewed rendered 58/80mm PDF samples. The preview width was then limited to a
readable thermal size; final capture/build verification follows in the delivery report.
Software rendering was used only for this local Xorg review. Full native packages
must come from the final CI builds. No physical printer or Windows device was used.

## Delivery still being verified

Final complete test run, final native preview captures, Windows/Linux CI packages,
and a consolidated screenshot/PDF/log archive. Do not treat this checkpoint as a
claim that pending checks passed.

Arabic guide: [USABILITY_GUIDE_AR.md](../../../Frontend/alikhlas_pos/USABILITY_GUIDE_AR.md).
