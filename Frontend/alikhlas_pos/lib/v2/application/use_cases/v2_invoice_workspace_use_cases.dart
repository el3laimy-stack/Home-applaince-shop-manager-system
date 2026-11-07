part of '../v2_use_cases.dart';

class WorkspaceConflict implements Exception {
  const WorkspaceConflict();
  @override
  String toString() => 'تغيرت المسودة أو أُغلقت. أعد فتحها قبل تعديلها.';
}

/// Version two wraps a legacy validated draft and the exact editor text. Raw
/// input is never used to post an invoice without normal business validation.
Map<String, dynamic> decodeWorkspace(String payload) {
  final data = jsonDecode(payload) as Map<String, dynamic>;
  if (data['version'] != 1 && data['version'] != 2) {
    throw const FormatException('Unsupported workspace version');
  }
  if (data['version'] == 2 &&
      (data['editor'] is! Map ||
          (data['draft'] != null && data['draft'] is! Map))) {
    throw const FormatException('Invalid workspace editor');
  }
  return data;
}

String? workspaceDraft(String payload) {
  final data = decodeWorkspace(payload);
  if (data['version'] == 1) return payload;
  final draft = data['draft'];
  return draft == null ? null : jsonEncode(draft);
}

extension V2InvoiceWorkspaceUseCases on V2UseCases {
  void _checkWorkspaceKind(String kind) {
    if (kind != 'sale' && kind != 'purchase') {
      throw ArgumentError.value(kind, 'kind');
    }
  }

  Future<void> _importLegacyWorkspace(String kind) async {
    _checkWorkspaceKind(kind);
    final legacyKey = 'draft.$kind.v1';
    final legacy = await (db.select(
      db.appSettings,
    )..where((r) => r.key.equals(legacyKey))).getSingleOrNull();
    if (legacy == null) return;
    final active =
        await (db.select(db.checkoutDrafts)
              ..where((r) => r.kind.equals(kind) & r.state.equals('editing')))
            .getSingleOrNull();
    await db
        .into(db.checkoutDrafts)
        .insert(
          CheckoutDraftsCompanion.insert(
            id: newFinancialOperationKey(),
            kind: kind,
            label: kind == 'sale' ? 'مسودة بيع سابقة' : 'مسودة شراء سابقة',
            state: Value(active == null ? 'editing' : 'suspended'),
            payload: legacy.value,
            createdAt: clock(),
            updatedAt: clock(),
          ),
        );
    await (db.delete(
      db.appSettings,
    )..where((r) => r.key.equals(legacyKey))).go();
  }

  Future<CheckoutDraft?> activeInvoiceWorkspace(String kind) =>
      _writeTransaction(() async {
        await _importLegacyWorkspace(kind);
        return (db.select(db.checkoutDrafts)
              ..where((r) => r.kind.equals(kind) & r.state.equals('editing')))
            .getSingleOrNull();
      });

