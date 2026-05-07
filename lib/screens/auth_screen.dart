import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// AUTH GATE — listens to Supabase auth state, routes to AuthScreen or app
// ════════════════════════════════════════════════════════════════════════════

/// Set to true to skip login and enter as guest
final guestMode = ValueNotifier<bool>(false);

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: guestMode,
      builder: (context, isGuest, _) {
        if (isGuest) return child; // guest → go straight to app

        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _SplashScreen();
            }
            final session = Supabase.instance.client.auth.currentSession;
            if (session != null) return child;
            return const AuthScreen();
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// AUTH SCREEN — Google Sign-In
// ════════════════════════════════════════════════════════════════════════════
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.booklymy://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      // Auth state stream in AuthGate handles navigation automatically
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // ── Logo / Branding ─────────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text('B', style: TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  )),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Bookly MY',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Malaysia Business Accounting',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w400,
                ),
              ),

              const Spacer(flex: 2),

              // ── Feature highlights ──────────────────────────────────────
              _FeatureRow(icon: '📊', text: 'Income & expense tracking with SST'),
              const SizedBox(height: 10),
              _FeatureRow(icon: '🧾', text: 'Invoice & payroll generation'),
              const SizedBox(height: 10),
              _FeatureRow(icon: '☁️', text: 'Cloud sync across devices'),

              const Spacer(flex: 3),

              // ── Error banner ────────────────────────────────────────────
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEB),
                    border: Border.all(color: const Color(0xFFFFCCCC)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 13, color: Color(0xFFCC0000)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              // ── Google Sign-In button ───────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1A1A1A),
                    elevation: 1,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF888888)),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _GoogleLogo(),
                            const SizedBox(width: 12),
                            const Text(
                              'Continue with Google',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 14),
              const Text(
                'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                style: TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // ── Skip / Guest mode ───────────────────────────────────────
              TextButton(
                onPressed: () => guestMode.value = true,
                child: const Text(
                  '暂时跳过，以访客身份使用',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF888888),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF888888),
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F5F5),
      body: Center(
        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String icon, text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF444444),
          fontWeight: FontWeight.w500,
        )),
      ],
    );
  }
}

/// Hand-drawn Google "G" logo in pure Flutter (no asset needed)
class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    // Background circle (white)
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.white);

    // Segments (simplified G logo via arcs)
    final segments = [
      (0.0,    90.0,  const Color(0xFF4285F4)),  // blue  top-right
      (90.0,   90.0,  const Color(0xFF34A853)),  // green bottom-right
      (180.0,  90.0,  const Color(0xFFFBBC05)),  // yellow bottom-left
      (270.0,  90.0,  const Color(0xFFEA4335)),  // red   top-left
    ];

    for (final seg in segments) {
      final paint = Paint()
        ..color = seg.$3
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.18;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.72),
        _deg(seg.$1),
        _deg(seg.$2),
        false,
        paint,
      );
    }

    // White horizontal bar for the G
    canvas.drawRect(
      Rect.fromLTRB(cx, cy - size.height * 0.09, cx + r * 0.72, cy + size.height * 0.09),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  double _deg(double d) => d * 3.14159265 / 180.0;

  @override
  bool shouldRepaint(_) => false;
}
