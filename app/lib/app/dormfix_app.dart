import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_service.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/password_page.dart';
import '../features/profile/presentation/profile_page.dart';

class DormFixApp extends StatelessWidget {
  const DormFixApp({super.key, required this.auth});
  final AuthService auth;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) => MaterialApp(
      key: ValueKey(auth.current?.id),
      title: 'DormFix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: auth.current == null
          ? LoginPage(auth: auth)
          : auth.current!.mustChangePassword
          ? PasswordPage(auth: auth, mandatory: true)
          : ProfilePage(auth: auth),
    ),
  );
}
