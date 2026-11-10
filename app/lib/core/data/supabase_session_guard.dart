import 'package:supabase_flutter/supabase_flutter.dart';

/// Binds a request to the session that started it and discards stale responses.
class SupabaseSessionGuard {
  const SupabaseSessionGuard(this._client);

  final SupabaseClient _client;

  Future<T> run<T>(
    Future<T> Function(String accessToken) operation, {
    required Exception denied,
  }) async {
    final session = _validSession;
    if (session == null) throw denied;
    final owner = session.user.id;
    var changed = false;
    final auth = _client.auth.onAuthStateChange.listen((state) {
      if (state.session?.user.id != owner) changed = true;
    }, onError: (Object _) => changed = true);

    try {
      return await operation(session.accessToken);
    } finally {
      await auth.cancel();
      if (changed || _validSession?.user.id != owner) throw denied;
    }
  }

  Session? get _validSession {
    final session = _client.auth.currentSession;
    if (session == null ||
        session.isExpired ||
        session.accessToken.isEmpty ||
        session.user.id.isEmpty) {
      return null;
    }
    return session;
  }
}
