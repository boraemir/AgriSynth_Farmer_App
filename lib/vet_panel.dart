import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'vet_calendar.dart';
import 'vet_app_drawer.dart';
import 'login_screen.dart';
import 'vet_listings_requests.dart';
import 'vet_messages.dart';
import 'vet_notes.dart';
import 'vet_profile_edit_screen.dart';
import 'supabase_service.dart';
import 'vet_appointments.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design Tokens — mevcut mavi palette korundu
// ─────────────────────────────────────────────────────────────────────────────
abstract class _V {
  static const bg        = Color(0xFFF0F4FF);
  static const card      = Color(0xFFFFFFFF);
  static const surface   = Color(0xFFF5F8FF);
  static const border    = Color(0xFFE2E8F0);
  static const divider   = Color(0xFFF1F5F9);

  static const navy      = Color(0xFF0F172A);
  static const deepBlue  = Color(0xFF1E3A8A);
  static const primary   = Color(0xFF2563EB);
  static const mid       = Color(0xFF3B82F6);
  static const lightBlue = Color(0xFFDBEAFE);
  static const paleBlu   = Color(0xFFEFF6FF);

  static const amber     = Color(0xFFF59E0B);
  static const amberBg   = Color(0xFFFFFBEB);
  static const green     = Color(0xFF10B981);
  static const greenBg   = Color(0xFFECFDF5);
  static const violet    = Color(0xFF7C3AED);
  static const violetBg  = Color(0xFFF5F3FF);
  static const rose      = Color(0xFFE11D48);
  static const roseBg    = Color(0xFFFFF1F2);

  static const inkDark   = Color(0xFF0F172A);
  static const inkMid    = Color(0xFF334155);
  static const inkLight  = Color(0xFF64748B);
  static const inkMuted  = Color(0xFF94A3B8);
}

// Tek gölge seti — sadece card bazlı, animasyon yok
List<BoxShadow> get _cardShadow => [
  BoxShadow(
    color: Color(0xFF1E3A8A).withOpacity(0.06),
    blurRadius: 20,
    offset: const Offset(0, 6),
  ),
  BoxShadow(
    color: Colors.black.withOpacity(0.03),
    blurRadius: 4,
    offset: const Offset(0, 2),
  ),
];

