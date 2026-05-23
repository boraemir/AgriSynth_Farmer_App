import 'package:flutter/material.dart';

import 'agrisynth_theme.dart';
import 'supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SignUpScreen — AgriSynth Premium UI
// ─────────────────────────────────────────────────────────────────────────────
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _adController = TextEditingController();
  final TextEditingController _soyadController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordAgainController = TextEditingController();
  final TextEditingController _tcController = TextEditingController();
  final TextEditingController _telefonController = TextEditingController();
  final TextEditingController _sehirController = TextEditingController();

  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscurePasswordAgain = true;
  String _selectedRole = 'ciftci';

  static const List<_RoleOption> _roleOptions = [
    _RoleOption(
      label: 'Çiftçi',
      subtitle: 'Tarla & hayvan yönetimi',
      value: 'ciftci',
      icon: Icons.grass_rounded,
      accentColor: Color(0xFF1E7A4A),
      bgColor: Color(0xFFE2F5EA),
    ),
    _RoleOption(
      label: 'Veteriner',
      subtitle: 'Hayvan sağlığı & tedavi',
      value: 'doktor',
      icon: Icons.medical_services_rounded,
      accentColor: Color(0xFF2563EB),
      bgColor: Color(0xFFE8F0FE),
    ),
    _RoleOption(
      label: 'Kullanıcı',
      subtitle: 'Genel erişim',
      value: 'user',
      icon: Icons.person_outline_rounded,
      accentColor: Color(0xFF6B4F9E),
      bgColor: Color(0xFFF0EBFF),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _adController.dispose();
    _soyadController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordAgainController.dispose();
    _tcController.dispose();
    _telefonController.dispose();
    _sehirController.dispose();
    super.dispose();
  }

  // ── Auth Logic (unchanged) ────────────────────────────────────────────
  Future<void> _signUp() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final username = _usernameController.text.trim();
      final ad = _adController.text.trim();
      final soyad = _soyadController.text.trim();

      final authResponse = await SupabaseService()
          .client
          .auth
          .signUp(
            email: email,
            password: password,
            data: {
              'username': username,
              'ad': ad,
              'soyad': soyad,
              'rol': _selectedRole,
            },
          )
          .timeout(const Duration(seconds: 30));

      final authUser = authResponse.user;
      if (authUser == null) throw Exception('Auth kullanıcısı oluşturulamadı.');

      final userPayload = <String, dynamic>{
        'id': authUser.id,
        'username': username,
        'email': email,
        'ad': ad,
        'soyad': soyad,
        'tc_kimlik': _emptyToNull(_tcController.text),
        'telefon': _emptyToNull(_telefonController.text),
        'sehir': _emptyToNull(_sehirController.text),
        'rol': _selectedRole,
        'sifre': null,
      };

      await SupabaseService()
          .client
          .from('users')
          .upsert(userPayload, onConflict: 'id')
          .timeout(const Duration(seconds: 25));

      await SupabaseService().client.auth.signOut();

      if (!mounted) return;
      showAgriSnackBar(context, 'Kayıt başarılı! Giriş ekranına yönlendiriliyorsun.');
      await Future.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showAgriSnackBar(context, _friendlySignUpError(e), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _friendlySignUpError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('already registered') || raw.contains('user already')) {
      return 'Bu e-posta adresi zaten kayıtlı.';
    }
    if (raw.contains('users_username_key')) return 'Bu kullanıcı adı zaten kullanılıyor.';
    if (raw.contains('users_tc_kimlik_key')) return 'Bu TC kimlik numarası zaten kayıtlı.';
    if (raw.contains('duplicate key')) return 'Bu bilgilerle kayıt zaten mevcut.';
    if (raw.contains('users_rol_check')) return 'Rol değeri veritabanı ile uyumlu değil.';
    if (raw.contains('password')) return 'Şifre en az 6 karakter olmalı.';
    if (raw.contains('timeout')) return 'Bağlantı zaman aşımına uğradı. İnternetini kontrol et.';
    return 'Kayıt oluşturulamadı: $error';
  }

  String? _required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Bu alan gerekli';
    return null;
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgriColors.offWhite,
      body: AgriBackground(
        child: SafeArea(
          child: Column(
            children: [
              _SignUpAppBar(isLoading: _isLoading),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Section 1: Rol ───────────────────────
                              const AgriSectionLabel('KULLANICI TÜRÜ'),
                              const SizedBox(height: 12),
                              _RoleSelector(
                                options: _roleOptions,
                                selected: _selectedRole,
                                isLoading: _isLoading,
                                onChanged: (v) =>
                                    setState(() => _selectedRole = v),
                              ),
                              const SizedBox(height: 24),

                              // ── Section 2: Kişisel ───────────────────
                              _FormCard(
                                label: 'KİŞİSEL BİLGİLER',
                                icon: Icons.person_outline_rounded,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AgriInputField(
                                          controller: _adController,
                                          label: 'Ad',
                                          hint: 'Adın',
                                          icon: Icons.badge_outlined,
                                          validator: _required,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: AgriInputField(
                                          controller: _soyadController,
                                          label: 'Soyad',
                                          hint: 'Soyadın',
                                          icon: Icons.badge_outlined,
                                          validator: _required,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  AgriInputField(
                                    controller: _usernameController,
                                    label: 'Kullanıcı Adı',
                                    hint: '@kullaniciadi',
                                    icon: Icons.alternate_email_rounded,
                                    validator: _required,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // ── Section 3: Hesap ─────────────────────
                              _FormCard(
                                label: 'HESAP BİLGİLERİ',
                                icon: Icons.shield_outlined,
                                children: [
                                  AgriInputField(
                                    controller: _emailController,
                                    label: 'E-posta',
                                    hint: 'ornek@mail.com',
                                    icon: Icons.alternate_email_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) {
                                      final t = (v ?? '').trim();
                                      if (t.isEmpty) return 'E-posta gerekli';
                                      if (!t.contains('@')) {
                                        return 'Geçerli bir e-posta gir';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AgriInputField(
                                          controller: _passwordController,
                                          label: 'Şifre',
                                          hint: 'En az 6 karakter',
                                          icon: Icons.lock_outline_rounded,
                                          obscureText: _obscurePassword,
                                          suffixIcon: IconButton(
                                            onPressed: () => setState(() =>
                                                _obscurePassword =
                                                    !_obscurePassword),
                                            icon: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              child: Icon(
                                                _obscurePassword
                                                    ? Icons
                                                        .visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                                key: ValueKey(_obscurePassword),
                                                color: AgriColors.inkLight,
                                                size: 19,
                                              ),
                                            ),
                                          ),
                                          validator: (v) {
                                            final t = (v ?? '').trim();
                                            if (t.isEmpty) return 'Şifre gerekli';
                                            if (t.length < 6) {
                                              return 'En az 6 karakter';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: AgriInputField(
                                          controller: _passwordAgainController,
                                          label: 'Tekrar',
                                          hint: 'Şifreni tekrarla',
                                          icon: Icons.lock_reset_rounded,
                                          obscureText: _obscurePasswordAgain,
                                          suffixIcon: IconButton(
                                            onPressed: () => setState(() =>
                                                _obscurePasswordAgain =
                                                    !_obscurePasswordAgain),
                                            icon: AnimatedSwitcher(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              child: Icon(
                                                _obscurePasswordAgain
                                                    ? Icons
                                                        .visibility_off_outlined
                                                    : Icons.visibility_outlined,
                                                key: ValueKey(
                                                    _obscurePasswordAgain),
                                                color: AgriColors.inkLight,
                                                size: 19,
                                              ),
                                            ),
                                          ),
                                          validator: (v) {
                                            final t = (v ?? '').trim();
                                            if (t.isEmpty) return 'Tekrar gerekli';
                                            if (t !=
                                                _passwordController.text
                                                    .trim()) {
                                              return 'Şifreler eşleşmiyor';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // ── Section 4: İletişim (opsiyonel) ──────
                              _FormCard(
                                label: 'İLETİŞİM & KONUM',
                                icon: Icons.location_on_outlined,
                                isOptional: true,
                                children: [
                                  AgriInputField(
                                    controller: _tcController,
                                    label: 'TC Kimlik Numarası',
                                    hint: '11 haneli numara',
                                    icon: Icons.credit_card_outlined,
                                    keyboardType: TextInputType.number,
                                    validator: (v) {
                                      final t = (v ?? '').trim();
                                      if (t.isEmpty) return null;
                                      if (t.length != 11) {
                                        return '11 haneli olmalı';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AgriInputField(
                                          controller: _telefonController,
                                          label: 'Telefon',
                                          hint: '05xx xxx xx xx',
                                          icon: Icons.phone_outlined,
                                          keyboardType: TextInputType.phone,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: AgriInputField(
                                          controller: _sehirController,
                                          label: 'Şehir',
                                          hint: 'İstanbul',
                                          icon: Icons.location_city_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),

                              // ── Submit ───────────────────────────────
                              AgriPrimaryButton(
                                onPressed: _isLoading ? null : _signUp,
                                isLoading: _isLoading,
                                label: 'Hesabımı Oluştur',
                                icon: Icons.how_to_reg_rounded,
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AgriColors.canopy,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                  ),
                                  child: const Text(
                                    'Zaten hesabım var →',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SignUpAppBar
// ─────────────────────────────────────────────────────────────────────────────
class _SignUpAppBar extends StatelessWidget {
  final bool isLoading;
  const _SignUpAppBar({required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 4),
      child: Row(
        children: [
          // Back button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isLoading ? null : () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(AgriRadius.sm),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AgriColors.cardWhite,
                  borderRadius: BorderRadius.circular(AgriRadius.sm),
                  border:
                      Border.all(color: AgriColors.borderGhost, width: 1.2),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AgriColors.inkMid,
                  size: 17,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yeni Hesap Oluştur',
                  style: TextStyle(
                    color: AgriColors.inkDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  "AgriSynth'e katıl",
                  style: TextStyle(
                    color: AgriColors.inkLight,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Hero logo (small)
          const AgriLogoHero(size: 42),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoleSelector — Interactive glowing role cards
// ─────────────────────────────────────────────────────────────────────────────
class _RoleSelector extends StatelessWidget {
  final List<_RoleOption> options;
  final String selected;
  final bool isLoading;
  final ValueChanged<String> onChanged;

  const _RoleSelector({
    required this.options,
    required this.selected,
    required this.isLoading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((opt) {
        final isSelected = opt.value == selected;
        final isLast = opt.value == options.last.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 10),
            child: _RoleCard(
              option: opt,
              isSelected: isSelected,
              isLoading: isLoading,
              onTap: () => onChanged(opt.value),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RoleCard extends StatefulWidget {
  final _RoleOption option;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _RoleCard({
    required this.option,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    if (widget.isSelected) _pulseCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _RoleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!widget.isSelected && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opt = widget.option;
    final sel = widget.isSelected;

    return GestureDetector(
      onTap: widget.isLoading ? null : widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: sel ? opt.bgColor : AgriColors.cardWhite,
          borderRadius: BorderRadius.circular(AgriRadius.xl),
          border: Border.all(
            color: sel ? opt.accentColor : AgriColors.borderGhost,
            width: sel ? 2.0 : 1.2,
          ),
          boxShadow: sel
              ? [
                  BoxShadow(
                    color: opt.accentColor.withOpacity(0.20),
                    blurRadius: 18,
                    spreadRadius: 0,
                    offset: const Offset(0, 8),
                  ),
                ]
              : AgriShadow.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container with scale pulse when selected
            ScaleTransition(
              scale: sel ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: sel ? opt.accentColor : AgriColors.surface,
                  borderRadius: BorderRadius.circular(AgriRadius.md),
                ),
                child: Icon(
                  opt.icon,
                  color: sel ? Colors.white : AgriColors.inkLight,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Label
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: sel ? opt.accentColor : AgriColors.inkMid,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
              child: Text(opt.label, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: sel
                    ? opt.accentColor.withOpacity(0.7)
                    : AgriColors.inkLight,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              child: Text(
                opt.subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
            // Selected checkmark
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: sel
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: opt.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    )
                  : const SizedBox(height: 0, key: ValueKey('empty')),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FormCard — Grouped form section with label
// ─────────────────────────────────────────────────────────────────────────────
class _FormCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Widget> children;
  final bool isOptional;

  const _FormCard({
    required this.label,
    required this.icon,
    required this.children,
    this.isOptional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AgriColors.cardWhite,
        borderRadius: BorderRadius.circular(AgriRadius.xxl),
        border: Border.all(color: AgriColors.borderGhost, width: 1.2),
        boxShadow: AgriShadow.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            decoration: BoxDecoration(
              color: AgriColors.surface.withOpacity(0.6),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AgriRadius.xxl),
                topRight: Radius.circular(AgriRadius.xxl),
              ),
              border: const Border(
                bottom: BorderSide(color: AgriColors.borderGhost, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AgriColors.canopy, size: 17),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: AgriColors.inkMid,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                if (isOptional) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AgriColors.paleMint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'İsteğe bağlı',
                      style: TextStyle(
                        color: AgriColors.canopy,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Fields
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _RoleOption model
// ─────────────────────────────────────────────────────────────────────────────
class _RoleOption {
  final String label;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color accentColor;
  final Color bgColor;

  const _RoleOption({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.bgColor,
  });
}