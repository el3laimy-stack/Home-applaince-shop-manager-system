import 'dart:io';
import 'package:alikhlas_pos/v2/application/v2_use_cases.dart';
import 'package:alikhlas_pos/v2/core/result.dart';
import 'package:alikhlas_pos/v2/data/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unconfirmed recovery survives restart and reissue requires password',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'recovery-confirmation-',
      );
      var db = AppDatabase(NativeDatabase(File('${dir.path}/shop.db')));
      addTearDown(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
      var uc = V2UseCases(db);
      final setup =
          (await uc.setupInitialOwner(
                    fullName: 'مالك',
                    password: 'password123',
                    shopName: 'محل',
                  )
                  as AppSuccess<InitialOwnerSetup>)
              .value;
      expect(await uc.recoveryCodeNeedsConfirmation(), isTrue);
      expect(await uc.confirmRecoveryCodeSaved('wrong'), isFalse);
      await db.close();
      db = AppDatabase(NativeDatabase(File('${dir.path}/shop.db')));
      uc = V2UseCases(db);
      expect(await uc.recoveryCodeNeedsConfirmation(), isTrue);
      expect(
        await uc.reissueUnconfirmedRecoveryCode('wrong'),
        isA<AppFailure<OwnerRecovery>>(),
      );
      final recovery =
          (await uc.reissueUnconfirmedRecoveryCode('password123')
                  as AppSuccess<OwnerRecovery>)
              .value;
      expect(recovery.recoveryCode, isNot(setup.recoveryCode));
      expect(await uc.confirmRecoveryCodeSaved(setup.recoveryCode), isFalse);
      expect(await uc.confirmRecoveryCodeSaved(recovery.recoveryCode), isTrue);
      expect(await uc.recoveryCodeNeedsConfirmation(), isFalse);
      expect(
        await uc.reissueUnconfirmedRecoveryCode('password123'),
        isA<AppFailure<OwnerRecovery>>(),
      );
    },
  );
}
