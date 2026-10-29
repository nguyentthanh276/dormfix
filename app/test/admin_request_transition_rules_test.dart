import 'package:dormfix/core/models/repair_status.dart';
import 'package:dormfix/features/admin_requests/models/admin_request_transition_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DF-045/046 Admin transition rules', () {
    test('only pending requests can be assigned or rejected', () {
      for (final action in AdminRequestAdminAction.values) {
        expect(
          AdminRequestTransitionRules.allows(action, RepairStatus.pending),
          isTrue,
        );
        for (final status in RepairStatus.values.where(
          (status) => status != RepairStatus.pending,
        )) {
          expect(
            AdminRequestTransitionRules.allows(action, status),
            isFalse,
            reason:
                '${action.name} must be blocked for ${status.databaseValue}',
          );
        }
      }
    });
  });
}
