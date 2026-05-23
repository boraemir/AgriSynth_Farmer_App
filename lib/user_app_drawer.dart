import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'supabase_service.dart';
import 'user_calendar_screen.dart';
import 'user_jobs_screen.dart';
import 'user_marketplace_screen.dart';
import 'user_messages.dart';
import 'user_notes_screen.dart';
import 'user_panel.dart';
import 'user_profile_edit_screen.dart';

/// Normal kullanıcı tarafındaki tüm sayfalarda ortak kullanılacak drawer.
/// Çiftçi panelindeki yeşil tasarım korunmuştur; sadece rol ve yönlendirmeler
/// normal kullanıcı akışına göre sadeleştirilmiştir.
enum UserDrawerPage {
  home,
  calendar,
  notes,
  marketplace,
  jobs,
  messages,
  profile,
}

class UserAppDrawer extends StatelessWidget {
  final Map<String, dynamic> userData;
  final UserDrawerPage currentPage;

  const UserAppDrawer({
    super.key,
    required this.userData,
    required this.currentPage,
  });

  static const Color primaryGreen = Color(0xFF1F6E43);
  static const Color darkGreen = Color(0xFF14452F);
  static const Color lightBackground = Color(0xFFF8FBF7);
  static const Color darkText = Color(0xFF1E293B);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color danger = Color(0xFFE11D48);
  static const Color dangerBg = Color(0xFFFFF1F2);

  String get _firstName =>
      (userData['ad'] ?? userData['first_name'] ?? '').toString().trim();

  String get _lastName =>
      (userData['soyad'] ?? userData['last_name'] ?? '').toString().trim();

  String get _avatarUrl => (userData['avatar_url'] ?? '').toString().trim();

  String get _fullName {
    final name = '$_firstName $_lastName'.trim();
    if (name.isNotEmpty) return name;
    final username = (userData['username'] ?? '').toString().trim();
    return username.isNotEmpty ? username : 'Kullanıcı';
  }

  String get _initial {
    final source = _firstName.isNotEmpty ? _firstName : _fullName;
    return source.isNotEmpty ? source[0].toUpperCase() : 'N';
  }

  Widget _avatar({double size = 52, double fontSize = 18}) {
    if (_avatarUrl.startsWith('data:image')) {
      try {
        final commaIndex = _avatarUrl.indexOf(',');
        if (commaIndex != -1) {
          final bytes = base64Decode(_avatarUrl.substring(commaIndex + 1));
          return Image.memory(
            Uint8List.fromList(bytes),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _avatarFallback(size, fontSize),
          );
        }
      } catch (_) {
        return _avatarFallback(size, fontSize);
      }
    }

    if (_avatarUrl.startsWith('http')) {
      return Image.network(
        _avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(size, fontSize),
      );
    }

    return _avatarFallback(size, fontSize);
  }

  Widget _avatarFallback(double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      color: Colors.white.withOpacity(0.18),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _navigate(BuildContext context, UserDrawerPage target) {
    final navigator = Navigator.of(context);
    navigator.pop();

    if (target == currentPage) return;

    late final Widget page;
    switch (target) {
      case UserDrawerPage.home:
        page = UserPanel(userData: userData);
        break;
      case UserDrawerPage.calendar:
        page = UserCalendarScreen(userData: userData);
        break;
      case UserDrawerPage.notes:
        page = UserNotesScreen(userData: userData);
        break;
      case UserDrawerPage.marketplace:
        page = UserMarketplaceScreen(userData: userData);
        break;
      case UserDrawerPage.jobs:
        page = UserJobsScreen(userData: userData);
        break;
      case UserDrawerPage.messages:
        page = UserMessagesScreen(userData: userData);
        break;
      case UserDrawerPage.profile:
        page = UserProfileEditScreen(userData: userData);
        break;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      if (target == UserDrawerPage.home) {
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => page),
          (route) => false,
        );
      } else {
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => page),
        );
      }
    });
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    navigator.pop();

    try {
      await SupabaseService().client.auth.signOut();
      if (!navigator.mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Çıkış yapılamadı: $e'),
          backgroundColor: danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                physics: const BouncingScrollPhysics(),
                children: [
                  _drawerItem(
                    context,
                    icon: Icons.home_rounded,
                    label: 'Ana Sayfa',
                    page: UserDrawerPage.home,
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.calendar_month_rounded,
                    label: 'Takvim',
                    page: UserDrawerPage.calendar,
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.note_alt_rounded,
                    label: 'Notlarım',
                    page: UserDrawerPage.notes,
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.storefront_rounded,
                    label: 'İlan Pazarı',
                    page: UserDrawerPage.marketplace,
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.work_outline_rounded,
                    label: 'İş Portalı',
                    page: UserDrawerPage.jobs,
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Mesajlarım',
                    page: UserDrawerPage.messages,
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: borderColor, height: 1),
                  const SizedBox(height: 8),
                  _drawerItem(
                    context,
                    icon: Icons.manage_accounts_rounded,
                    label: 'Profil Ayarları',
                    page: UserDrawerPage.profile,
                  ),
                ],
              ),
            ),
            _logoutButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F6E43), Color(0xFF2F8C59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withOpacity(0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.24),
                width: 2,
              ),
            ),
            child: ClipOval(child: _avatar()),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Normal Kullanıcı',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required UserDrawerPage page,
  }) {
    final selected = currentPage == page;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: selected ? primaryGreen.withOpacity(0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _navigate(context, page),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? primaryGreen.withOpacity(0.14) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor.withOpacity(0.85)),
                  ),
                  child: Icon(
                    icon,
                    color: selected ? primaryGreen : darkGreen.withOpacity(0.72),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      color: selected ? primaryGreen : darkText,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: primaryGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Material(
        color: dangerBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _logout(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.logout_rounded, color: danger, size: 20),
                SizedBox(width: 12),
                Text(
                  'Çıkış Yap',
                  style: TextStyle(
                    color: danger,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
