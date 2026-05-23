import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'user_app_drawer.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileEditScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const UserProfileEditScreen({super.key, this.userData});

  @override
  State<UserProfileEditScreen> createState() => _UserProfileEditScreenState();
}

class _UserProfileEditScreenState extends State<UserProfileEditScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const String avatarBucket = 'avatars';

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();

  final _formKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final _adController = TextEditingController();
  final _soyadController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _tcController = TextEditingController();
  final _telefonController = TextEditingController();
  final _sehirController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _passwordSaving = false;
  bool _avatarUploading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _userId;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _adController.dispose();
    _soyadController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _tcController.dispose();
    _telefonController.dispose();
    _sehirController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);

    try {
      final widgetId = widget.userData?['id']?.toString();
      final authId = _supabase.auth.currentUser?.id;
      final currentUserId = (widgetId != null && widgetId.isNotEmpty) ? widgetId : authId;

      if (currentUserId == null || currentUserId.isEmpty) {
        throw Exception('Oturum bilgisi bulunamadı. Lütfen tekrar giriş yapın.');
      }

      _userId = currentUserId;

      final data = await _supabase
          .from('users')
          .select('id, username, email, ad, soyad, tc_kimlik, telefon, sehir, rol, created_at, avatar_url')
          .eq('id', currentUserId)
          .maybeSingle()
          .timeout(const Duration(seconds: 20));

      if (data == null) {
        throw Exception('Profil kaydı bulunamadı. users tablosunda kullanıcı satırı yok.');
      }

      _profile = Map<String, dynamic>.from(data);
      _fillControllers(_profile!);
    } on TimeoutException {
      _showSnack('Profil bilgileri alınırken zaman aşımı oluştu.', isError: true);
    } catch (e) {
      _showSnack('Profil bilgileri alınamadı: $e', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillControllers(Map<String, dynamic> data) {
    _adController.text = (data['ad'] ?? '').toString();
    _soyadController.text = (data['soyad'] ?? '').toString();
    _usernameController.text = (data['username'] ?? '').toString();
    _emailController.text = (data['email'] ?? '').toString();
    _tcController.text = (data['tc_kimlik'] ?? '').toString();
    _telefonController.text = (data['telefon'] ?? '').toString();
    _sehirController.text = (data['sehir'] ?? '').toString();
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      _showSnack('Kullanıcı kimliği bulunamadı.', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final updateData = <String, dynamic>{
        'ad': _adController.text.trim(),
        'soyad': _soyadController.text.trim(),
        'tc_kimlik': _emptyToNull(_tcController.text),
        'telefon': _emptyToNull(_telefonController.text),
        'sehir': _emptyToNull(_sehirController.text),
      };

      await _supabase
          .from('users')
          .update(updateData)
          .eq('id', userId)
          .timeout(const Duration(seconds: 20));

      setState(() {
        _profile = {
          ...?_profile,
          ...updateData,
        };
      });

      _showSnack('Profil bilgileri güncellendi.');
    } on TimeoutException {
      _showSnack('Güncelleme işlemi zaman aşımına uğradı.', isError: true);
    } catch (e) {
      _showSnack('Profil güncellenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _updatePassword() async {
    if (_passwordSaving) return;
    if (!_passwordFormKey.currentState!.validate()) return;

    final userId = _userId ?? _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _showSnack('Kullanıcı kimliği bulunamadı. Lütfen tekrar giriş yapın.', isError: true);
      return;
    }

    final newPassword = _newPasswordController.text.trim();

    setState(() => _passwordSaving = true);

    var databaseUpdated = false;
    var authUpdated = false;
    var authNeedsRelogin = false;
    var authAlreadySame = false;

    try {
      // Önce users.sifre alanını güncelliyoruz.
      // Böylece Supabase Auth oturumu eski/bozuk olsa bile veritabanındaki şifre alanı değişmeden işlem yarıda kalmaz.
      await _supabase
          .from('users')
          .update({'sifre': newPassword})
          .eq('id', userId)
          .timeout(const Duration(seconds: 20));

      databaseUpdated = true;

      // Sonra mümkünse Supabase Auth şifresini de güncelliyoruz.
      // Eğer session_id/JWT hatası gelirse kullanıcı çıkış yapıp tekrar giriş yaptığında Auth tarafı sağlıklı güncellenebilir.
      try {
        await _supabase.auth
            .updateUser(UserAttributes(password: newPassword))
            .timeout(const Duration(seconds: 20));
        authUpdated = true;
      } on AuthException catch (e) {
        final message = e.message.toLowerCase();

        if (message.contains('different from the old password') ||
            message.contains('different from old password') ||
            message.contains('same password')) {
          authAlreadySame = true;
        } else if (message.contains('session_id') ||
            message.contains('session from session_id') ||
            message.contains('session not found') ||
            message.contains('invalid session') ||
            message.contains('jwt')) {
          authNeedsRelogin = true;
        } else {
          rethrow;
        }
      }

      _newPasswordController.clear();
      _confirmPasswordController.clear();

      if (mounted) {
        setState(() {
          _profile = {
            ...?_profile,
            'sifre': newPassword,
          };
        });
      }

      if (authUpdated) {
        _showSnack('Şifre başarıyla güncellendi.');
      } else if (authAlreadySame) {
        _showSnack('Şifre zaten Auth tarafında aynıydı; veritabanı şifre alanı güncellendi.');
      } else if (authNeedsRelogin) {
        _showSnack(
          'Veritabanındaki şifre güncellendi. Auth oturumu eski olduğu için çıkış yapıp tekrar giriş yapman gerekebilir.',
        );
      } else if (databaseUpdated) {
        _showSnack('Veritabanındaki şifre alanı güncellendi.');
      }
    } on PostgrestException catch (e) {
      _showSnack('users.sifre güncellenemedi: ${e.message}', isError: true);
    } on AuthException catch (e) {
      _showSnack(e.message, isError: true);
    } on TimeoutException {
      _showSnack('Şifre güncelleme işlemi zaman aşımına uğradı.', isError: true);
    } catch (e) {
      _showSnack('Şifre güncellenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _passwordSaving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_avatarUploading) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      _showSnack('Kullanıcı kimliği bulunamadı.', isError: true);
      return;
    }

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );

      if (picked == null) return;

      setState(() => _avatarUploading = true);

      final file = File(picked.path);
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('Profil fotoğrafı en fazla 5 MB olmalıdır.');
      }

      final extension = _fileExtension(picked.path);
      final objectPath = '$userId/avatar_${DateTime.now().millisecondsSinceEpoch}$extension';
      final contentType = _contentType(extension);

      await _supabase.storage
          .from(avatarBucket)
          .upload(
            objectPath,
            file,
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: false,
            ),
          )
          .timeout(const Duration(seconds: 35));

      final publicUrl = _supabase.storage.from(avatarBucket).getPublicUrl(objectPath);

      await _supabase
          .from('users')
          .update({'avatar_url': publicUrl})
          .eq('id', userId)
          .timeout(const Duration(seconds: 20));

      setState(() {
        _profile = {
          ...?_profile,
          'avatar_url': publicUrl,
        };
      });

      _showSnack('Profil fotoğrafı güncellendi.');
    } on StorageException catch (e) {
      _showSnack('Fotoğraf yüklenemedi: ${e.message}', isError: true);
    } on TimeoutException {
      _showSnack('Fotoğraf yükleme işlemi zaman aşımına uğradı.', isError: true);
    } catch (e) {
      _showSnack('Fotoğraf yüklenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _fileExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.heic')) return '.heic';
    if (lower.endsWith('.heif')) return '.heif';
    return '.jpg';
  }

  String _contentType(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  String _displayName() {
    final ad = (_profile?['ad'] ?? _adController.text).toString().trim();
    final soyad = (_profile?['soyad'] ?? _soyadController.text).toString().trim();
    final fullName = '$ad $soyad'.trim();
    if (fullName.isNotEmpty) return fullName;
    final username = (_profile?['username'] ?? _usernameController.text).toString().trim();
    return username.isNotEmpty ? username : 'Kullanıcı';
  }

  String _initials() {
    final ad = _adController.text.trim();
    final soyad = _soyadController.text.trim();
    final first = ad.isNotEmpty ? ad[0] : '';
    final last = soyad.isNotEmpty ? soyad[0] : '';
    final initials = '$first$last'.toUpperCase();
    return initials.isNotEmpty ? initials : 'U';
  }

  String _roleLabel(dynamic value) {
    final role = (value ?? '').toString().toLowerCase().trim();
    switch (role) {
      case 'doktor':
      case 'doctor':
      case 'veteriner':
        return 'VETERİNER';
      case 'ciftci':
      case 'çiftçi':
      case 'farmer':
        return 'ÇİFTÇİ';
      case 'user':
      case 'normal':
      case 'kullanici':
        return 'NORMAL KULLANICI';
      default:
        return role.isEmpty ? 'KULLANICI' : role.toUpperCase();
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFE53935) : const Color(0xFF0A9E68),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF3F8F4),
      drawer: UserAppDrawer(
        userData: widget.userData ?? _profile ?? const <String, dynamic>{},
        currentPage: UserDrawerPage.profile,
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F8F4),
        elevation: 0,
        centerTitle: false,
        title: const Text(
          'Profil Ayarları',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF111827)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF0A9E68)),
              )
            : RefreshIndicator(
                color: const Color(0xFF0A9E68),
                onRefresh: _loadProfile,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 18),
                      _buildPersonalInfoCard(),
                      const SizedBox(height: 18),
                      _buildSecurityCard(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final avatarUrl = (_profile?['avatar_url'] ?? '').toString().trim();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF10B981), Color(0xFF047857)],
                      ),
                    ),
                  ),
                  ...List.generate(16, (index) {
                    final left = (index * 41) % 360;
                    final top = 12 + ((index * 29) % 86);
                    final size = index.isEven ? 8.0 : 14.0;
                    return Positioned(
                      left: left.toDouble(),
                      top: top.toDouble(),
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -34),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: const Color(0xFFEAF7EF),
                            backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl.isEmpty
                                ? Text(
                                    _initials(),
                                    style: const TextStyle(
                                      color: Color(0xFF0A9E68),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 2,
                          child: InkWell(
                            onTap: _avatarUploading ? null : _pickAndUploadAvatar,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: _avatarUploading
                                  ? const Padding(
                                      padding: EdgeInsets.all(9),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 24,
                              height: 1.05,
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F8EF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.workspace_premium_rounded, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  _roleLabel(_profile?['rol']),
                                  style: const TextStyle(
                                    color: Color(0xFF0A9E68),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return _ProfileCard(
      title: 'Kişisel Bilgiler',
      icon: Icons.person_outline_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 620;
                final children = [
                  _buildTextField(
                    label: 'Ad',
                    controller: _adController,
                    validator: (value) => _requiredValidator(value, 'Ad boş bırakılamaz.'),
                  ),
                  _buildTextField(
                    label: 'Soyad',
                    controller: _soyadController,
                    validator: (value) => _requiredValidator(value, 'Soyad boş bırakılamaz.'),
                  ),
                  _buildTextField(
                    label: 'Kullanıcı Adı',
                    controller: _usernameController,
                    enabled: false,
                    helperText: 'Değiştirilemez',
                  ),
                  _buildTextField(
                    label: 'E-posta',
                    controller: _emailController,
                    enabled: false,
                    helperText: 'Değiştirilemez',
                  ),
                  _buildTextField(
                    label: 'TC Kimlik',
                    controller: _tcController,
                    keyboardType: TextInputType.number,
                    maxLength: 11,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      if (text.length != 11) return 'TC kimlik 11 haneli olmalıdır.';
                      return null;
                    },
                  ),
                  _buildTextField(
                    label: 'Telefon',
                    controller: _telefonController,
                    keyboardType: TextInputType.phone,
                  ),
                  _buildTextField(
                    label: 'Şehir',
                    controller: _sehirController,
                  ),
                ];

                if (!twoColumns) {
                  return Column(
                    children: children
                        .map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: item,
                            ))
                        .toList(),
                  );
                }

                return Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  children: children
                      .map((item) => SizedBox(
                            width: (constraints.maxWidth - 16) / 2,
                            child: item,
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveProfile,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Kaydediliyor...' : 'Değişiklikleri Kaydet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  disabledBackgroundColor: const Color(0xFF9CA3AF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard() {
    return _ProfileCard(
      title: 'Güvenlik Ayarları',
      icon: Icons.shield_outlined,
      child: Form(
        key: _passwordFormKey,
        child: Column(
          children: [
            _buildTextField(
              label: 'Yeni Şifre',
              controller: _newPasswordController,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Yeni şifre boş bırakılamaz.';
                if (text.length < 6) return 'Şifre en az 6 karakter olmalıdır.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildTextField(
              label: 'Yeni Şifre Tekrar',
              controller: _confirmPasswordController,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Şifre tekrarı boş bırakılamaz.';
                if (text != _newPasswordController.text.trim()) return 'Şifreler eşleşmiyor.';
                return null;
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _passwordSaving ? null : _updatePassword,
                icon: _passwordSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.key_rounded),
                label: Text(_passwordSaving ? 'Güncelleniyor...' : 'Şifreyi Güncelle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A9E68),
                  disabledBackgroundColor: const Color(0xFF9CA3AF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool enabled = true,
    bool obscureText = false,
    String? helperText,
    TextInputType? keyboardType,
    int? maxLength,
    String? Function(String?)? validator,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (helperText != null) ...[
              const SizedBox(width: 4),
              Text(
                '($helperText)',
                style: const TextStyle(
                  color: Color(0xFFA0AEC0),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLength: maxLength,
          validator: validator,
          style: TextStyle(
            color: enabled ? const Color(0xFF111827) : const Color(0xFF6B7280),
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            counterText: '',
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: enabled ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFFE53935), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  String? _requiredValidator(String? value, String message) {
    if ((value ?? '').trim().isEmpty) return message;
    return null;
  }
}

class _ProfileCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ProfileCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.055),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF111827), size: 25),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFE5E7EB)),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
