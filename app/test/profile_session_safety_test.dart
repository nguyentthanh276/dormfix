import 'dart:async';

import 'package:dormfix/features/auth/models/user_profile.dart';
import 'package:dormfix/features/auth/presentation/auth_controller.dart';
import 'package:dormfix/features/profile/data/profile_repository.dart';
import 'package:dormfix/features/profile/presentation/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/technician_jobs_fakes.dart';

class _PendingProfileRepository implements ProfileRepository {
  final response = Completer<UserProfile>();

  @override
  Future<UserProfile> getProfile() => response.future;
  @override
  Future<UserProfile> updatePhone({required String phone}) => response.future;
}

void main() {
  test('disposed retained profile ignores an outstanding refresh', () async {
    final auth = TechnicianTestAuthRepository();
    final controller = AuthController(repository: auth);
    await controller.restoreSession();
    final repository = _PendingProfileRepository();
    final profile = ProfileController(
      authController: controller,
      repository: repository,
    );
    final pending = profile.loadProfile();
    profile.dispose();
    repository.response.complete(auth.profile.copyWith(phone: '0909999999'));
    await pending;
    expect(controller.profile?.phone, '0901111111');
    controller.dispose();
    await auth.dispose();
  });

  for (final lateFailure in [false, true]) {
    test(
      'old profile ${lateFailure ? 'failure' : 'save'} cannot affect a newly signed-in user',
      () async {
        final auth = TechnicianTestAuthRepository();
        final controller = AuthController(repository: auth);
        await controller.restoreSession();
        final repository = _PendingProfileRepository();
        final profile = ProfileController(
          authController: controller,
          repository: repository,
        );
        final pending = profile.updatePhone('0909999999');
        final old = auth.profile;
        await controller.signOut();
        auth.profile = technicianProfile(id: 'technician-2');
        await controller.signIn(
          email: 'second@example.com',
          password: 'unused-test-password',
        );
        expect(controller.profile?.id, 'technician-2');
        if (lateFailure) {
          repository.response.completeError(
            const ProfileFailure('Old session expired', signOutRequired: true),
          );
        } else {
          repository.response.complete(old.copyWith(phone: '0909999999'));
        }
        expect(await pending, isFalse);
        expect(controller.state, AuthViewState.authenticated);
        expect(controller.profile?.id, 'technician-2');
        expect(controller.profile?.phone, '0901111111');
        profile.dispose();
        controller.dispose();
        await auth.dispose();
      },
    );
  }
}
