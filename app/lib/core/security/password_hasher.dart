import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PasswordDigest {
  const PasswordDigest(this.hash, this.salt, this.iterations);
  final String hash;
  final String salt;
  final int iterations;
}

class PasswordHasher {
  static const iterations = 120000;
  Future<PasswordDigest> hash(String password) async {
    final random = Random.secure();
    final salt = base64Encode(List.generate(16, (_) => random.nextInt(256)));
    return PasswordDigest(
      await _derive(password, salt, iterations),
      salt,
      iterations,
    );
  }

  Future<bool> verify(
    String password,
    String hash,
    String salt,
    int iterations,
  ) async {
    final actual = base64Decode(await _derive(password, salt, iterations));
    final expected = base64Decode(hash);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }

  Future<String> _derive(String password, String salt, int rounds) async {
    final key =
        await Pbkdf2(
          macAlgorithm: Hmac.sha256(),
          iterations: rounds,
          bits: 256,
        ).deriveKey(
          secretKey: SecretKey(utf8.encode(password)),
          nonce: base64Decode(salt),
        );
    return base64Encode(await key.extractBytes());
  }

  static String? validate(String password) {
    if (password.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password)) {
      return 'Mật khẩu cần ít nhất 8 ký tự, có chữ hoa, chữ thường và số.';
    }
    return null;
  }
}
