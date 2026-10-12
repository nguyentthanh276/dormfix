import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'demo_seed.dart';

abstract final class LocalDatabase {
  static const version = 1;
  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final engine = factory ?? databaseFactory;
    final location =
        path ?? p.join(await engine.getDatabasesPath(), 'dormfix.db');
    return engine.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          final sql = await rootBundle.loadString('assets/database/schema.sql');
          final parts = sql.split('CREATE TRIGGER');
          for (final statement in parts.first.split(';')) {
            if (statement.trim().isNotEmpty) await db.execute(statement);
          }
          for (final trigger in parts.skip(1)) {
            await db.execute('CREATE TRIGGER ${trigger.trim()}');
          }
          await DemoSeed.insert(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          throw StateError('Chưa có migration cho phiên bản database này.');
        },
      ),
    );
  }
}
