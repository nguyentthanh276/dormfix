import 'package:sqflite/sqflite.dart';

abstract final class DemoSeed {
  static Future<void> insert(DatabaseExecutor db) async {
    await db.insert('rooms', {
      'id': 'demo-room',
      'code': 'DEMO-A101',
      'building': 'Tòa demo',
    });
    for (final name in ['Điện', 'Nước', 'Nội thất', 'Khác']) {
      await db.insert('incident_categories', {
        'id': 'category-$name',
        'name': name,
      });
    }
    for (final row in accounts) {
      await db.insert('profiles', row);
    }
  }

  // Demo password digests only; each account has a distinct salt.
  static const List<Map<String, Object?>> accounts = [
    {
      "id": "demo-admin",
      "identity_code": "ADMIN001",
      "full_name": "Admin Demo",
      "email": "admin@example.com",
      "phone": null,
      "role": "admin",
      "status": "active",
      "room_id": null,
      "must_change_password": 0,
      "password_hash": "YDSqysm+MKk4Y/9vgS+gj991FmFKVXQLEY8Bf7nxlgA=",
      "password_salt": "GdfhcU3T0yrkfs62uSWcnw==",
      "password_iterations": 120000,
    },
    {
      "id": "demo-student",
      "identity_code": "SV001",
      "full_name": "Sinh viên Demo",
      "email": "student@example.com",
      "phone": "0000000001",
      "role": "student",
      "status": "active",
      "room_id": "demo-room",
      "must_change_password": 1,
      "password_hash": "BjDrHFqoqzrlRzyG23TTDHaPSPuBYRLlOWC7gZf7/wg=",
      "password_salt": "ileLJGfd2veIpKN+1dPq1g==",
      "password_iterations": 120000,
    },
    {
      "id": "demo-technician",
      "identity_code": "KTV001",
      "full_name": "Kỹ thuật viên Demo",
      "email": "technican@example.com",
      "phone": "0000000002",
      "role": "technician",
      "status": "active",
      "room_id": null,
      "must_change_password": 1,
      "password_hash": "6VrNTqMxWrcDPsMjuQOIy72z9wB866P+cQZiQWtoat8=",
      "password_salt": "xsz9lCMwtvU7FzIfu9CXyw==",
      "password_iterations": 120000,
    },
  ];
}
