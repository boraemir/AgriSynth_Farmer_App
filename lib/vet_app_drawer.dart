import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'supabase_service.dart';
import 'vet_appointments.dart';
import 'vet_calendar.dart';
import 'vet_listings_requests.dart';
import 'vet_messages.dart';
import 'vet_notes.dart';
import 'vet_panel.dart';
import 'vet_profile_edit_screen.dart';

enum VetDrawerPage {
  home,
  listings,
  appointments,
  calendar,
  messages,
  notes,
  profile,
}

class VetAppDrawer extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VetDrawerPage currentPage;

  const VetAppDrawer({
    super.key,
    required this.userData,
    required this.currentPage,
  });

  static const Color _cardWhite = Color(0xFFFFFFFF);
  static const Color _surface = Color(0xFFF1F4F8);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _deepBlue = Color(0xFF1E3A8A);
  static const Color _primary = Color(0xFF2563EB);
  static const Color _inkLight = Color(0xFF64748B);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _rose = Color(0xFFE11D48);
  static const Color _roseBg = Color(0xFFFFF1F2);

  String get _name => (userData['ad'] ?? userData['first_name'] ?? '').toString().trim();
  String get _surname => (userData['soyad'] ?? userData['last_name'] ?? '').toString().trim();

  String get _fullName {
    final full = '$_name $_surname'.trim();
    return full.isEmpty ? 'Veteriner' : full;
  }

  String get _avatarUrl => (userData['avatar_url'] ?? '').toString().trim();

  String get _initial {
    final source = _name.isNotEmpty ? _name : _fullName;
    return source.isNotEmpty ? source[0].toUpperCase() : 'V';
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
      color: const Color(0xFFDBEAFE),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: TextStyle(
          color: _deepBlue,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _navigate(BuildContext context, VetDrawerPage target) {
    final navigator = Navigator.of(context);
    navigator.pop();

    if (target == currentPage) return;

    late final Widget page;
    switch (target) {
      case VetDrawerPage.home:
        page = VetPanel(userData: userData);
        break;
      case VetDrawerPage.listings:
        page = VetListingsRequestsScreen(userData: userData);
        break;
      case VetDrawerPage.appointments:
        page = VetAppointmentsScreen(userData: userData);
        break;
      case VetDrawerPage.calendar:
        page = VetCalendarScreen(userData: userData);
        break;
      case VetDrawerPage.messages:
        page = VetMessagesScreen(userData: userData);
        break;
      case VetDrawerPage.notes:
        page = VetNotesScreen(userData: userData);
        break;
      case VetDrawerPage.profile:
        page = VetProfileEditScreen(userData: userData);
        break;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      if (target == VetDrawerPage.home) {
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
          backgroundColor: _rose,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _cardWhite,
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
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.20),
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
                          'Dr. $_fullName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Hekim Paneli',
                            style: TextStyle(
                              color: Color(0xFF93C5FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                physics: const BouncingScrollPhysics(),
                children: [
                  _VetDrawerItem(
                    icon: Icons.home_rounded,
                    label: 'Ana Sayfa',
                    selected: currentPage == VetDrawerPage.home,
                    onTap: () => _navigate(context, VetDrawerPage.home),
                  ),
                  _VetDrawerItem(
                    icon: Icons.assignment_rounded,
                    label: 'İlanlar & Talepler',
                    selected: currentPage == VetDrawerPage.listings,
                    onTap: () => _navigate(context, VetDrawerPage.listings),
                  ),
                  _VetDrawerItem(
                    icon: Icons.calendar_today_rounded,
                    label: 'Randevularım',
                    selected: currentPage == VetDrawerPage.appointments,
                    onTap: () => _navigate(context, VetDrawerPage.appointments),
                  ),
                  _VetDrawerItem(
                    icon: Icons.event_note_rounded,
                    label: 'Takvim',
                    selected: currentPage == VetDrawerPage.calendar,
                    onTap: () => _navigate(context, VetDrawerPage.calendar),
                  ),
                  _VetDrawerItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Mesajlarım',
                    selected: currentPage == VetDrawerPage.messages,
                    onTap: () => _navigate(context, VetDrawerPage.messages),
                  ),
                  _VetDrawerItem(
                    icon: Icons.description_rounded,
                    label: 'Notlarım',
                    selected: currentPage == VetDrawerPage.notes,
                    onTap: () => _navigate(context, VetDrawerPage.notes),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: _border, height: 1),
                  const SizedBox(height: 8),
                  _VetDrawerItem(
                    icon: Icons.manage_accounts_rounded,
                    label: 'Profil Ayarları',
                    selected: currentPage == VetDrawerPage.profile,
                    onTap: () => _navigate(context, VetDrawerPage.profile),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Material(
                color: _roseBg,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _logout(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, color: _rose, size: 20),
                        SizedBox(width: 12),
                        Text(
                          'Çıkış Yap',
                          style: TextStyle(
                            color: _rose,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VetDrawerItem extends StatelessWidget {
  static const Color _surface = Color(0xFFF1F4F8);
  static const Color _navy = Color(0xFF0F172A);
  static const Color _primary = Color(0xFF2563EB);
  static const Color _inkLight = Color(0xFF64748B);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _VetDrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: selected ? _primary.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? _primary.withOpacity(0.12) : _surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: selected ? _primary : _inkLight,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? _primary : _navy,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _primary,
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
}
