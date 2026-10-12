import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/dormfix_app.dart';
import 'core/config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  var backendReady = false;
  if (config.isConfigured) {
    try {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
      backendReady = true;
    } catch (_) {
      // Keep the shell usable when initialization fails. Never log credentials.
    }
  }
  runApp(DormFixApp(backendReady: backendReady));
}
