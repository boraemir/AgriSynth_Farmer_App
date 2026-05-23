import 'package:flutter/material.dart';

import 'calendar_screen.dart';
import 'e_veteriner_screen.dart';
import 'farmer_panel.dart';
import 'fields_screen.dart';
import 'jobs_screen.dart';
import 'login_screen.dart';
import 'marketplace_screen.dart';
import 'messages.dart';
import 'notes_screen.dart';
import 'profile_edit_screen.dart';
import 'supabase_service.dart';

enum FarmerDrawerPage {
  home,
  eVeteriner,
  fields,
  calendar,
  notes,
  marketplace,
  jobs,
  messages,
  profile,
}

class FarmerAppDrawer extends StatelessWidget {
  final Map<String, dynamic> userData;
  final FarmerDrawerPage currentPage;

  const FarmerAppDrawer({
    super.key,
    required this.userData,
    required this.currentPage,
  });

  static const Color primaryGreen = Color(0xFF1F6E43);
  static const Color darkGreen = Color(0xFF14452F);
  static const Color lightBackground = Color(0xFFF8FBF7);
  static const Color darkText = Color(0xFF1E293B);

  String get _firstName => (userData['ad'] ?? userData['first_name'] ?? '').toString().trim();
  String get _lastName => (userData['soyad'] ?? userData['last_name'] ?? '').toString().trim();
  String get _avatarUrl => (userData['avatar_url'] ?? '').toString().trim();
  String get _role => (userData['rol'] ?? userData['role'] ?? '').toString().trim();

  String get _fullName {
    final name = '$_firstName $_lastName'.trim();
    if (name.isNotEmpty) return name;
    final username = (userData['username'] ?? '').toString().trim();
    return username.isNotEmpty ? username : 'Kullanıcı';
  }

  String get _roleLabel {
    switch (_role.toLowerCase()) {
      case 'ciftci':
      case 'çiftçi':
      case 'farmer':
        return 'Çiftçi';
      case 'doktor':
      case 'doctor':
      case 'veteriner':
        return 'Veteriner';
      case 'user':
      case 'normal':
        return 'Normal Kullanıcı';
      default:
        return 'Kullanıcı';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: lightBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _drawerItem(
                    context,
                    icon: Icons.home_rounded,
                    label: 'Ana Sayfa',
                    page: FarmerDrawerPage.home,
                    builder: (_) => FarmerPanel(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.medical_services_rounded,
                    label: 'E-Veteriner',
                    page: FarmerDrawerPage.eVeteriner,
                    builder: (_) => EVeterinerScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.terrain_rounded,
                    label: 'Arazilerim',
                    page: FarmerDrawerPage.fields,
                    builder: (_) => FieldsScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.calendar_month_rounded,
                    label: 'Takvim',
                    page: FarmerDrawerPage.calendar,
                    builder: (_) => CalendarScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.note_alt_rounded,
                    label: 'Notlarım',
                    page: FarmerDrawerPage.notes,
                    builder: (_) => NotesScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.storefront_rounded,
                    label: 'İlan Pazarı',
                    page: FarmerDrawerPage.marketplace,
                    builder: (_) => MarketplaceScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.work_rounded,
                    label: 'İş Portalı',
                    page: FarmerDrawerPage.jobs,
                    builder: (_) => JobsScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Mesajlarım',
                    page: FarmerDrawerPage.messages,
                    builder: (_) => MessagesScreen(userData: userData),
                  ),
                  _drawerItem(
                    context,
                    icon: Icons.manage_accounts_rounded,
                    label: 'Profil Ayarları',
                    page: FarmerDrawerPage.profile,
                    builder: (_) => ProfileEditScreen(userData: userData),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F6E43), Color(0xFF2F8C59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withOpacity(0.18),
            backgroundImage: _avatarUrl.startsWith('http') ? NetworkImage(_avatarUrl) : null,
            child: !_avatarUrl.startsWith('http')
                ? Text(
                    _firstName.isNotEmpty ? _firstName[0].toUpperCase() : 'Ç',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
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
    required FarmerDrawerPage page,
    required WidgetBuilder builder,
  }) {
    final selected = currentPage == page;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: selected ? primaryGreen : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            final navigator = Navigator.of(context);
            navigator.pop();
            if (selected) return;
            navigator.pushReplacement(
              MaterialPageRoute(builder: builder),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : darkGreen.withOpacity(0.78),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : darkText,
                    ),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Material(
        color: Colors.redAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () async {
            final navigator = Navigator.of(context);
            navigator.pop();
            await SupabaseService().client.auth.signOut();
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.logout_rounded, color: Colors.redAccent),
                SizedBox(width: 14),
                Text(
                  'Çıkış Yap',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.redAccent,
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
