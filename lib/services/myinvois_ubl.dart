import '../models.dart';

// ════════════════════════════════════════════════════════════════════════════
// MyInvois UBL 2.1 JSON builder (Phase 4 #28)
//
// Maps a Bookly invoice record → the LHDN MyInvois e-Invoice document (JSON
// variant of UBL 2.1, document version 1.0 = UNSIGNED). The structure uses the
// `_D/_A/_B` namespace keys and the `[{ "_": value }]` value-wrapper convention
// required by MyInvois.
//
// ⚠️ This is a best-effort v1.0 mapping. The EXACT mandatory field set + code
// lists (classification, state, tax-type) must be validated against the
// MyInvois sandbox — validation errors there pinpoint any field to adjust.
// Codes marked TODO are placeholders/defaults.
// ════════════════════════════════════════════════════════════════════════════

class MyInvoisUbl {
  // SST rate per line key (mirrors invoice_pdf.dart).
  static const _sstRate = {'none': 0.0, 'sst5': 0.05, 'sst10': 0.10};
  // LHDN tax type codes: 01 = Sales Tax, 02 = Service Tax, 06 = Not Applicable.
  static String _taxType(String key) => key == 'none' ? '06' : '01';
  // General-public TIN for buyers without their own TIN (B2C).
  static const generalPublicTin = 'EI00000000010';
  // General TIN for foreign suppliers/buyers (self-billed to non-residents).
  static const generalForeignTin = 'EI00000000020';
  // Fallback classification when none configured ("022" = Others on CLASS list).
  static const _fallbackClassification = '022';

  static List<Map<String, dynamic>> _v(Object? value) => [
        {'_': value}
      ];
  static List<Map<String, dynamic>> _vA(Object? value, Map<String, dynamic> attrs) => [
        {'_': value, ...attrs}
      ];

  /// Build the UBL document for [inv] (an invoice record as stored by AppState),
  /// the supplier [s] and the [buyer]. Returns the JSON map to Base64-encode.
  ///
  /// [signed] selects the document version: `1.1` (digitally signed, required
  /// for production) when true, `1.0` (unsigned, sandbox only) when false. The
  /// version is part of the signed payload, so it must be set before signing.
  /// [consolidated] builds a B2C consolidated e-Invoice: the buyer becomes the
  /// general public (TIN EI00000000010) and every line uses classification 004.
  /// [invoiceTypeCode] is the LHDN document type ('01' invoice, '11' self-billed).
  static Map<String, dynamic> buildInvoice({
    required Map<String, dynamic> inv,
    required AppSettings s,
    required Customer buyer,
    bool signed = false,
    bool consolidated = false,
    String invoiceTypeCode = '01',
    Customer? selfBilledSupplier,
    String selfBilledMsic = '',
    String selfBilledMsicDesc = '',
  }) {
    // Self-billed (type 11): you issue on the supplier's behalf, so the roles
    // swap — the counterparty is the supplier and your company is the buyer.
    final selfBilled = selfBilledSupplier != null;
    final typeCode = selfBilled ? '11' : invoiceTypeCode;
    final version = signed ? '1.1' : '1.0';
    final classCode = consolidated
        ? '004' // "Consolidated e-Invoice" on the CLASS list
        : (s.classCode.trim().isEmpty ? _fallbackClassification : s.classCode.trim());
    // General public (name "General Public", TIN EI00000000010, reg NA, state 17)
    // is ONLY valid for a consolidated e-Invoice (classification 004). LHDN
    // rejects it on a normal invoice (CV317/ERR236), so a normal invoice must
    // carry a real, identified buyer — B2C without buyer details goes through
    // the consolidated flow instead.
    final generalPublic = consolidated;
    final effBuyer = generalPublic
        ? const Customer(id: 0, name: 'General Public', regNo: 'NA')
        : buyer;
    final rows = (inv['items'] as List).cast<Map<String, dynamic>>();
    double netOf(Map r) =>
        (double.tryParse('${r['qty'] ?? '1'}') ?? 1) * (double.tryParse('${r['price'] ?? '0'}') ?? 0);
    double sstOf(Map r) => netOf(r) * (_sstRate[r['sst'] ?? 'none'] ?? 0);

    final subtotal = rows.fold<double>(0, (a, r) => a + netOf(r));
    final totalSst = rows.fold<double>(0, (a, r) => a + sstOf(r));
    final grand = subtotal + totalSst;

    final now = DateTime.now().toUtc();
    final issueDate = (inv['invDate'] as String?)?.isNotEmpty == true
        ? inv['invDate'] as String
        : now.toIso8601String().substring(0, 10);
    final issueTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}Z';