List<BoxShadow> get _heroShadow => [
  BoxShadow(
    color: Color(0xFF1E3A8A).withOpacity(0.25),
    blurRadius: 36,
    offset: const Offset(0, 16),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// VetPanel
// ─────────────────────────────────────────────────────────────────────────────
class VetPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  const VetPanel({super.key, required this.userData});

  @override
  State<VetPanel> createState() => _VetPanelState();
}

class _VetPanelState extends State<VetPanel> {
  bool _isLoading = true;
  String? _pageError;

  Map<String, dynamic> _currentUserData = {};
  int _pendingRequestCount      = 0;
  int _activeListingCount       = 0;
  int _upcomingAppointmentCount = 0;
  int _activeChatCount          = 0;

  // ── Getters (UNCHANGED) ───────────────────────────────────────────────
  String get _authUserId => SupabaseService().client.auth.currentUser?.id ?? '';

  String get _userId {
    final fromCurrent = (_currentUserData['id'] ?? '').toString();
    if (fromCurrent.isNotEmpty) return fromCurrent;
    final fromWidget  = (widget.userData['id']  ?? '').toString();
    if (fromWidget.isNotEmpty)  return fromWidget;
    return _authUserId;
  }

  String get _name =>
      (_currentUserData['ad']    ?? widget.userData['ad']    ?? '').toString().trim();
  String get _surname =>
      (_currentUserData['soyad'] ?? widget.userData['soyad'] ?? '').toString().trim();
  String get _fullName {
    final full = '$_name $_surname'.trim();
    return full.isEmpty ? 'Veteriner' : full;
  }

  String get _avatarUrl =>
      (_currentUserData['avatar_url'] ?? widget.userData['avatar_url'] ?? '')
          .toString().trim();

  // ── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _currentUserData = Map<String, dynamic>.from(widget.userData);
    _loadDashboard();
  }

  // ── Data (UNCHANGED) ─────────────────────────────────────────────────
  Future<void> _loadDashboard() async {
    if (mounted) setState(() { _isLoading = true; _pageError = null; });
    try {
      await _refreshCurrentUser();
      await Future.wait([
        _fetchPendingRequests(),
        _fetchActiveListings(),
        _fetchUpcomingAppointments(),
        _fetchActiveChats(),
      ]);
    } catch (e) {
      debugPrint('Vet panel dashboard error: $e');
      _pageError = 'Panel bilgileri alınamadı: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshCurrentUser() async {
    final id = _userId;
    if (id.isEmpty) return;
    try {
      final data = await SupabaseService()
          .client.from('users')
          .select('id,username,email,ad,soyad,telefon,sehir,rol,avatar_url,created_at')
          .eq('id', id).maybeSingle()
          .timeout(const Duration(seconds: 15));
      if (data != null) _currentUserData = Map<String, dynamic>.from(data);
    } catch (e) { debugPrint('Vet user refresh error: $e'); }
  }

  Future<void> _fetchPendingRequests() async {
    final id = _userId; if (id.isEmpty) return;
    try {
      final data = await SupabaseService().client.from('appointments')
          .select('id').eq('doctor_id', id).eq('status', 'pending')
          .timeout(const Duration(seconds: 15));
      _pendingRequestCount = List<dynamic>.from(data).length;
    } catch (e) { _pendingRequestCount = 0; }
  }

  Future<void> _fetchActiveListings() async {
    final id = _userId; if (id.isEmpty) return;
    try {
      final data = await SupabaseService().client.from('listings')
          .select('id').eq('user_id', id).eq('category', 'veteriner')
          .eq('is_active', true).timeout(const Duration(seconds: 15));
      _activeListingCount = List<dynamic>.from(data).length;
    } catch (e) { _activeListingCount = 0; }
  }

  Future<void> _fetchUpcomingAppointments() async {
    final id = _userId; if (id.isEmpty) return;
    try {
      final today = _dateOnly(DateTime.now());
      final data = await SupabaseService().client.from('appointments')
          .select('id').eq('doctor_id', id).eq('status', 'approved')
          .gte('appointment_date', today).timeout(const Duration(seconds: 15));
      _upcomingAppointmentCount = List<dynamic>.from(data).length;
    } catch (e) { _upcomingAppointmentCount = 0; }
  }

  Future<void> _fetchActiveChats() async {
    final id = _userId; if (id.isEmpty) return;
    try {
      final data = await SupabaseService().client.from('chats')
          .select('id').or('user1_id.eq.$id,user2_id.eq.$id')
          .timeout(const Duration(seconds: 15));
      _activeChatCount = List<dynamic>.from(data).length;
    } catch (e) { _activeChatCount = 0; }
  }

  // ── Navigation (UNCHANGED) ────────────────────────────────────────────
  String _dateOnly(DateTime dt) {
    return '${dt.year.toString().padLeft(4,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  }

  String _todayLabel() {
    final now = DateTime.now();
    const months = ['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
    const days   = ['Pazartesi','Salı','Çarşamba','Perşembe','Cuma','Cumartesi','Pazar'];
    return '${now.day} ${months[now.month - 1]} ${now.year}, ${days[now.weekday - 1]}';
  }

  Future<void> _openProfileEdit() async {
    Navigator.pop(context);
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => VetProfileEditScreen(userData: _currentUserData)));
    if (mounted) await _loadDashboard();
  }

  Future<void> _logout() async {
    try {
      await SupabaseService().client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Çıkış yapılamadı: $e', isError: true);
    }
  }

  void _goTo(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _goToFromDrawer(Widget page) {
    Navigator.pop(context);
    Future.microtask(() {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: Colors.white, size: 17),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
      backgroundColor: isError ? _V.rose : _V.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _V.bg,
      drawer: _VetDrawer(
        fullName    : _fullName,
        avatarWidget: _buildAvatar(size: 52, fontSize: 18),
        onHome      : () => Navigator.pop(context),
        onListings  : () => _goToFromDrawer(VetListingsRequestsScreen(userData: _currentUserData)),
        onAppointments: () => _goToFromDrawer(VetAppointmentsScreen(userData: _currentUserData)),
        onCalendar  : () => _goToFromDrawer(VetCalendarScreen(userData: _currentUserData)),
        onMessages  : () => _goToFromDrawer(VetMessagesScreen(userData: _currentUserData)),
        onNotes     : () => _goToFromDrawer(VetNotesScreen(userData: _currentUserData)),
        onProfileEdit: _openProfileEdit,
        onLogout    : _logout,
      ),
      body: SafeArea(
        child: _isLoading
            ? const _LoadingView()
            : RefreshIndicator(
                color: _V.primary,
                backgroundColor: _V.card,
                onRefresh: _loadDashboard,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  slivers: [
                    // ── Top bar ──
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                        child: _TopBar(
                          name        : _name,
                          avatarWidget: _buildAvatar(size: 44, fontSize: 16),
                        ),
                      ),
                    ),

                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // Error banner
                          if (_pageError != null) ...[
                            _ErrorBanner(message: _pageError!),
                            const SizedBox(height: 14),
                          ],

                          // ── Hero Card ──
                          _HeroCard(
                            name        : _name,
                            todayLabel  : _todayLabel(),
                            pendingCount: _pendingRequestCount,
                            onViewRequests: () => _goTo(VetAppointmentsScreen(userData: _currentUserData)),
                          ),
                          const SizedBox(height: 16),

                          // ── 4 Stat Cards (uniform 2×2 grid) ──
                          _StatsGrid(
                            pendingCount    : _pendingRequestCount,
                            listingCount    : _activeListingCount,
                            appointmentCount: _upcomingAppointmentCount,
                            chatCount       : _activeChatCount,
                            onAppointments  : () => _goTo(VetAppointmentsScreen(userData: _currentUserData)),
                            onMessages      : () => _goTo(VetMessagesScreen(userData: _currentUserData)),
                          ),
                          const SizedBox(height: 16),

                          // ── Visit type cards ──
                          _VisitRow(
                            onFarmVisit: () => _goTo(VetAppointmentsScreen(userData: _currentUserData)),
                            onClinic   : () => _goTo(VetCalendarScreen(userData: _currentUserData)),
                          ),
                          const SizedBox(height: 22),

                          // ── Hızlı Erişim ──
                          const _SectionTitle(title: 'Hızlı Erişim'),
                          const SizedBox(height: 12),
                          _QuickGrid(
                            onMarketplace: () => _goTo(VetListingsRequestsScreen(userData: _currentUserData)),
                            onAppointments: () => _goTo(VetAppointmentsScreen(userData: _currentUserData)),
                            onNotes      : () => _goTo(VetNotesScreen(userData: _currentUserData)),
                            onMessages   : () => _goTo(VetMessagesScreen(userData: _currentUserData)),
                            onCalendar   : () => _goTo(VetCalendarScreen(userData: _currentUserData)),
                          ),
                          const SizedBox(height: 22),

                          // ── Mevsimsel Hatırlatma ──
                          const _SeasonalCard(),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Avatar ────────────────────────────────────────────────────────────
  Widget _buildAvatar({required double size, required double fontSize}) {
    final av = _avatarUrl;
    if (av.startsWith('data:image')) {
      try {
        final idx = av.indexOf(',');
        if (idx != -1) {
          final bytes = base64Decode(av.substring(idx + 1));
          return Image.memory(Uint8List.fromList(bytes),
              width: size, height: size, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(size, fontSize));
        }
      } catch (_) {}
    }
    if (av.startsWith('http')) {
      return Image.network(av,
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(size, fontSize));
    }
    return _fallback(size, fontSize);
  }

  Widget _fallback(double size, double fontSize) {
    final letter = _name.isNotEmpty ? _name[0].toUpperCase() : 'V';
    return Container(
      width: size, height: size,
      color: _V.lightBlue,
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(color: _V.deepBlue, fontSize: fontSize,
              fontWeight: FontWeight.w900)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              color: _V.card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: _cardShadow,
            ),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: CircularProgressIndicator(color: _V.primary, strokeWidth: 2.5),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Panel yükleniyor…',
              style: TextStyle(color: _V.inkLight, fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String name;
  final Widget avatarWidget;
  const _TopBar({required this.name, required this.avatarWidget});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Hamburger
        Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _V.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _V.border),
                boxShadow: _cardShadow,
              ),
              child: const Icon(Icons.menu_rounded, color: _V.navy, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Brand badge
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_V.deepBlue, _V.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.medical_services_rounded,
              color: Colors.white, size: 18),
        ),
        const SizedBox(width: 8),
        const Text('AgriSynth',
            style: TextStyle(
                color: _V.navy, fontSize: 20, fontWeight: FontWeight.w900,
                letterSpacing: -0.5)),
        const Spacer(),
        // Avatar
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _V.primary.withOpacity(0.22), width: 2),
            boxShadow: _cardShadow,
          ),
          child: ClipOval(child: avatarWidget),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Card
// ─────────────────────────────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  final String name;
  final String todayLabel;
  final int pendingCount;
  final VoidCallback onViewRequests;

  const _HeroCard({
    required this.name,
    required this.todayLabel,
    required this.pendingCount,
    required this.onViewRequests,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
          stops: [0.0, 0.50, 1.0],
        ),
        boxShadow: _heroShadow,
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Dekoratif arka plan
          Positioned(
            right: -24, top: -24,
            child: Container(
              width: 150, height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            right: -8, top: 14,
            child: Icon(Icons.local_hospital_rounded,
                size: 100, color: Colors.white.withOpacity(0.05)),
          ),
          Positioned(
            left: -30, bottom: -30,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _V.green.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _V.green.withOpacity(0.35)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 7, color: Color(0xFF6EE7B7)),
                      SizedBox(width: 6),
                      Text('Sistem Aktif',
                          style: TextStyle(color: Color(0xFF6EE7B7),
                              fontSize: 11.5, fontWeight: FontWeight.w800,
                              letterSpacing: 0.3)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Selamlama
                Text(
                  'Merhaba,\nDr. $name',
                  style: const TextStyle(
                    color: Colors.white, fontSize: 28,
                    fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(todayLabel,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.58),
                        fontSize: 12.5, fontWeight: FontWeight.w500)),
                const SizedBox(height: 20),

                // Pending alert
                if (pendingCount > 0)
                  GestureDetector(
                    onTap: onViewRequests,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _V.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _V.amber.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pending_actions_rounded,
                              color: Color(0xFFFCD34D), size: 17),
                          const SizedBox(width: 8),
                          Text('$pendingCount bekleyen talep',
                              style: const TextStyle(
                                  color: Color(0xFFFCD34D),
                                  fontSize: 13, fontWeight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: Color(0xFFFCD34D), size: 11),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.09)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: Colors.white60, size: 16),
                        SizedBox(width: 8),
                        Text('Bekleyen talep yok',
                            style: TextStyle(color: Colors.white60,
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Grid — 2×2 eşit boyut, IntrinsicHeight ile hizalanmış
// ─────────────────────────────────────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final int pendingCount;
  final int listingCount;
  final int appointmentCount;
  final int chatCount;
  final VoidCallback onAppointments;
  final VoidCallback onMessages;

  const _StatsGrid({
    required this.pendingCount,
    required this.listingCount,
    required this.appointmentCount,
    required this.chatCount,
    required this.onAppointments,
    required this.onMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  label   : 'Bekleyen Talep',
                  count   : pendingCount,
                  icon    : Icons.pending_actions_rounded,
                  accent  : _V.primary,
                  accentBg: _V.paleBlu,
                  urgent  : pendingCount > 0,
                  onTap   : onAppointments,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label   : 'Aktif İlan',
                  count   : listingCount,
                  icon    : Icons.campaign_rounded,
                  accent  : _V.green,
                  accentBg: _V.greenBg,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _StatCard(
                  label   : 'Aktif Mesaj',
                  count   : chatCount,
                  icon    : Icons.chat_bubble_rounded,
                  accent  : _V.violet,
                  accentBg: _V.violetBg,
                  onTap   : onMessages,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label   : 'Yaklaşan Randevu',
                  count   : appointmentCount,
                  icon    : Icons.event_available_rounded,
                  accent  : _V.amber,
                  accentBg: _V.amberBg,
                  onTap   : onAppointments,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color accent;
  final Color accentBg;
  final bool urgent;
  final VoidCallback? onTap;

  const _StatCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.accent,
    required this.accentBg,
    this.urgent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _V.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: urgent ? accent.withOpacity(0.25) : _V.border,
            width: urgent ? 1.5 : 1.0,
          ),
          boxShadow: _cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // İkon + urgent dot
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: urgent ? accent.withOpacity(0.12) : accentBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const Spacer(),
                if (urgent)
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // Sayı
            Text(
              count.toString(),
              style: TextStyle(
                color: urgent ? accent : _V.inkDark,
                fontSize: 34, fontWeight: FontWeight.w900,
                height: 1.0, letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 5),
            // Etiket
            Text(label,
                style: const TextStyle(color: _V.inkLight,
                    fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3)),
            // Görüntüle linki
            if (onTap != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Görüntüle',
                      style: TextStyle(color: accent, fontSize: 11.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward_rounded, color: accent, size: 13),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Visit Row — Çiftlik Ziyareti / Kliniğe Davet
// ─────────────────────────────────────────────────────────────────────────────
class _VisitRow extends StatelessWidget {
  final VoidCallback onFarmVisit;
  final VoidCallback onClinic;
  const _VisitRow({required this.onFarmVisit, required this.onClinic});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _VisitCard(
              icon    : Icons.agriculture_rounded,
              title   : 'Çiftlik Ziyareti',
              subtitle: 'Yerinde muayene talebi',
              accent  : _V.green,
              bg      : _V.greenBg,
              onTap   : onFarmVisit,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _VisitCard(
              icon    : Icons.local_hospital_rounded,
              title   : 'Kliniğe Davet',
              subtitle: 'Hayvanı kliniğe getir',
              accent  : _V.primary,
              bg      : _V.paleBlu,
              onTap   : onClinic,
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color bg;
  final VoidCallback onTap;

  const _VisitCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withOpacity(0.18), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.07),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(color: accent, fontSize: 14,
                    fontWeight: FontWeight.w800, letterSpacing: -0.2)),
            const SizedBox(height: 3),
            Text(subtitle,
                style: const TextStyle(color: _V.inkLight,
                    fontSize: 11.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Grid — 5 eylem
// ─────────────────────────────────────────────────────────────────────────────
class _QuickGrid extends StatelessWidget {
  final VoidCallback onMarketplace;
  final VoidCallback onAppointments;
  final VoidCallback onNotes;
  final VoidCallback onMessages;
  final VoidCallback onCalendar;

  const _QuickGrid({
    required this.onMarketplace,
    required this.onAppointments,
    required this.onNotes,
    required this.onMessages,
    required this.onCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _QItem(icon: Icons.publish_rounded,        label: 'Profil Yayınla', accent: _V.primary,   onTap: onMarketplace),
      _QItem(icon: Icons.search_rounded,         label: 'Talepleri Gör',  accent: _V.deepBlue,  onTap: onAppointments),
      _QItem(icon: Icons.calendar_month_rounded, label: 'Randevular',     accent: _V.amber,     onTap: onAppointments),
      _QItem(icon: Icons.sticky_note_2_rounded,  label: 'Notlarım',       accent: _V.violet,    onTap: onNotes),
      _QItem(icon: Icons.chat_bubble_rounded,    label: 'Mesajlar',       accent: _V.green,     onTap: onMessages),
    ];

    return Column(
      children: [
        // Üst sıra — 3 kart
        Row(
          children: List.generate(3, (i) => [
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _QCard(item: items[i], wide: false)),
          ]).expand((e) => e).toList(),
        ),
        const SizedBox(height: 10),
        // Alt sıra — 2 geniş kart
        Row(
          children: [
            Expanded(child: _QCard(item: items[3], wide: true)),
            const SizedBox(width: 10),
            Expanded(child: _QCard(item: items[4], wide: true)),
          ],
        ),
      ],
    );
  }
}

class _QItem {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  const _QItem({required this.icon, required this.label,
      required this.accent, required this.onTap});
}

class _QCard extends StatelessWidget {
  final _QItem item;
  final bool wide;
  const _QCard({required this.item, required this.wide});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: 12, vertical: wide ? 15 : 13),
        decoration: BoxDecoration(
          color: _V.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _V.border),
          boxShadow: _cardShadow,
        ),
        child: wide
            ? Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: item.accent.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(item.icon, color: item.accent, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.label,
                        style: const TextStyle(color: _V.inkDark,
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: _V.inkMuted, size: 18),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: item.accent.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(item.icon, color: item.accent, size: 20),
                  ),
                  const SizedBox(height: 9),
                  Text(item.label,
                      textAlign: TextAlign.center, maxLines: 2,
                      style: const TextStyle(color: _V.inkDark, fontSize: 11.5,
                          fontWeight: FontWeight.w700, height: 1.25)),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Title
// ─────────────────────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3, height: 20,
          decoration: BoxDecoration(
              color: _V.primary, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(color: _V.inkDark, fontSize: 18,
                fontWeight: FontWeight.w900, letterSpacing: -0.3)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seasonal Notes Card (PageView, hareketli efekt yok)
// ─────────────────────────────────────────────────────────────────────────────
class _SeasonalCard extends StatefulWidget {
  const _SeasonalCard();

  @override
  State<_SeasonalCard> createState() => _SeasonalCardState();
}

class _SeasonalCardState extends State<_SeasonalCard> {
  final PageController _ctrl = PageController();
  int _page = 0;

  static const List<_SNote> _notes = [
    _SNote(
      season: 'İlkbahar', icon: Icons.local_florist_rounded,
      accent: Color(0xFF16A34A), bg: Color(0xFFECFDF5),
      title : 'Aşı & Parazit Takibi',
      body  : 'İlkbaharda hayvanların aşı takvimini ve parazit mücadelelerini kontrol etmeyi unutmayın. Mevsim geçişi bağışıklığı zayıflatabiliyor.',
    ),
    _SNote(
      season: 'Yaz', icon: Icons.wb_sunny_rounded,
      accent: Color(0xFFD97706), bg: Color(0xFFFFFBEB),
      title : 'Sıcak Stres & Hidrasyon',
      body  : 'Yaz aylarında büyükbaş ve küçükbaşlarda ısı stresi riski yükselir. Gölgelik alanları ve temiz su kaynaklarını düzenli kontrol edin.',
    ),
    _SNote(
      season: 'Sonbahar', icon: Icons.energy_savings_leaf_rounded,
      accent: Color(0xFFEA580C), bg: Color(0xFFFFF7ED),
      title : 'Kış Hazırlığı',
      body  : 'Sonbaharda solunum yolu enfeksiyonlarına karşı koruyucu aşılama takvimini güncelleyin. Barınak nem ve ısısını ayarlayın.',
    ),
    _SNote(
      season: 'Kış', icon: Icons.ac_unit_rounded,
      accent: Color(0xFF2563EB), bg: Color(0xFFEFF6FF),
      title : 'Soğuk & Beslenme Takibi',
      body  : 'Kış döneminde hayvanların enerji ihtiyacı artar. Yem kalitesini ve barınak sıcaklığını düzenli olarak izleyin.',
    ),
    _SNote(
      season: 'Genel', icon: Icons.medical_services_rounded,
      accent: Color(0xFF7C3AED), bg: Color(0xFFF5F3FF),
      title : 'Düzenli Kontrol',
      body  : 'Rutin muayene ve erken teşhis, tedavi maliyetlerini önemli ölçüde düşürür. Bölgenizdeki nem artışı parazit riskini yükseltebilir.',
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = _notes[_page];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Başlık satırı
        Row(
          children: [
            Container(
              width: 3, height: 20,
              decoration: BoxDecoration(
                  color: note.accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Mevsimsel Hatırlatma',
                  style: TextStyle(color: _V.inkDark, fontSize: 18,
                      fontWeight: FontWeight.w900, letterSpacing: -0.3)),
            ),
            Text('${_page + 1} / ${_notes.length}',
                style: const TextStyle(color: _V.inkMuted,
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),

        // Kart
        Container(
          decoration: BoxDecoration(
            color: note.bg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: note.accent.withOpacity(0.18), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: note.accent.withOpacity(0.08),
                blurRadius: 18, offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            children: [
              // PageView içerik
              SizedBox(
                height: 162,
                child: PageView.builder(
                  controller: _ctrl,
                  itemCount: _notes.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, idx) {
                    final n = _notes[idx];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: n.accent.withOpacity(0.13),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(n.icon, color: n.accent, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.season.toUpperCase(),
                                      style: TextStyle(color: n.accent,
                                          fontSize: 10, fontWeight: FontWeight.w800,
                                          letterSpacing: 0.7)),
                                  Text(n.title,
                                      style: const TextStyle(color: _V.inkDark,
                                          fontSize: 14.5, fontWeight: FontWeight.w800,
                                          letterSpacing: -0.2)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(n.body,
                              maxLines: 3, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: _V.inkMid,
                                  fontSize: 13, height: 1.55,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Nav bar — oklar + dots
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    // Önceki
                    _NavBtn(
                      icon   : Icons.chevron_left_rounded,
                      color  : note.accent,
                      enabled: _page > 0,
                      onTap  : () {
                        if (_page > 0) _ctrl.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // Dots
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_notes.length, (i) {
                          final active = i == _page;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2.5),
                            width : active ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? _notes[_page].accent
                                  : _V.inkMuted.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sonraki
                    _NavBtn(
                      icon   : Icons.chevron_right_rounded,
                      color  : note.accent,
                      enabled: _page < _notes.length - 1,
                      onTap  : () {
                        if (_page < _notes.length - 1) _ctrl.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.color,
      required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            color: enabled ? color : _V.inkMuted.withOpacity(0.28), size: 20),
      ),
    );
  }
}

class _SNote {
  final String season;
  final IconData icon;
  final Color accent;
  final Color bg;
  final String title;
  final String body;
  const _SNote({required this.season, required this.icon, required this.accent,
      required this.bg, required this.title, required this.body});
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _V.roseBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _V.rose.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: _V.rose, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: _V.rose,
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Drawer — mevcut yapı korundu, VetAppDrawer yerine inline
// ─────────────────────────────────────────────────────────────────────────────
class _VetDrawer extends StatelessWidget {
  final String fullName;
  final Widget avatarWidget;
  final VoidCallback onHome;
  final VoidCallback onListings;
  final VoidCallback onAppointments;
  final VoidCallback onCalendar;
  final VoidCallback onMessages;
  final VoidCallback onNotes;
  final VoidCallback onProfileEdit;
  final VoidCallback onLogout;

  const _VetDrawer({
    required this.fullName,
    required this.avatarWidget,
    required this.onHome,
    required this.onListings,
    required this.onAppointments,
    required this.onCalendar,
    required this.onMessages,
    required this.onNotes,
    required this.onProfileEdit,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _V.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight   : Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profil başlığı
            Container(
              margin : const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                  begin: Alignment.topLeft,
                  end  : Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      shape : BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.20), width: 2),
                    ),
                    child: ClipOval(child: avatarWidget),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dr. $fullName',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white,
                                fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _V.primary.withOpacity(0.30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('AgriSynth Hekim',
                              style: TextStyle(color: Color(0xFF93C5FD),
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Nav listesi
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _DNavItem(icon: Icons.home_rounded,              label: 'Ana Sayfa',         onTap: onHome,         selected: true),
                  _DNavItem(icon: Icons.assignment_rounded,        label: 'İlanlar & Talepler', onTap: onListings),
                  _DNavItem(icon: Icons.calendar_today_rounded,    label: 'Randevularım',       onTap: onAppointments),
                  _DNavItem(icon: Icons.event_note_rounded,        label: 'Takvim',             onTap: onCalendar),
                  _DNavItem(icon: Icons.chat_bubble_outline_rounded,label: 'Mesajlarım',        onTap: onMessages),
                  _DNavItem(icon: Icons.description_rounded,       label: 'Notlarım',           onTap: onNotes),
                  const SizedBox(height: 8),
                  const Divider(color: _V.border, height: 1),
                  const SizedBox(height: 8),
                  _DNavItem(icon: Icons.manage_accounts_rounded,   label: 'Profil Ayarları',   onTap: onProfileEdit),
                ],
              ),
            ),

            // Çıkış
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: GestureDetector(
                onTap: onLogout,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _V.roseBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _V.rose.withOpacity(0.15), width: 1),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: _V.rose, size: 20),
                      SizedBox(width: 12),
                      Text('Çıkış Yap',
                          style: TextStyle(color: _V.rose,
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ],
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

class _DNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _DNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _V.primary.withOpacity(0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? _V.primary.withOpacity(0.11)
                    : _V.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected ? _V.primary : _V.inkLight, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: selected ? _V.primary : _V.inkDark,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
            ),
            if (selected)
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: _V.primary, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}