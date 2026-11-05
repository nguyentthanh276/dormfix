import 'dart:convert';

import 'package:flutter/services.dart';

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
  });

  static Future<AppConfig> fromEnvironment() async {
    var supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    var supabasePublishableKey = const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    );

    if (supabaseUrl.trim().isEmpty || supabasePublishableKey.trim().isEmpty) {
      final configFiles = ['config/local.json', 'config/example.json'];

      for (final configFile in configFiles) {
        try {
          final source = await rootBundle.loadString(configFile);
          final decoded = jsonDecode(source);

          if (decoded is! Map) {
            continue;
          }

          final configMap = decoded.cast<String, dynamic>();
          supabaseUrl = (configMap['SUPABASE_URL'] ?? supabaseUrl).toString();
          supabasePublishableKey =
              (configMap['SUPABASE_PUBLISHABLE_KEY'] ?? supabasePublishableKey)
                  .toString();

          if (supabaseUrl.trim().isNotEmpty &&
              supabasePublishableKey.trim().isNotEmpty) {
            break;
          }
        } catch (_) {
          // Ignore missing or invalid config files and fall back to the next one.
        }
      }
    }

    return AppConfig(
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: supabasePublishableKey,
    );
  }

  final String supabaseUrl;
  final String supabasePublishableKey;

  bool get isConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        supabasePublishableKey.trim().isNotEmpty;
  }
}
