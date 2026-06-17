import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart'; // re-exports pointycastle (RSAPrivateKey)
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants.dart';

// ════════════════════════════════════════════════════════════════════════════
// CertService — on-device MyInvois signing-certificate store (Phase 4 #28 v2)
//
// SECURITY MODEL (deliberate): the taxpayer's digital-signature PRIVATE KEY
// lives ONLY on this device, inside Android Keystore-backed encrypted storage
// (flutter_secure_storage). It is NEVER uploaded to Supabase, NEVER logged, and
// NEVER leaves the device. This satisfies LHDN's non-repudiation requirement
// (the signing key must be under the taxpayer's sole control) and means Bookly
// (the developer) holds zero private-key liability.
//
// Keys are company-scoped via coKey(): each company (= a distinct legal entity
// with its own TIN) gets its own certificate, isolated per active company.
// ════════════════════════════════════════════════════════════════════════════

/// Display-friendly certificate metadata (no secrets).
class CertInfo {
  final String subject;
  final String issuer;
  final String serial;
  final DateTime notBefore;
  final DateTime notAfter;
  const CertInfo({
    required this.subject,
    required this.issuer,
    required this.serial,
    required this.notBefore,
    required this.notAfter,
  });

  bool get expired => DateTime.now().isAfter(notAfter);
  bool get notYetValid => DateTime.now().isBefore(notBefore);
  int get daysLeft => notAfter.difference(DateTime.now()).inDays;
}

/// In-memory key material for one signing operation. Never persisted as-is and
/// never serialised — built fresh from secure storage each time signing runs.
class CertBundle {
  final RSAPrivateKey privateKey;
  final Uint8List certDer; // raw DER bytes — basis for CertDigest
  final String certBase64; // base64(DER) — goes into X509Certificate
  final String subjectName;
  final String issuerName;
  final String serialNumber;
  const CertBundle({
    required this.privateKey,
    required this.certDer,
    required this.certBase64,
    required this.subjectName,
    required this.issuerName,
    required this.serialNumber,
  });
}

class CertService {
  // Company-scoped secure-storage keys (default company uses the bare key).
  static String get _kKey => coKey('bly_mi_key'); // PEM private key
  static String get _kCert => coKey('bly_mi_cert'); // PEM certificate

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// True when the active company has a certificate stored.
  static Future<bool> hasCert() async =>
      (await _storage.read(key: _kKey)) != null &&
      (await _storage.read(key: _kCert)) != null;

  /// Import certificate material for the active company.
  ///
  /// Accepts a `.p12`/`.pfx` (PKCS#12, needs [password]) or a `.pem` file that
  /// contains BOTH the private key and the certificate. Validates by actually
  /// parsing the key + cert. Returns `null` on success, or a human-readable
  /// error string on failure.
  static Future<String?> importBytes(
    Uint8List bytes, {
    String? password,
    required String filename,
  }) async {
    try {
      String? keyPem;
      String? certPem;
      final lower = filename.toLowerCase();

      if (lower.endsWith('.p12') || lower.endsWith('.pfx')) {
        if (password == null || password.isEmpty) {
          return 'PKCS#12 (.p12/.pfx) needs its password';
        }
        final List<String> pems = Pkcs12Utils.parsePkcs12(bytes, password: password);
        for (final p in pems) {
          if (p.contains('PRIVATE KEY')) {
            keyPem ??= p;
          } else if (p.contains('BEGIN CERTIFICATE')) {
            certPem ??= p; // first cert = the signing (leaf) certificate
          }
        }
      } else {
        // Raw PEM bundle (key + cert in one file).
        final text = utf8.decode(bytes);
        keyPem = _extractPem(text, 'PRIVATE KEY');
        certPem = _extractPem(text, 'CERTIFICATE');
      }

      if (keyPem == null) return 'No private key found in the file';
      if (certPem == null) return 'No certificate found in the file';

      // Validate by parsing — throws if the material is malformed.
      CryptoUtils.rsaPrivateKeyFromPem(keyPem);
      X509Utils.x509CertificateFromPem(certPem);

      await _storage.write(key: _kKey, value: keyPem);
      await _storage.write(key: _kCert, value: certPem);
      return null;
    } catch (e) {
      // Most common failure: AES-encrypted .p12 (OpenSSL 3 default) which the
      // pure-Dart parser can't open. Steer the user to a PEM export.
      return 'Could not read certificate. If it is a .p12, export it to PEM '
          '(key + cert) and import that instead.\n($e)';
    }
  }

  /// Parsed metadata for display / expiry checks, or null if none stored.
  static Future<CertInfo?> info() async {
    final certPem = await _storage.read(key: _kCert);
    if (certPem == null) return null;
    try {
      final c = X509Utils.x509CertificateFromPem(certPem);
      final tbs = c.tbsCertificate;
      final subject = tbs?.subject ?? c.subject;
      final issuer = tbs?.issuer ?? c.issuer;
      final serial = tbs?.serialNumber ?? c.serialNumber;
      final validity = tbs?.validity ?? c.validity;
      return CertInfo(
        subject: _dn(subject),
        issuer: _dn(issuer),
        serial: serial.toString(),
        notBefore: validity.notBefore,
        notAfter: validity.notAfter,
      );
    } catch (_) {
      return null;
    }
  }

  /// Load full key material for signing, or null if no certificate is stored.
  static Future<CertBundle?> load() async {
    final keyPem = await _storage.read(key: _kKey);
    final certPem = await _storage.read(key: _kCert);
    if (keyPem == null || certPem == null) return null;

    final key = CryptoUtils.rsaPrivateKeyFromPem(keyPem);
    final c = X509Utils.x509CertificateFromPem(certPem);
    final der = _derFromPem(certPem);
    final tbs = c.tbsCertificate;
    return CertBundle(
      privateKey: key,
      certDer: der,
      certBase64: base64.encode(der),
      subjectName: _dn(tbs?.subject ?? c.subject),
      issuerName: _dn(tbs?.issuer ?? c.issuer),
      serialNumber: (tbs?.serialNumber ?? c.serialNumber).toString(),
    );
  }

  /// Remove the active company's certificate.
  static Future<void> clear() async {
    await _storage.delete(key: _kKey);
    await _storage.delete(key: _kCert);
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static String? _extractPem(String text, String marker) {
    final re = RegExp(
      '-----BEGIN [A-Z0-9 ]*$marker-----.*?-----END [A-Z0-9 ]*$marker-----',
      dotAll: true,
    );
    return re.firstMatch(text)?.group(0);
  }

  static Uint8List _derFromPem(String pem) {
    final b64 = pem
        .replaceAll(RegExp(r'-----BEGIN [^-]+-----'), '')
        .replaceAll(RegExp(r'-----END [^-]+-----'), '')
        .replaceAll(RegExp(r'\s'), '');
    return base64.decode(b64);
  }

  // Distinguished-name parts keyed by OID → short label, for X509IssuerName /
  // X509SubjectName. (basic_utils keys the subject/issuer map by OID string.)
  static const _oidName = {
    '2.5.4.3': 'CN',
    '2.5.4.6': 'C',
    '2.5.4.7': 'L',
    '2.5.4.8': 'ST',
    '2.5.4.10': 'O',
    '2.5.4.11': 'OU',
    '2.5.4.5': 'SERIALNUMBER',
    '1.2.840.113549.1.9.1': 'E',
  };

  static String _dn(Map<String, String?> m) {
    final parts = <String>[];
    m.forEach((k, v) {
      if (v == null || v.isEmpty) return;
      parts.add('${_oidName[k] ?? k}=$v');
    });
    return parts.join(', ');
  }
}
