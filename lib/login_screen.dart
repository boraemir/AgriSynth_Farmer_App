import 'package:flutter/material.dart';

import 'agrisynth_theme.dart';
import 'farmer_panel.dart';
import 'signup_screen.dart';
import 'supabase_service.dart';
import 'user_panel.dart';
import 'vet_panel.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen — AgriSynth Premium UI
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Auth Logic (unchanged) ────────────────────────────────────────────
  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      final authResponse = await SupabaseService()
          .client
          .auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 25));

      final authUser = authResponse.user;
      if (authUser == null) {
        throw Exception('Oturum bilgisi alınamadı. Lütfen tekrar deneyin.');
      }

      final userData = await SupabaseService()
          .client
          .from('users')
          .select(
            'id,username,email,ad,soyad,tc_kimlik,telefon,sehir,rol,created_at,avatar_url',
          )
          .eq('id', authUser.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 20));

      if (userData == null) {
        await SupabaseService().client.auth.signOut();
        throw Exception('Kullanıcı profil kaydı bulunamadı.');
      }

      if (!mounted) return;
      _goToPanel(Map<String, dynamic>.from(userData));
    } catch (e) {
      if (!mounted) return;
      showAgriSnackBar(context, _friendlyAuthError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToPanel(Map<String, dynamic> userData) {
    final role = (userData['rol'] ?? '').toString().toLowerCase().trim();

    if (role == 'doktor') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => VetPanel(userData: userData)),
      );
      return;
    }

    if (role == 'user') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => UserPanel(userData: userData)),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => FarmerPanel(userData: userData)),
    );
  }

  Future<void> _openSignup() async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const SignUpScreen(),
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      showAgriSnackBar(context, 'Kayıt oluşturuldu. Şimdi giriş yapabilirsin.');
    }
  }

  String _friendlyAuthError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('invalid login credentials')) return 'E-posta veya şifre hatalı.';
    if (raw.contains('email not confirmed')) return 'E-posta adresi henüz doğrulanmamış.';
    if (raw.contains('timeout')) return 'Bağlantı zaman aşımına uğradı. İnternetini kontrol et.';
    if (raw.contains('profile') || raw.contains('profil')) return 'Kullanıcı profil kaydı bulunamadı.';
    return 'Giriş yapılamadı: $error';
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.offWhite,
      body: AgriBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _LoginHeader(),
                        const SizedBox(height: 32),
                        _LoginCard(
                          formKey: _formKey,
                          emailController: _emailController,
                          passwordController: _passwordController,
                          isLoading: _isLoading,
                          obscurePassword: _obscurePassword,
                          onToggleObscure: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          onLogin: _login,
                          onOpenSignup: _openSignup,
                        ),
                        const SizedBox(height: 24),
                        const _FooterBadge(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LoginHeader
// ─────────────────────────────────────────────────────────────────────────────
class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AgriLogoHero(size: 84),
        const SizedBox(height: 22),
        const Text(
          'AgriSynth',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AgriColors.deepForest,
            fontSize: 36,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Akıllı Tarım Yönetim Platformu',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AgriColors.inkLight,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LoginCard
// ─────────────────────────────────────────────────────────────────────────────
class _LoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isLoading;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final VoidCallback onOpenSignup;

  const _LoginCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.isLoading,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onLogin,
    required this.onOpenSignup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AgriColors.cardWhite,
        borderRadius: BorderRadius.circular(AgriRadius.xxl),
        border: Border.all(color: AgriColors.borderGhost, width: 1.2),
        boxShadow: AgriShadow.card,
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card title
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AgriColors.paleMint,
                    borderRadius: BorderRadius.circular(AgriRadius.sm),
                  ),
                  child: const Icon(
                    Icons.eco_rounded,
                    color: AgriColors.canopy,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hoş Geldin',
                      style: TextStyle(
                        color: AgriColors.inkDark,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Hesabına giriş yap',
                      style: TextStyle(
                        color: AgriColors.inkLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Email field
            AgriInputField(
              controller: emailController,
              label: 'E-posta',
              hint: 'ornek@mail.com',
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'E-posta gerekli';
                if (!t.contains('@')) return 'Geçerli bir e-posta gir';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password field
            AgriInputField(
              controller: passwordController,
              label: 'Şifre',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              suffixIcon: IconButton(
                onPressed: onToggleObscure,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    key: ValueKey(obscurePassword),
                    color: AgriColors.inkLight,
                    size: 20,
                  ),
                ),
              ),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return 'Şifre gerekli';
                return null;
              },
            ),
            const SizedBox(height: 28),

            // Login button
            AgriPrimaryButton(
              onPressed: isLoading ? null : onLogin,
              isLoading: isLoading,
              label: 'Giriş Yap',
              icon: Icons.login_rounded,
            ),
            const SizedBox(height: 24),

            // Divider
            Row(
              children: [
                const Expanded(
                  child: Divider(color: AgriColors.borderGhost, thickness: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AgriColors.paleMint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'veya',
                      style: TextStyle(
                        color: AgriColors.canopy,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: Divider(color: AgriColors.borderGhost, thickness: 1),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Sign up row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Hesabın yok mu?',
                  style: TextStyle(
                    color: AgriColors.inkLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: isLoading ? null : onOpenSignup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AgriColors.paleMint,
                      borderRadius: BorderRadius.circular(AgriRadius.sm),
                    ),
                    child: const Text(
                      'Kayıt Ol →',
                      style: TextStyle(
                        color: AgriColors.canopy,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FooterBadge
// ─────────────────────────────────────────────────────────────────────────────
class _FooterBadge extends StatelessWidget {
  const _FooterBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: AgriColors.leaf,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'AgriSynth v1.0 · Güvenli & Şifreli',
          style: TextStyle(
            color: AgriColors.inkLight,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}