  Future<List<CheckoutDraft>> invoiceWorkspaces(String kind) =>
      _writeTransaction(() async {
        await _importLegacyWorkspace(kind);
        return (db.select(db.checkoutDrafts)
              ..where((r) => r.kind.equals(kind))
              ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]))
            .get();
      });

  Future<CheckoutDraft> saveInvoiceWorkspace({
    required String kind,
    required String payload,
    String? id,
    int? expectedRevision,
    String? label,
  }) => _writeTransaction(() async {
    _checkWorkspaceKind(kind);
    decodeWorkspace(payload);
    if ((kind == 'sale' && await pendingSale() != null) ||
        (kind == 'purchase' && await pendingPurchase() != null)) {
      throw StateError('تحقق من نتيجة الطلب السابق قبل تعديل المسودة.');
    }
    await _importLegacyWorkspace(kind);
    final active =
        await (db.select(db.checkoutDrafts)
              ..where((r) => r.kind.equals(kind) & r.state.equals('editing')))
            .getSingleOrNull();
    if (id != null &&
        (active?.id != id || active?.revision != expectedRevision)) {
      throw const WorkspaceConflict();
    }
    if (active == null) {
      if (id != null) throw const WorkspaceConflict();
      final newId = newFinancialOperationKey();
      await db
          .into(db.checkoutDrafts)
          .insert(
            CheckoutDraftsCompanion.insert(
              id: newId,
              kind: kind,
              label: (label?.trim().isNotEmpty ?? false)
                  ? label!.trim()
                  : '${kind == 'sale' ? 'بيع' : 'شراء'} ${clock().toIso8601String().substring(0, 19).replaceFirst('T', ' ')}',
              payload: payload,
              createdAt: clock(),
              updatedAt: clock(),
            ),
          );
      return (db.select(
        db.checkoutDrafts,
      )..where((r) => r.id.equals(newId))).getSingle();
    }
    final changed =
        await (db.update(db.checkoutDrafts)..where(
              (r) =>
                  r.id.equals(active.id) &
                  r.revision.equals(active.revision) &
                  r.state.equals('editing'),
            ))
            .write(
              CheckoutDraftsCompanion(
                payload: Value(payload),
                label: label == null
                    ? const Value.absent()
                    : Value(label.trim().isEmpty ? active.label : label.trim()),
                revision: Value(active.revision + 1),
                updatedAt: Value(clock()),
              ),
            );
    if (changed != 1) throw const WorkspaceConflict();
    return (db.select(
      db.checkoutDrafts,
    )..where((r) => r.id.equals(active.id))).getSingle();
  });

  Future<void> suspendInvoiceWorkspace(String id) =>
      _writeTransaction(() async {
        final count =
            await (db.update(
              db.checkoutDrafts,
            )..where((r) => r.id.equals(id) & r.state.equals('editing'))).write(
              CheckoutDraftsCompanion(
                state: const Value('suspended'),
                revision: const Value.absent(),
                updatedAt: Value(clock()),
              ),
            );
        if (count != 1) throw const WorkspaceConflict();
      });

  Future<CheckoutDraft> resumeInvoiceWorkspace(String id) => _writeTransaction(
    () async {
      final target = await (db.select(
        db.checkoutDrafts,
      )..where((r) => r.id.equals(id))).getSingle();
      if (target.state == 'submitting' ||
          (target.kind == 'sale' && await pendingSale() != null) ||
          (target.kind == 'purchase' && await pendingPurchase() != null)) {
        throw StateError('تحقق من طلب الحفظ قبل استكمال فاتورة أخرى.');
      }
      await (db.update(db.checkoutDrafts)..where(
            (r) => r.kind.equals(target.kind) & r.state.equals('editing'),
          ))
          .write(const CheckoutDraftsCompanion(state: Value('suspended')));
      await (db.update(db.checkoutDrafts)..where((r) => r.id.equals(id))).write(
        CheckoutDraftsCompanion(
          state: const Value('editing'),
          revision: Value(target.revision + 1),
          updatedAt: Value(clock()),
        ),
      );
      return (db.select(
        db.checkoutDrafts,
      )..where((r) => r.id.equals(id))).getSingle();
    },
  );

  Future<void> deleteInvoiceWorkspace(String id) => _writeTransaction(() async {
    final target = await (db.select(
      db.checkoutDrafts,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (target == null) return;
    if (target.state == 'submitting') {
      throw StateError('لا يمكن حذف طلب جارٍ التحقق من حفظه.');
    }
    await (db.delete(db.checkoutDrafts)..where((r) => r.id.equals(id))).go();
  });

  Future<void> renameInvoiceWorkspace(String id, String label) =>
      _writeTransaction(() async {
        if (label.trim().isEmpty || label.trim().length > 120) {
          throw ArgumentError('اسم الفاتورة مطلوب وبحد أقصى 120 حرفًا.');
        }
        await (db.update(db.checkoutDrafts)..where(
              (r) => r.id.equals(id) & r.state.equals('submitting').not(),
            ))
            .write(
              CheckoutDraftsCompanion(
                label: Value(label.trim()),
                updatedAt: Value(clock()),
              ),
            );
      });

  Future<String?> _stageWorkspace(String kind, String operationKey) async {
    await _importLegacyWorkspace(kind);
    final active =
        await (db.select(db.checkoutDrafts)
              ..where((r) => r.kind.equals(kind) & r.state.equals('editing')))
            .getSingleOrNull();
    if (active == null) return null;
    await (db.update(
      db.checkoutDrafts,
    )..where((r) => r.id.equals(active.id))).write(
      CheckoutDraftsCompanion(
        state: const Value('submitting'),
        operationKey: Value(operationKey),
        revision: Value(active.revision + 1),
        updatedAt: Value(clock()),
      ),
    );
    return active.id;
  }

  Future<void> _finishWorkspace(String kind, String operationKey) async {
    await (db.delete(db.checkoutDrafts)..where(
          (r) =>
              r.kind.equals(kind) &
              r.operationKey.equals(operationKey) &
              r.state.equals('submitting'),
        ))
        .go();
  }

  Future<void> _restoreWorkspace(
    String kind,
    String operationKey,
    String payload,
  ) async {
    final row =
        await (db.select(db.checkoutDrafts)..where(
              (r) => r.kind.equals(kind) & r.operationKey.equals(operationKey),
            ))
            .getSingleOrNull();
    if (row == null) {
      await db
          .into(db.checkoutDrafts)
          .insert(
            CheckoutDraftsCompanion.insert(
              id: newFinancialOperationKey(),
              kind: kind,
              label: 'طلب مستعاد',
              payload: payload,
              createdAt: clock(),
              updatedAt: clock(),
            ),
          );
    } else {
      final original = decodeWorkspace(row.payload);
      final restoredPayload =
          original['version'] == 2 && original['draft'] == null
          ? jsonEncode({...original, 'draft': jsonDecode(payload)})
          : row.payload;
      await (db.update(
        db.checkoutDrafts,
      )..where((r) => r.id.equals(row.id))).write(
        CheckoutDraftsCompanion(
          state: const Value('editing'),
          operationKey: const Value(null),
          // Keep the editor's original text when returning an uncommitted request.
          payload: Value(restoredPayload),
          revision: Value(row.revision + 1),
          updatedAt: Value(clock()),
        ),
      );
    }
  }
}
