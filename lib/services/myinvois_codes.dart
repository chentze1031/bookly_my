// ════════════════════════════════════════════════════════════════════════════
// MyInvois reference code lists (Phase 4 #28 v2)
//
// Only the small, stable lists the app needs at the point of capture. The full
// classification list (~80 codes) is NOT embedded — the user sets a default
// classification code in Settings (see AppSettings.classCode).
// ════════════════════════════════════════════════════════════════════════════

class MyInvoisCodes {
  /// LHDN state codes (UBL `CountrySubentityCode`). Ordered for a dropdown.
  /// `17` = Not Applicable — the safe default for B2C / unknown.
  static const List<({String code, String name})> states = [
    (code: '17', name: 'Not Applicable'),
    (code: '01', name: 'Johor'),
    (code: '02', name: 'Kedah'),
    (code: '03', name: 'Kelantan'),
    (code: '04', name: 'Melaka'),
    (code: '05', name: 'Negeri Sembilan'),
    (code: '06', name: 'Pahang'),
    (code: '07', name: 'Pulau Pinang'),
    (code: '08', name: 'Perak'),
    (code: '09', name: 'Perlis'),
    (code: '10', name: 'Selangor'),
    (code: '11', name: 'Terengganu'),
    (code: '12', name: 'Sabah'),
    (code: '13', name: 'Sarawak'),
    (code: '14', name: 'WP Kuala Lumpur'),
    (code: '15', name: 'WP Labuan'),
    (code: '16', name: 'WP Putrajaya'),
  ];

  static String stateName(String code) {
    for (final s in states) {
      if (s.code == code) return s.name;
    }
    return 'Not Applicable';
  }
}
