import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'cert_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// MyInvoisSigner — UBL 2.1 JSON document signature (XAdES, document version 1.1)
//
// Implements LHDN's JSON signing procedure
// (https://sdk.myinvois.hasil.gov.my/signature-creation-json/). Confirmed
// against LHDN's spec and a working reference implementation
// (github.com/osikh/myinvois-json-signature):
//
//   • DocDigest  = base64( SHA256( minified document, BEFORE extensions ) )
//   • Sig        = base64( RSA-PKCS1v15-SHA256( same minified document ) )
//                  ── note: the JSON variant signs the DOCUMENT directly, NOT
//                     the SignedInfo element (this differs from classic XMLDSig)
//   • CertDigest = base64( SHA256( raw certificate DER bytes ) )
//   • PropsDigest= base64( SHA256( minified {"Target":...,"SignedProperties":[…]} ) )
//
// "minified" = compact JSON with no whitespace, which is exactly what Dart's
// jsonEncode emits. The embedded SignedProperties is the SAME map object that
// was hashed, so the bytes are guaranteed identical.
//
// ⚠️ SANDBOX-TUNABLE: LHDN re-extracts the document (excluding UBLExtensions and
// Signature by key name), re-minifies and re-verifies. The one thing to confirm
// in the sandbox is NUMERIC canonicalisation — if LHDN reports "signature
// invalid" while the structure is accepted, the fix is almost always to emit
// amounts/percentages as strings in the UBL builder so the round-trip is
// byte-stable. The signing math here is correct and does not change.
// ════════════════════════════════════════════════════════════════════════════

class MyInvoisSigner {
  // ── Literal constants (verbatim from the LHDN spec) ────────────────────────
  static const _extUri = 'urn:oasis:names:specification:ubl:dsig:enveloped:xades';
  static const _sigMethod = 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256';
  static const _digestMethod = 'http://www.w3.org/2001/04/xmlenc#sha256';
  static const _sigInfoId = 'urn:oasis:names:specification:ubl:signature:1';
  static const _refSigId = 'urn:oasis:names:specification:ubl:signature:Invoice';
  static const _propsType = 'http://uri.etsi.org/01903/v1.3.2#SignedProperties';
  static const _propsUri = '#id-xades-signed-props';
  static const _propsId = 'id-xades-signed-props';
  // PKCS#1 v1.5 DigestInfo OID prefix for SHA-256 (pointycastle convention).
  static const _sha256DigestId = '0609608648016503040201';

  static List<Map<String, dynamic>> _v(Object? x) => [
        {'_': x}
      ];
  static List<Map<String, dynamic>> _vAlg(String algorithm) => [
        {'_': '', 'Algorithm': algorithm}
      ];

  /// Returns a NEW document map identical to [doc] but with the XAdES signature
  /// embedded under `Invoice[0].UBLExtensions` and a `Invoice[0].Signature`
  /// reference. [doc] MUST be the unsigned document (no UBLExtensions/Signature)
  /// — exactly what [MyInvoisUbl.buildInvoice] produces.
  static Map<String, dynamic> sign(Map<String, dynamic> doc, CertBundle cert) {
    // 1) Digest + sign the document as-is, BEFORE inserting any extensions.
    final docBytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
    final docDigest = base64.encode(crypto.sha256.convert(docBytes).bytes);
    final sig = _rsaSha256(docBytes, cert.privateKey);
    final certDigest = base64.encode(crypto.sha256.convert(cert.certDer).bytes);

    // 2) SignedProperties wrapper. This EXACT object is both hashed (PropsDigest)
    //    and embedded into QualifyingProperties → identical bytes guaranteed.
    final signedProps = <String, dynamic>{
      'Target': 'signature',
      'SignedProperties': [
        {
          'Id': _propsId,
          'SignedSignatureProperties': [
            {
              'SigningTime': _v(_utc(DateTime.now().toUtc())),
              'SigningCertificate': [
                {
                  'Cert': [
                    {
                      'CertDigest': [
                        {
                          'DigestMethod': _vAlg(_digestMethod),
                          'DigestValue': _v(certDigest),
                        }
                      ],
                      'IssuerSerial': [
                        {
                          'X509IssuerName': _v(cert.issuerName),
                          'X509SerialNumber': _v(cert.serialNumber),
                        }
                      ],
                    }
                  ],
                }
              ],
            }
          ],
        }
      ],
    };
    final propsDigest = base64.encode(
        crypto.sha256.convert(utf8.encode(jsonEncode(signedProps))).bytes);

    // 3) The ds:Signature object.
    final signature = <String, dynamic>{
      'Id': 'signature',
      'SignedInfo': [
        {
          'SignatureMethod': _vAlg(_sigMethod),
          'Reference': [
            {
              'Type': _propsType,
              'URI': _propsUri,
              'DigestMethod': _vAlg(_digestMethod),
              'DigestValue': _v(propsDigest),
            },
            {
              'Type': '',
              'URI': '',
              'DigestMethod': _vAlg(_digestMethod),
              'DigestValue': _v(docDigest),
            },
          ],
        }
      ],
      'SignatureValue': _v(sig),
      'KeyInfo': [
        {
          'X509Data': [
            {
              'X509Certificate': _v(cert.certBase64),
              'X509SubjectName': _v(cert.subjectName),
              'X509IssuerSerial': [
                {
                  'X509IssuerName': _v(cert.issuerName),
                  'X509SerialNumber': _v(cert.serialNumber),
                }
              ],
            }
          ],
        }
      ],
      'Object': [
        {
          'QualifyingProperties': [signedProps],
        }
      ],
    };

    // 4) UBLExtensions envelope around the signature.
    final ublExtensions = [
      {
        'UBLExtension': [
          {
            'ExtensionURI': _v(_extUri),
            'ExtensionContent': [
              {
                'UBLDocumentSignatures': [
                  {
                    'SignatureInformation': [
                      {
                        'ID': _v(_sigInfoId),
                        'ReferencedSignatureID': _v(_refSigId),
                        'Signature': [signature],
                      }
                    ],
                  }
                ],
              }
            ],
          }
        ],
      }
    ];

    // 5) Insert into the invoice. Removing UBLExtensions + Signature by name
    //    reproduces the originally-signed bytes (original key order preserved).
    final invoice = (doc['Invoice'] as List).first as Map<String, dynamic>;
    final signedInvoice = <String, dynamic>{
      'UBLExtensions': ublExtensions,
      ...invoice,
      'Signature': [
        {
          'ID': _v(_refSigId),
          'SignatureMethod': _v(_extUri),
        }
      ],
    };

    final out = Map<String, dynamic>.from(doc);
    out['Invoice'] = [signedInvoice];
    return out;
  }

  static String _rsaSha256(Uint8List data, RSAPrivateKey key) {
    final signer = RSASigner(SHA256Digest(), _sha256DigestId);
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    final RSASignature s = signer.generateSignature(data);
    return base64.encode(s.bytes);
  }

  // UTC timestamp without milliseconds, e.g. 2024-07-23T15:14:54Z.
  static String _utc(DateTime t) =>
      '${_p(t.year, 4)}-${_p(t.month)}-${_p(t.day)}'
      'T${_p(t.hour)}:${_p(t.minute)}:${_p(t.second)}Z';
  static String _p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
}
