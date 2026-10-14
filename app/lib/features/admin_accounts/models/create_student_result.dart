/// Successful result returned after creating a student account.
class CreateStudentResult {
  const CreateStudentResult({required this.profileId});

  /// UUID of the newly created profile.
  final String profileId;
}