    final buyerTin = generalPublic ? generalPublicTin : effBuyer.tin.trim();

    return {
      '_D': 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2',
      '_A': 'urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2',
      '_B': 'urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2',
      'Invoice': [
        {
          'ID': _v(inv['invNo'] ?? ''),
          'IssueDate': _v(issueDate),
          'IssueTime': _v(issueTime),
          'InvoiceTypeCode': _vA(typeCode, {'listVersionID': version}),
          'DocumentCurrencyCode': _v('MYR'),
          'TaxCurrencyCode': _v('MYR'),
          'AccountingSupplierParty': [
            {
              'Party': [selfBilled ? _customerAsSupplier(selfBilledSupplier, selfBilledMsic, selfBilledMsicDesc) : _supplierParty(s)]
            }
          ],
          'AccountingCustomerParty': [
            {
              'Party': [selfBilled ? _companyAsBuyer(s) : _buyerParty(effBuyer, buyerTin)]
            }
          ],
          'InvoiceLine': [
            for (var i = 0; i < rows.length; i++)
              _line(i + 1, rows[i], netOf(rows[i]), sstOf(rows[i]), classCode),
          ],
          'TaxTotal': [
            {
              'TaxAmount': _vA(_money(totalSst), {'currencyID': 'MYR'}),
              'TaxSubtotal': _taxSubtotals(rows, netOf, sstOf),
            }
          ],
          'LegalMonetaryTotal': [
            {
              'LineExtensionAmount': _vA(_money(subtotal), {'currencyID': 'MYR'}),
              'TaxExclusiveAmount': _vA(_money(subtotal), {'currencyID': 'MYR'}),
              'TaxInclusiveAmount': _vA(_money(grand), {'currencyID': 'MYR'}),
              'PayableAmount': _vA(_money(grand), {'currencyID': 'MYR'}),
            }
          ],
        }
      ],
    };
  }

  // Unified party builder — same structure for supplier and buyer. MSIC
  // (IndustryClassificationCode) is supplier-only, so it's optional.
  static Map<String, dynamic> _party({
    required String name,
    required String tin,
    required String brn,
    required String sst,
    required String addr,
    required String city,
    required String postcode,
    required String state,
    required String phone,
    required String email,
    String msicCode = '',
    String msicDesc = '',
    String regScheme = 'BRN', // BRN | NRIC | PASSPORT | ARMY
  }) =>
      {
        if (msicCode.isNotEmpty)
          'IndustryClassificationCode': _vA(msicCode, {'name': msicDesc}),
        'PartyIdentification': [
          {'ID': _vA(tin, {'schemeID': 'TIN'})},
          {'ID': _vA(brn.isEmpty ? 'NA' : brn, {'schemeID': regScheme})},
          {'ID': _vA(sst.isEmpty ? 'NA' : sst, {'schemeID': 'SST'})},
        ],
        'PostalAddress': [_address(addr, city, postcode, state)],
        'PartyLegalEntity': [
          {'RegistrationName': _v(name)}
        ],
        'Contact': [
          {
            'Telephone': _v(phone.isEmpty ? 'NA' : phone),
            if (email.isNotEmpty) 'ElectronicMail': _v(email),
          }
        ],
      };

  static Map<String, dynamic> _supplierParty(AppSettings s) => _party(
        name: s.companyName, tin: s.coTin, brn: s.coReg, sst: s.sstRegNo,
        addr: s.coAddr, city: s.coCity, postcode: s.coPostcode, state: s.coState,
        phone: s.coPhone, email: s.coEmail,
        msicCode: s.msicCode, msicDesc: s.msicDesc,
        regScheme: s.regType,
      );

  // Your own company as the BUYER (self-billed): same fields, no MSIC.
  static Map<String, dynamic> _companyAsBuyer(AppSettings s) => _party(
        name: s.companyName, tin: s.coTin, brn: s.coReg, sst: s.sstRegNo,
        addr: s.coAddr, city: s.coCity, postcode: s.coPostcode, state: s.coState,
        phone: s.coPhone, email: s.coEmail,
        regScheme: s.regType,
      );

  static Map<String, dynamic> _buyerParty(Customer b, String tin) => _party(
        name: b.name, tin: tin, brn: b.regNo, sst: b.sstRegNo,
        addr: b.address, city: b.city, postcode: b.postcode, state: b.state,
        phone: b.phone, email: b.email,
      );

  // The counterparty as the SUPPLIER (self-billed). LHDN requires a valid MSIC
  // (CF360) + phone (CF414); these are supplied (falling back to the company's).
  static Map<String, dynamic> _customerAsSupplier(Customer c,
          [String msicCode = '', String msicDesc = '']) => _party(
        name: c.name,
        tin: c.tin.trim().isEmpty ? generalForeignTin : c.tin.trim(),
        brn: c.regNo, sst: c.sstRegNo,
        addr: c.address, city: c.city, postcode: c.postcode, state: c.state,
        phone: c.phone, email: c.email,
        msicCode: msicCode, msicDesc: msicDesc,
      );

  // Structured MyInvois address: line + city + postcode + LHDN state code.
  // Country fixed to MYS (this build targets Malaysian taxpayers).
  static Map<String, dynamic> _address(
          String addr, String city, String postcode, String state) =>
      {
        'CityName': _v(city.isEmpty ? 'NA' : city),
        'PostalZone': _v(postcode.isEmpty ? 'NA' : postcode),
        'CountrySubentityCode': _v(state.isEmpty ? '17' : state),
        'AddressLine': [
          {
            'Line': _v(addr.isEmpty ? 'NA' : addr)
          }
        ],
        'Country': [
          {
            'IdentificationCode': _vA('MYS', {
              'listID': 'ISO3166-1',
              'listAgencyID': '6',
            })
          }
        ],
      };

  static Map<String, dynamic> _line(
      int n, Map<String, dynamic> r, double net, double sst, String classCode) {
    final key = (r['sst'] ?? 'none') as String;
    final pct = (_sstRate[key] ?? 0) * 100;
    final qty = double.tryParse('${r['qty'] ?? '1'}') ?? 1;
    final price = double.tryParse('${r['price'] ?? '0'}') ?? 0;
    return {
      'ID': _v('$n'),
      'InvoicedQuantity': _vA(qty, {'unitCode': 'C62'}), // C62 = unit/each
      'LineExtensionAmount': _vA(_money(net), {'currencyID': 'MYR'}),
      'TaxTotal': [
        {
          'TaxAmount': _vA(_money(sst), {'currencyID': 'MYR'}),
          'TaxSubtotal': [
            {
              'TaxableAmount': _vA(_money(net), {'currencyID': 'MYR'}),
              'TaxAmount': _vA(_money(sst), {'currencyID': 'MYR'}),
              'TaxCategory': [
                {
                  'ID': _v(_taxType(key)),
                  'Percent': _v(pct),
                  'TaxScheme': [
                    {
                      'ID': _vA('OTH', {'schemeID': 'UN/ECE 5153', 'schemeAgencyID': '6'})
                    }
                  ],
                }
              ],
            }
          ],
        }
      ],
      'Item': [
        {
          'CommodityClassification': [
            {
              'ItemClassificationCode': _vA(classCode, {'listID': 'CLASS'})
            }
          ],
          'Description': _v(r['desc'] ?? ''),
        }
      ],
      'Price': [
        {
          'PriceAmount': _vA(_money(price), {'currencyID': 'MYR'})
        }
      ],
      'ItemPriceExtension': [
        {
          'Amount': _vA(_money(net), {'currencyID': 'MYR'})
        }
      ],
    };
  }

  static List<Map<String, dynamic>> _taxSubtotals(
      List<Map<String, dynamic>> rows, double Function(Map) netOf, double Function(Map) sstOf) {
    // Group by SST key.
    final byKey = <String, ({double net, double tax, double pct})>{};
    for (final r in rows) {
      final key = (r['sst'] ?? 'none') as String;
      final prev = byKey[key] ?? (net: 0, tax: 0, pct: (_sstRate[key] ?? 0) * 100);
      byKey[key] = (net: prev.net + netOf(r), tax: prev.tax + sstOf(r), pct: prev.pct);
    }
    return [
      for (final e in byKey.entries)
        {
          'TaxableAmount': _vA(_money(e.value.net), {'currencyID': 'MYR'}),
          'TaxAmount': _vA(_money(e.value.tax), {'currencyID': 'MYR'}),
          'TaxCategory': [
            {
              'ID': _v(_taxType(e.key)),
              'Percent': _v(e.value.pct),
              'TaxScheme': [
                {
                  'ID': _vA('OTH', {'schemeID': 'UN/ECE 5153', 'schemeAgencyID': '6'})
                }
              ],
            }
          ],
        }
    ];
  }

  static double _money(double v) => double.parse(v.toStringAsFixed(2));
}
