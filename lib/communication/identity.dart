import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import '../persistence/repository.dart';

class Identity {
  Identity(this.keyPem, this.certPem);
  final String keyPem, certPem;
  String get fingerprint => sha256
      .convert(
        base64Decode(certPem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')),
      )
      .toString();
  String get id => fingerprint;
  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..usePrivateKeyBytes(utf8.encode(keyPem))
    ..useCertificateChainBytes(utf8.encode(certPem));
  static Identity generate() {
    final keys = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keys.privateKey as RSAPrivateKey;
    final publicKey = keys.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'OmniLink local'},
      privateKey,
      publicKey,
    );
    return Identity(
      CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
      X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650),
    );
  }

  static Future<Identity> load(Repository repository) async {
    final stored = await repository.readSecret('identity');
    if (stored != null) {
      final j = jsonDecode(stored);
      return Identity(j['key'], j['cert']);
    }
    final identity = await Isolate.run(generate);
    await repository.writeSecret(
      'identity',
      jsonEncode({'key': identity.keyPem, 'cert': identity.certPem}),
    );
    return identity;
  }
}
