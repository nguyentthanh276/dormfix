import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/admin_requests/models/admin_request_transition_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-045/046/047/048 Admin transition rules', () {
    test('only pending requests can be assigned or rejected', () {
      expect(
        AdminRequestTransitionRules.allows(
          AdminRequestAdminAction.assign,
          RepairStatus.pending,
        ),
        isTrue,
      );
      expect(
        AdminRequestTransitionRules.allows(
          AdminRequestAdminAction.reject,
          RepairStatus.pending,
        ),
        isTrue,
      );
      for (final status in RepairStatus.values.where(
        (status) => status != RepairStatus.pending,
      )) {
        expect(
          AdminRequestTransitionRules.allows(
            AdminRequestAdminAction.assign,
            status,
          ),
          isFalse,
          reason: 'assignment must be blocked for ${status.databaseValue}',
        );
        expect(
          AdminRequestTransitionRules.allows(
            AdminRequestAdminAction.reject,
            status,
          ),
          isFalse,
          reason: 'rejection must be blocked for ${status.databaseValue}',
        );
      }
    });

    test('transfer is limited to the three approved statuses', () {
      for (final status in RepairStatus.values) {
        expect(
          AdminRequestTransitionRules.allows(
            AdminRequestAdminAction.transfer,
            status,
          ),
          {
            RepairStatus.assigned,
            RepairStatus.inProgress,
            RepairStatus.awaitingRework,
          }.contains(status),
          reason: 'transfer rule for ${status.databaseValue}',
        );
      }
    });

    test(
      'DF-048 only exposes handling for a revoked student awaiting confirm',
      () {
        for (final action in [
          AdminRequestAdminAction.confirmForRevokedStudent,
          AdminRequestAdminAction.requestReworkForRevokedStudent,
        ]) {
          expect(
            AdminRequestTransitionRules.allows(
              action,
              RepairStatus.awaitingConfirmation,
              studentAccountStatus: 'revoked',
            ),
            isTrue,
          );
          for (final accountStatus in ['active', 'locked']) {
            expect(
              AdminRequestTransitionRules.allows(
                action,
                RepairStatus.awaitingConfirmation,
                studentAccountStatus: accountStatus,
              ),
              isFalse,
            );
          }
        }
      },
    );
  });
}
