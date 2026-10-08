enum AppRole {
  admin('admin', 'Admin'),
  student('student', 'Sinh viên'),
  technician('technician', 'Kỹ thuật viên');

  const AppRole(this.databaseValue, this.label);
  final String databaseValue;
  final String label;
}
