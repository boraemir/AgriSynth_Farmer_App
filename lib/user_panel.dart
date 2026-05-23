import 'dart:convert';
import 'package:flutter/material.dart';
import 'user_app_drawer.dart';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';
import 'user_calendar_screen.dart';
import 'user_notes_screen.dart';
import 'user_marketplace_screen.dart';
import 'user_messages.dart';
import 'user_profile_edit_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Design Tokens
// ─────────────────────────────────────────────────────────────────────────────
abstract class _FC {
  // Greens
  static const forest = Color(0xFF0E3D22);
  static const primary = Color(0xFF1F6E43);
  static const canopy = Color(0xFF2A8C57);
  static const leaf = Color(0xFF3AAD6B);
  static const softGreen = Color(0xFFA7D7B5);
  static const paleMint = Color(0xFFE2F5EA);
  static const mintFrost = Color(0xFFF0FAF4);

  // Neutrals
  static const bg = Color(0xFFF5F7F5);
  static const cardWhite = Colors.white;
  static const surface = Color(0xFFF9FBF9);
  static const border = Color(0xFFE4EDE7);

  // Text
  static const inkDark = Color(0xFF0F1F16);
  static const inkMid = Color(0xFF2D4A38);
  static const inkLight = Color(0xFF64748B);
  static const inkMuted = Color(0xFF94A3B8);

  // Semantic
  static const amber = Color(0xFFF59E0B);
  static const amberBg = Color(0xFFFFFBEB);
  static const blue = Color(0xFF2563EB);
  static const blueBg = Color(0xFFEFF6FF);
  static const violet = Color(0xFF7C3AED);
  static const violetBg = Color(0xFFF5F3FF);
  static const rose = Color(0xFFE11D48);
  static const roseBg = Color(0xFFFFF1F2);
}

abstract class _FS {
  static List<BoxShadow> card = [
    BoxShadow(
      color: Color(0xFF1F6E43).withOpacity(0.07),
      blurRadius: 28,
      offset: const Offset(0, 10),
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.03),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0xFF0E3D22).withOpacity(0.30),
      blurRadius: 48,
      spreadRadius: 0,
      offset: const Offset(0, 24),
    ),
  ];

  static List<BoxShadow> subtle = [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// UserPanel
// ─────────────────────────────────────────────────────────────────────────────
class UserPanel extends StatefulWidget {
  final Map<String, dynamic> userData;
  const UserPanel({super.key, required this.userData});

  @override
  State<UserPanel> createState() => _UserPanelState();
}

class _UserPanelState extends State<UserPanel>
    with SingleTickerProviderStateMixin {
  // ── palette aliases kept for minimal code changes ─────────────────────
  static const Color primaryGreen = _FC.primary;
  static const Color darkGreen = _FC.forest;

  // ── State ─────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isRefreshingWeather = false;
  String? _pageError;

  Map<String, dynamic>? _weatherData;
  List<Map<String, dynamic>> _recentNotes = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _featuredListings = [];
  late Map<String, dynamic> _currentUserData;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Getters (UNCHANGED) ───────────────────────────────────────────────
  String get _userId => (_currentUserData['id'] ?? '').toString();
  String get _userName => (_currentUserData['ad'] ?? '').toString();
  String get _userSurname => (_currentUserData['soyad'] ?? '').toString();
  String get _userCity => (_currentUserData['sehir'] ?? '').toString();
  String get _avatarUrl => (_currentUserData['avatar_url'] ?? '').toString();
  String get _userRole => (_currentUserData['rol'] ?? '').toString();

  String get _fullName {
    final full = '$_userName $_userSurname'.trim();
    return full.isEmpty ? 'Kullanıcı' : full;
  }

  String get _roleLabel {
    switch (_userRole.toLowerCase().trim()) {
      case 'ciftci':
        return 'Çiftçi';
      case 'user':
        return 'Normal Kullanıcı';
      case 'doktor':
        return 'Veteriner';
      default:
        return 'Kullanıcı';
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _currentUserData = Map<String, dynamic>.from(widget.userData);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // İlk veri yüklemesini build tamamlandıktan sonra başlatıyoruz.
    // Böylece sayfa ilk çizilirken semantics/layout ağacı aynı anda kirlenmiyor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadDashboard();
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data Methods (UNCHANGED logic) ────────────────────────────────────
  Future<void> _loadDashboard({bool showLoader = true}) async {
    if (!mounted) return;

    if (showLoader) {
      setState(() {
        _isLoading = true;
        _pageError = null;
      });
    } else {
      _pageError = null;
    }

    String? errorMessage;

    try {
      await Future.wait([
        _fetchWeather(),
        _fetchRecentNotes(),
        _fetchUpcomingEvents(),
        _fetchFeaturedListings(),
      ]);
    } catch (e) {
      errorMessage = 'Veriler yüklenirken bir sorun oluştu.';
      debugPrint('Dashboard load error: $e');
    }

    if (!mounted) return;

    setState(() {
      _pageError = errorMessage;
      _isLoading = false;
    });

    if (errorMessage == null) {
      _fadeCtrl.forward(from: 0);
    }
  }

  Future<void> _refreshAll() async => _loadDashboard(showLoader: false);

  Future<void> _refreshCurrentUserData() async {
    final currentAuthId = SupabaseService().client.auth.currentUser?.id;
    final id = _userId.isNotEmpty ? _userId : (currentAuthId ?? '');
    if (id.isEmpty) return;
    try {
      final data = await SupabaseService()
          .client
          .from('users')
          .select('id,username,email,ad,soyad,tc_kimlik,telefon,sehir,rol,created_at,avatar_url')
          .eq('id', id)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() => _currentUserData = Map<String, dynamic>.from(data));
      }
    } catch (e) {
      debugPrint('Refresh profile data error: $e');
    }
  }

  Future<void> _openProfileEdit() async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => UserProfileEditScreen(userData: _currentUserData)),
    );
    if (!mounted) return;
    await _refreshCurrentUserData();
    await _fetchWeather();
    if (mounted) setState(() {});
  }

  // ── Weather (UNCHANGED) ───────────────────────────────────────────────
  Future<void> _fetchWeather() async {
    final city = _userCity.trim();
    if (city.isEmpty) {
      _weatherData = {
        'city': 'Şehir bilgisi yok',
        'temperature': '--',
        'description': 'Hava durumu alınamadı',
        'isDay': true,
        'code': 0,
        'hourly': <Map<String, dynamic>>[],
      };
      return;
    }
    try {
      final geocodeUri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=tr&format=json',
      );
      final geocodeRes = await http.get(geocodeUri);
      if (geocodeRes.statusCode != 200) throw Exception('Geocoding başarısız');

      final geocodeJson = jsonDecode(geocodeRes.body) as Map<String, dynamic>;
      final results = (geocodeJson['results'] as List?) ?? [];
      if (results.isEmpty) {
        _weatherData = {
          'city': city,
          'temperature': '--',
          'description': 'Konum bulunamadı',
          'isDay': true,
          'code': 0,
          'hourly': <Map<String, dynamic>>[],
        };
        return;
      }

      final first = results.first as Map<String, dynamic>;
      final lat = first['latitude'];
      final lon = first['longitude'];
      final resolvedCity = (first['name'] ?? city).toString();

      final forecastUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code&timezone=auto&forecast_days=2',
      );
      final forecastRes = await http.get(forecastUri);
      if (forecastRes.statusCode != 200) throw Exception('Forecast başarısız');

      final forecastJson = jsonDecode(forecastRes.body) as Map<String, dynamic>;
      final current = (forecastJson['current'] as Map<String, dynamic>?) ?? {};
      final hourly = (forecastJson['hourly'] as Map<String, dynamic>?) ?? {};

      final times = List<String>.from(hourly['time'] ?? []);
      final temps = List<dynamic>.from(hourly['temperature_2m'] ?? []);
      final codes = List<dynamic>.from(hourly['weather_code'] ?? []);

      final now = DateTime.now();
      final List<Map<String, dynamic>> hourlyCards = [];
      for (int i = 0; i < times.length; i++) {
        final parsed = DateTime.tryParse(times[i]);
        if (parsed == null) continue;
        if (parsed.isBefore(now)) continue;
        hourlyCards.add({
          'time': _formatHour(parsed),
          'temp': _safeRound(temps.length > i ? temps[i] : null),
          'code': (codes.length > i ? codes[i] : 0) ?? 0,
        });
        if (hourlyCards.length == 4) break;
      }

      _weatherData = {
        'city': resolvedCity,
        'temperature': _safeRound(current['temperature_2m']),
        'description': _weatherDescription(current['weather_code']),
        'isDay': (current['is_day'] ?? 1) == 1,
        'code': current['weather_code'] ?? 0,
        'hourly': hourlyCards,
      };
    } catch (e) {
      debugPrint('Weather error: $e');
      _weatherData = {
        'city': city,
        'temperature': '--',
        'description': 'Hava durumu alınamadı',
        'isDay': true,
        'code': 0,
        'hourly': <Map<String, dynamic>>[],
      };
    }
  }

  Future<void> _refreshWeatherOnly() async {
    if (!mounted) return;
    setState(() => _isRefreshingWeather = true);
    await _fetchWeather();
    if (!mounted) return;
    setState(() => _isRefreshingWeather = false);
  }

  Future<void> _fetchRecentNotes() async {
    try {
      final data = await SupabaseService()
          .client
          .from('notes')
          .select('id,title,content,images,created_at,note_date,note_time,color')
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .limit(2);
      _recentNotes = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Recent notes error: $e');
      _recentNotes = [];
    }
  }

  Future<void> _fetchUpcomingEvents() async {
    try {
      final now = DateTime.now();
      final today = _dateOnly(now);
      final tomorrow = _dateOnly(now.add(const Duration(days: 1)));
      final data = await SupabaseService()
          .client
          .from('notes')
          .select('id,title,content,note_date,note_time,end_time,color')
          .eq('user_id', _userId)
          .not('note_date', 'is', null)
          .gte('note_date', today)
          .lte('note_date', tomorrow)
          .order('note_date', ascending: true)
          .order('note_time', ascending: true);
      _upcomingEvents = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Upcoming events error: $e');
      _upcomingEvents = [];
    }
  }

  Future<void> _fetchFeaturedListings() async {
    try {
      final data = await SupabaseService()
          .client
          .from('listings')
          .select('id,title,description,price,photos,location,category,created_at,is_active')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(4);
      _featuredListings = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Listings error: $e');
      _featuredListings = [];
    }
  }

  // ── Helpers (UNCHANGED) ───────────────────────────────────────────────
  String _dateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatHour(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _safeRound(dynamic value) {
    if (value == null) return '--';
    if (value is int) return value.toString();
    if (value is double) return value.round().toString();
    final parsed = double.tryParse(value.toString());
    return parsed == null ? '--' : parsed.round().toString();
  }

  String _weatherDescription(dynamic code) {
    final int c = int.tryParse(code.toString()) ?? 0;
    if (c == 0) return 'Açık';
    if (c == 1 || c == 2) return 'Parçalı Bulutlu';
    if (c == 3) return 'Bulutlu';
    if (c == 45 || c == 48) return 'Sisli';
    if (c == 51 || c == 53 || c == 55) return 'Çiseleme';
    if (c == 61 || c == 63 || c == 65) return 'Yağmurlu';
    if (c == 66 || c == 67) return 'Donan Yağmur';
    if (c == 71 || c == 73 || c == 75) return 'Karlı';
    if (c == 80 || c == 81 || c == 82) return 'Sağanak';
    if (c == 95 || c == 96 || c == 99) return 'Fırtınalı';
    return 'Hava Durumu';
  }

  IconData _weatherIcon(dynamic code, {bool isDay = true}) {
    final int c = int.tryParse(code.toString()) ?? 0;
    if (c == 0) return isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
    if (c == 1 || c == 2) return Icons.wb_cloudy_rounded;
    if (c == 3) return Icons.cloud_rounded;
    if (c == 45 || c == 48) return Icons.blur_on_rounded;
    if (c == 51 || c == 53 || c == 55) return Icons.grain_rounded;
    if (c == 61 || c == 63 || c == 65 || c == 80 || c == 81 || c == 82) {
      return Icons.water_drop_rounded;
    }
    if (c == 71 || c == 73 || c == 75) return Icons.ac_unit_rounded;
    if (c == 95 || c == 96 || c == 99) return Icons.thunderstorm_rounded;
    return Icons.cloud_rounded;
  }

  Color _noteAccent(int? colorIndex) {
    switch (colorIndex ?? 0) {
      case 1: return const Color(0xFF16A34A);
      case 2: return const Color(0xFF0284C7);
      case 3: return const Color(0xFFF59E0B);
      case 4: return const Color(0xFF8B5CF6);
      case 5: return const Color(0xFFEF4444);
      default: return primaryGreen;
    }
  }

  String _relativeTime(dynamic createdAt) {
    if (createdAt == null) return 'Şimdi';
    final dt = DateTime.tryParse(createdAt.toString());
    if (dt == null) return 'Şimdi';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    if (diff.inDays == 1) return 'Dün';
    return '${diff.inDays} gün önce';
  }

  String _formatEventDate(dynamic noteDate) {
    if (noteDate == null) return '';
    final dt = DateTime.tryParse(noteDate.toString());
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    if (target == today) return 'Bugün';
    if (target == today.add(const Duration(days: 1))) return 'Yarın';
    const months = ['','Oca','Şub','Mar','Nis','May','Haz','Tem','Ağu','Eyl','Eki','Kas','Ara'];
    return '${dt.day} ${months[dt.month]}';
  }

  String _formatNoteTime(dynamic noteTime) {
    if (noteTime == null) return 'Tüm Gün';
    final raw = noteTime.toString();
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  String _listingPhoto(dynamic photos) {
    if (photos == null) return '';

    String clean(String value) {
      return value
          .trim()
          .replaceAll(RegExp(r'''^["']+'''), '')
          .replaceAll(RegExp(r'''["']+$'''), '')
          .trim();
    }

    String normalize(String value) {
      var photo = clean(value);
      if (photo.isEmpty) return '';

      if (photo.startsWith('data:image')) return photo;
      if (photo.startsWith('http://') || photo.startsWith('https://')) return photo;

      if (photo.startsWith('/')) photo = photo.substring(1);
      if (photo.startsWith('listing-photos/')) {
        photo = photo.replaceFirst('listing-photos/', '');
      }

      try {
        return SupabaseService()
            .client
            .storage
            .from('listing-photos')
            .getPublicUrl(photo);
      } catch (_) {
        return '';
      }
    }

    if (photos is List) {
      for (final item in photos) {
        final parsed = normalize(item.toString());
        if (parsed.isNotEmpty) return parsed;
      }
      return '';
    }

    if (photos is Map) {
      for (final key in ['url', 'publicUrl', 'path', 'src']) {
        final value = photos[key];
        if (value != null) {
          final parsed = normalize(value.toString());
          if (parsed.isNotEmpty) return parsed;
        }
      }
      return '';
    }

    final raw = clean(photos.toString());
    if (raw.isEmpty) return '';

    if (raw.startsWith('[') || raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        final parsed = _listingPhoto(decoded);
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {}
    }

    if (raw.startsWith('[') && raw.endsWith(']')) {
      final inner = raw.substring(1, raw.length - 1);
      for (final part in inner.split(',')) {
        final parsed = normalize(part);
        if (parsed.isNotEmpty) return parsed;
      }
      return '';
    }

    if (raw.contains(',') && !raw.startsWith('data:image')) {
      for (final part in raw.split(',')) {
        final parsed = normalize(part);
        if (parsed.isNotEmpty) return parsed;
      }
      return '';
    }

    return normalize(raw);
  }

  String _categoryLabel(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'land': return 'Arazi';
      case 'fruit': return 'Meyve';
      case 'animal': return 'Hayvan';
      case 'tree': return 'Ağaç';
      case 'equipment': return 'Ekipman';
      case 'veteriner': return 'Veteriner';
      default: return 'Diğer';
    }
  }

  Color _categoryColor(String? category) {
    switch ((category ?? '').toLowerCase()) {
      case 'land': return const Color(0xFF92400E);
      case 'fruit': return const Color(0xFFD97706);
      case 'animal': return const Color(0xFF0284C7);
      case 'tree': return const Color(0xFF16A34A);
      case 'equipment': return const Color(0xFF6B7280);
      case 'veteriner': return const Color(0xFF7C3AED);
      default: return _FC.primary;
    }
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.white, size: 17),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        ],
      ),
      backgroundColor: _FC.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _FC.bg,
      drawer: UserAppDrawer(
        userData: _currentUserData,
        currentPage: UserDrawerPage.home,
      ),
      body: RefreshIndicator(
        color: _FC.primary,
        backgroundColor: Colors.white,
        onRefresh: _refreshAll,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                      child: _TopBar(
                        userName: _userName,
                        avatarUrl: _avatarUrl,
                        onMenuTap: (ctx) => Scaffold.of(ctx).openDrawer(),
                        avatarFallback: _userName.isNotEmpty
                            ? _userName[0].toUpperCase()
                            : 'N',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Body
                    if (_isLoading)
                      const _LoadingSkeleton()
                    else if (_pageError != null)
                      _ErrorState(
                          message: _pageError!, onRetry: _loadDashboard)
                    else
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Weather Hero ──
                              _WeatherHeroCard(
                                weather: _weatherData ?? {},
                                userName: _userName,
                                isRefreshing: _isRefreshingWeather,
                                onRefresh: _refreshWeatherOnly,
                                weatherIcon: _weatherIcon,
                              ),
                              const SizedBox(height: 24),

                              // ── Bento: Notes + Events ──
                              _SectionHeader(
                                title: 'Son Notlar',
                                actionIcon: Icons.add_rounded,
                                onAction: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserNotesScreen(userData: _currentUserData),
                                  ),
                                ),
                                onMore: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserNotesScreen(userData: _currentUserData),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _NotesBentoGrid(
                                notes: _recentNotes,
                                noteAccent: _noteAccent,
                                relativeTime: _relativeTime,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserNotesScreen(userData: _currentUserData),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // ── Upcoming Events ──
                              _SectionHeader(
                                title: 'Yaklaşan Etkinlikler',
                                onMore: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserCalendarScreen(userData: _currentUserData),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _UpcomingEventsCard(
                                events: _upcomingEvents,
                                noteAccent: _noteAccent,
                                formatEventDate: _formatEventDate,
                                formatNoteTime: _formatNoteTime,
                              ),
                              const SizedBox(height: 24),

                              // ── Marketplace ──
                              _SectionHeader(
                                title: 'İlan Pazarı',
                                onMore: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserMarketplaceScreen(userData: _currentUserData),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _MarketplaceGrid(
                                listings: _featuredListings,
                                listingPhoto: _listingPhoto,
                                categoryLabel: _categoryLabel,
                                categoryColor: _categoryColor,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserMarketplaceScreen(userData: _currentUserData),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                              // ── Günün Tarım İpucu ──
                              const _FarmTipsCard(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Bar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String userName;
  final String avatarUrl;
  final void Function(BuildContext ctx) onMenuTap;
  final String avatarFallback;

  const _TopBar({
    required this.userName,
    required this.avatarUrl,
    required this.onMenuTap,
    required this.avatarFallback,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Hamburger
        Builder(
          builder: (ctx) => Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onMenuTap(ctx),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _FC.border),
                  boxShadow: _FS.subtle,
                ),
                child: const Icon(Icons.menu_rounded, color: _FC.forest, size: 22),
              ),
            ),
          ),
        ),
        const Spacer(),
        // Brand
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_FC.primary, _FC.leaf],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.grass_rounded, color: Colors.white, size: 17),
        ),
        const SizedBox(width: 8),
        const Text(
          'AgriSynth',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: _FC.forest,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        // Avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _FC.primary.withOpacity(0.22), width: 2),
            boxShadow: _FS.subtle,
          ),
          child: ClipOval(
            child: avatarUrl.startsWith('http')
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _AvatarFallbackBox(letter: avatarFallback),
                  )
                : _AvatarFallbackBox(letter: avatarFallback),
          ),
        ),
      ],
    );
  }
}

class _AvatarFallbackBox extends StatelessWidget {
  final String letter;
  const _AvatarFallbackBox({required this.letter});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _FC.paleMint,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: _FC.primary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onMore;

  const _SectionHeader({
    required this.title,
    this.actionIcon,
    this.onAction,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: _FC.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _FC.inkDark,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (actionIcon != null)
          GestureDetector(
            onTap: onAction,
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _FC.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(actionIcon, color: Colors.white, size: 18),
            ),
          ),
        if (onMore != null)
          GestureDetector(
            onTap: onMore,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _FC.paleMint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Tümü →',
                style: TextStyle(
                  color: _FC.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weather Hero Card
// ─────────────────────────────────────────────────────────────────────────────
class _WeatherHeroCard extends StatelessWidget {
  final Map<String, dynamic> weather;
  final String userName;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final IconData Function(dynamic code, {bool isDay}) weatherIcon;

  const _WeatherHeroCard({
    required this.weather,
    required this.userName,
    required this.isRefreshing,
    required this.onRefresh,
    required this.weatherIcon,
  });

  @override
  Widget build(BuildContext context) {
    final hourly = List<Map<String, dynamic>>.from(weather['hourly'] ?? []);
    final bool isDay = (weather['isDay'] ?? true) == true;

    // Dynamic gradient based on day/night and weather
    final List<Color> gradColors = isDay
        ? [const Color(0xFF0E3D22), const Color(0xFF1F6E43), const Color(0xFF2A8C57)]
        : [const Color(0xFF0A1F14), const Color(0xFF0E3D22), const Color(0xFF1A5435)];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradColors,
          stops: const [0.0, 0.5, 1.0],
        ),
        boxShadow: _FS.hero,
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Background decorative elements
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 20,
            child: Icon(
              weatherIcon(weather['code'], isDay: isDay),
              size: 90,
              color: Colors.white.withOpacity(0.07),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: location pill + refresh
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.13),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on_rounded,
                                size: 13, color: Colors.white70),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                (weather['city'] ?? '').toString().toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: isRefreshing ? null : onRefresh,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.10)),
                        ),
                        child: isRefreshing
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded,
                                color: Colors.white70, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Main weather info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Temperature
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                weather['temperature']?.toString() ?? '--',
                                style: const TextStyle(
                                  fontSize: 72,
                                  height: 0.9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -3,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  '°C',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            weather['description']?.toString() ?? 'Hava Durumu',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Large weather icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Icon(
                        weatherIcon(weather['code'], isDay: isDay),
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Greeting
                Text(
                  userName.isNotEmpty
                      ? 'Merhaba $userName, iyi günler!'
                      : 'Hava durumuna göre tarla planını yap.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.72),
                    fontWeight: FontWeight.w500,
                  ),
                ),

                // Hourly forecast
                if (hourly.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    height: 1,
                    color: Colors.white.withOpacity(0.10),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: List.generate(hourly.length, (i) {
                      final item = hourly[i];
                      final isLast = i == hourly.length - 1;
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: isLast ? 0 : 8),
                          padding: const EdgeInsets.symmetric(
                              vertical: 11, horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.07)),
                          ),
                          child: Column(
                            children: [
                              Text(
                                item['time'].toString(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.70),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Icon(
                                weatherIcon(item['code']),
                                color: Colors.white.withOpacity(0.90),
                                size: 18,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${item['temp']}°',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes Bento Grid
// ─────────────────────────────────────────────────────────────────────────────
class _NotesBentoGrid extends StatelessWidget {
  final List<Map<String, dynamic>> notes;
  final Color Function(int?) noteAccent;
  final String Function(dynamic) relativeTime;
  final VoidCallback onTap;

  const _NotesBentoGrid({
    required this.notes,
    required this.noteAccent,
    required this.relativeTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (notes.isEmpty) {
      return _EmptyCard(
        icon: Icons.sticky_note_2_outlined,
        title: 'Henüz not yok',
        subtitle: 'İlk notunu eklediğinde burada görünecek.',
      );
    }

    if (notes.length == 1) {
      return _NoteCard(
        note: notes.first,
        accent: noteAccent(notes.first['color'] as int?),
        timeLabel: relativeTime(notes.first['created_at']),
        onTap: onTap,
        wide: true,
      );
    }

    // 2 notes: bento layout. IntrinsicHeight kaldırıldı;
    // CustomScrollView içinde fazladan layout/semantics hesaplaması yapmasın.
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;

        if (isNarrow) {
          return Column(
            children: [
              _NoteCard(
                note: notes[0],
                accent: noteAccent(notes[0]['color'] as int?),
                timeLabel: relativeTime(notes[0]['created_at']),
                onTap: onTap,
              ),
              const SizedBox(height: 12),
              _NoteCard(
                note: notes[1],
                accent: noteAccent(notes[1]['color'] as int?),
                timeLabel: relativeTime(notes[1]['created_at']),
                onTap: onTap,
                compact: true,
              ),
            ],
          );
        }

        return SizedBox(
          height: 178,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _NoteCard(
                  note: notes[0],
                  accent: noteAccent(notes[0]['color'] as int?),
                  timeLabel: relativeTime(notes[0]['created_at']),
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: _NoteCard(
                  note: notes[1],
                  accent: noteAccent(notes[1]['color'] as int?),
                  timeLabel: relativeTime(notes[1]['created_at']),
                  onTap: onTap,
                  compact: true,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Map<String, dynamic> note;
  final Color accent;
  final String timeLabel;
  final VoidCallback onTap;
  final bool wide;
  final bool compact;

  const _NoteCard({
    required this.note,
    required this.accent,
    required this.timeLabel,
    required this.onTap,
    this.wide = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final double minHeight = wide ? 142 : (compact ? 132 : 156);

    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.15), width: 1.2),
        boxShadow: _FS.card,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(width: 5, color: accent),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 17 : 21,
                  compact ? 12 : 16,
                  compact ? 12 : 16,
                  compact ? 12 : 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _MiniBadge(
                          label: note['note_date'] != null ? 'PLANLI' : 'NOT',
                          color: accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            timeLabel,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: _FC.inkMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      (note['title'] ?? 'Başlıksız Not').toString(),
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15.5,
                        fontWeight: FontWeight.w800,
                        color: _FC.inkDark,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 7),
                      Text(
                        (note['content'] ?? '').toString(),
                        maxLines: wide ? 3 : 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _FC.inkLight,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
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
// Upcoming Events Card
// ─────────────────────────────────────────────────────────────────────────────
class _UpcomingEventsCard extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  final Color Function(int?) noteAccent;
  final String Function(dynamic) formatEventDate;
  final String Function(dynamic) formatNoteTime;

  const _UpcomingEventsCard({
    required this.events,
    required this.noteAccent,
    required this.formatEventDate,
    required this.formatNoteTime,
  });

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _EmptyCard(
        icon: Icons.event_note_rounded,
        title: 'Yaklaşan etkinlik yok',
        subtitle: 'Tarihli bir not eklediğinde burada görünecek.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _FC.border),
        boxShadow: _FS.card,
      ),
      child: Column(
        children: [
          // Header inside card
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _FC.paleMint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.event_rounded,
                      color: _FC.primary, size: 16),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Bugün & Yarın',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _FC.inkLight,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Events list
          ...events.asMap().entries.map((entry) {
            final i = entry.key;
            final event = entry.value;
            final accent = noteAccent(event['color'] as int?);
            final isLast = i == events.length - 1;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: _EventRow(
                    event: event,
                    accent: accent,
                    timeLabel: formatNoteTime(event['note_time']),
                    dateLabel: formatEventDate(event['note_date']),
                    isFirst: i == 0,
                  ),
                ),
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(
                        color: _FC.border, height: 1, thickness: 1),
                  ),
              ],
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final Color accent;
  final String timeLabel;
  final String dateLabel;
  final bool isFirst;

  const _EventRow({
    required this.event,
    required this.accent,
    required this.timeLabel,
    required this.dateLabel,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Time badge
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isFirst ? _FC.primary : _FC.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                timeLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: isFirst ? Colors.white : _FC.inkMid,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Accent dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          // Title + content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (event['title'] ?? 'Planlı Not').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: _FC.inkDark,
                  ),
                ),
                if ((event['content'] ?? '').toString().isNotEmpty)
                  Text(
                    event['content'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _FC.inkLight,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Date badge
          if (dateLabel.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marketplace Grid — 2-column e-commerce style
// ─────────────────────────────────────────────────────────────────────────────
class _MarketplaceGrid extends StatelessWidget {
  final List<Map<String, dynamic>> listings;
  final String Function(dynamic) listingPhoto;
  final String Function(String?) categoryLabel;
  final Color Function(String?) categoryColor;
  final VoidCallback onTap;

  const _MarketplaceGrid({
    required this.listings,
    required this.listingPhoto,
    required this.categoryLabel,
    required this.categoryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (listings.isEmpty) {
      return _EmptyCard(
        icon: Icons.storefront_outlined,
        title: 'Henüz aktif ilan yok',
        subtitle: 'Aktif ilanlar burada görünecek.',
      );
    }

    // 2-column grid
    final rows = <Widget>[];
    for (int i = 0; i < listings.length; i += 2) {
      final left = listings[i];
      final right = i + 1 < listings.length ? listings[i + 1] : null;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ListingCard(
                listing: left,
                photo: listingPhoto(left['photos']),
                category: categoryLabel(left['category']?.toString()),
                catColor: categoryColor(left['category']?.toString()),
                onTap: onTap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: right != null
                  ? _ListingCard(
                      listing: right,
                      photo: listingPhoto(right['photos']),
                      category: categoryLabel(right['category']?.toString()),
                      catColor: categoryColor(right['category']?.toString()),
                      onTap: onTap,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < listings.length) rows.add(const SizedBox(height: 12));
    }

    return Column(children: rows);
  }
}

class _ListingCard extends StatelessWidget {
  final Map<String, dynamic> listing;
  final String photo;
  final String category;
  final Color catColor;
  final VoidCallback onTap;

  const _ListingCard({
    required this.listing,
    required this.photo,
    required this.category,
    required this.catColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = (listing['title'] ?? 'İlan').toString();
    final price = listing['price'] == null ? 'Fiyat yok' : '${listing['price']} ₺';
    final location = (listing['location'] ?? '').toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _FC.border),
        boxShadow: _FS.card,
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 130,
                width: double.infinity,
                child: _ListingPreviewImage(
                  photo: photo,
                  color: catColor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: catColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          color: catColor,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _FC.inkDark,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: _FC.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              price,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: _FC.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 12, color: _FC.inkMuted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: _FC.inkMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListingPreviewImage extends StatelessWidget {
  final String photo;
  final Color color;

  const _ListingPreviewImage({
    required this.photo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final value = photo.trim();

    if (value.startsWith('data:image')) {
      try {
        final commaIndex = value.indexOf(',');
        if (commaIndex != -1) {
          final bytes = base64Decode(value.substring(commaIndex + 1));
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _ListingImagePlaceholder(color: color),
          );
        }
      } catch (_) {
        return _ListingImagePlaceholder(color: color);
      }
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(
        value,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _ListingImagePlaceholder(color: color),
      );
    }

    return _ListingImagePlaceholder(color: color);
  }
}

class _ListingImagePlaceholder extends StatelessWidget {
  final Color color;
  const _ListingImagePlaceholder({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color.withOpacity(0.08),
      child: Center(
        child: Icon(Icons.inventory_2_rounded, size: 36, color: color.withOpacity(0.45)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Empty Card
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _FC.border),
        boxShadow: _FS.subtle,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _FC.paleMint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _FC.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _FC.inkDark,
                    )),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _FC.inkLight,
                      height: 1.35,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Mini Badge
// ─────────────────────────────────────────────────────────────────────────────
class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _MiniBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading Skeleton
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
      child: Column(
        children: [
          _SkeletonBox(height: 260, radius: 32),
          const SizedBox(height: 20),
          _SkeletonBox(height: 130, radius: 24),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _SkeletonBox(height: 120, radius: 22)),
            const SizedBox(width: 12),
            Expanded(child: _SkeletonBox(height: 120, radius: 22)),
          ]),
          const SizedBox(height: 20),
          _SkeletonBox(height: 150, radius: 28),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _SkeletonBox(height: 200, radius: 24)),
            const SizedBox(width: 12),
            Expanded(child: _SkeletonBox(height: 200, radius: 24)),
          ]),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;
  final double radius;
  const _SkeletonBox({required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _FC.border),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error State
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _FC.border),
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 28, color: Color(0xFFE11D48)),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: _FC.inkDark,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: _FC.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Tekrar Dene',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
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

// ─────────────────────────────────────────────────────────────────────────────
// Günün Tarım İpucu — Kaydırmalı kart
// ─────────────────────────────────────────────────────────────────────────────
class _FarmTipsCard extends StatefulWidget {
  const _FarmTipsCard();

  @override
  State<_FarmTipsCard> createState() => _FarmTipsCardState();
}

class _FarmTipsCardState extends State<_FarmTipsCard> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  // ── İpuçları verisi ──────────────────────────────────────────────────
  static const List<_FarmTip> _tips = [
    _FarmTip(
      season: 'İlkbahar',
      seasonIcon: '🌱',
      seasonColor: Color(0xFF16A34A),
      seasonBg: Color(0xFFECFDF5),
      icon: Icons.local_florist_rounded,
      title: 'Fide Sertleştirme',
      body:
          'Domates ve biber fidelerini dışarıya almadan önce 1–2 hafta sertleştirme uygulayın. Gündüzleri gölgede bırakıp geceleri içeri alın.',
    ),
    _FarmTip(
      season: 'Sulama',
      seasonIcon: '💧',
      seasonColor: Color(0xFF0284C7),
      seasonBg: Color(0xFFE0F2FE),
      icon: Icons.water_drop_rounded,
      title: 'Doğru Sulama Zamanı',
      body:
          'Bitkileri sabahın erken saatlerinde sulayın. Gün ortasında sulama yapıldığında su buharlaşır, yapraklarda yanık izi bırakabilir.',
    ),
    _FarmTip(
      season: 'Toprak',
      seasonIcon: '🌍',
      seasonColor: Color(0xFF92400E),
      seasonBg: Color(0xFFFEF3C7),
      icon: Icons.terrain_rounded,
      title: 'Toprak pH Dengesi',
      body:
          'Çoğu tarım bitkisi 6.0–7.0 arası pH değerini sever. Toprağınızı yılda en az bir kez test edin; gerekirse kireç ya da kükürt ekleyin.',
    ),
    _FarmTip(
      season: 'Yaz',
      seasonIcon: '☀️',
      seasonColor: Color(0xFFD97706),
      seasonBg: Color(0xFFFFFBEB),
      icon: Icons.wb_sunny_rounded,
      title: 'Sıcak Stresine Dikkat',
      body:
          'Yüksek sıcaklıkta hayvanlar ve bitkiler strese girer. Gölgelik alanlar oluşturun, su kaynaklarını düzenli kontrol edin.',
    ),
    _FarmTip(
      season: 'Hasat',
      seasonIcon: '🌾',
      seasonColor: Color(0xFF1F6E43),
      seasonBg: Color(0xFFE2F5EA),
      icon: Icons.grass_rounded,
      title: 'Hasat Zamanlaması',
      body:
          'Tahılları hasat etmeden önce nem oranının %14\'ün altına inmesini bekleyin. Erken hasat çürümeyi, geç hasat kırılmayı artırır.',
    ),
    _FarmTip(
      season: 'Kış',
      seasonIcon: '❄️',
      seasonColor: Color(0xFF2563EB),
      seasonBg: Color(0xFFEFF6FF),
      icon: Icons.ac_unit_rounded,
      title: 'Kış Hazırlığı',
      body:
          'Sonbahar sonunda tarla yüzeyine organik malç (saman, yaprak) serpin. Bu uygulama toprağı dondan korur ve bahar için besin sağlar.',
    ),
    _FarmTip(
      season: 'Parazit',
      seasonIcon: '🛡️',
      seasonColor: Color(0xFF7C3AED),
      seasonBg: Color(0xFFF5F3FF),
      icon: Icons.bug_report_rounded,
      title: 'Doğal Zararlı Kontrolü',
      body:
          'Kimyasala başvurmadan önce sarımsak suyu veya neem yağı spreyi deneyin. Faydalı böcekleri (uğur böceği, yeşil kurtçuk) koruyun.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _tips.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tip = _tips[_currentPage];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Başlık ──────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: tip.seasonColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.wb_sunny_rounded,
                size: 20, color: _FC.amber),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Tarım İpucuları',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _FC.inkDark,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            // Sayfa sayacı
            Text(
              '${_currentPage + 1} / ${_tips.length}',
              style: const TextStyle(
                color: _FC.inkMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Ana kart (PageView) ──────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          decoration: BoxDecoration(
            color: tip.seasonBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: tip.seasonColor.withOpacity(0.20),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: tip.seasonColor.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // PageView içeriği
              SizedBox(
                height: 156,
                child: PageView.builder(
                  controller: _pageCtrl,
                  itemCount: _tips.length,
                  onPageChanged: (i) {
                    if (mounted && _currentPage != i) {
                      setState(() => _currentPage = i);
                    }
                  },
                  itemBuilder: (context, index) {
                    final t = _tips[index];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sezon + başlık satırı
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: t.seasonColor.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(t.icon,
                                    color: t.seasonColor, size: 20),
                              ),
                              const SizedBox(width: 11),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        t.seasonIcon,
                                        style:
                                            const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        t.season.toUpperCase(),
                                        style: TextStyle(
                                          color: t.seasonColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.7,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    t.title,
                                    style: const TextStyle(
                                      color: _FC.inkDark,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // İpucu metni
                          Text(
                            t.body,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _FC.inkMid,
                              fontSize: 13,
                              height: 1.55,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // ── Alt bar: oklar + dot indikatörler ───────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    // Sol ok
                    _TipNavBtn(
                      icon: Icons.chevron_left_rounded,
                      color: tip.seasonColor,
                      enabled: _currentPage > 0,
                      onTap: _prevPage,
                    ),
                    const SizedBox(width: 10),
                    // Dot indikatörler
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_tips.length, (i) {
                          final active = i == _currentPage;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 2.5),
                            width: active ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? _tips[_currentPage].seasonColor
                                  : _FC.inkMuted.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Sağ ok
                    _TipNavBtn(
                      icon: Icons.chevron_right_rounded,
                      color: tip.seasonColor,
                      enabled: _currentPage < _tips.length - 1,
                      onTap: _nextPage,
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

// ── Ok butonu ─────────────────────────────────────────────────────────────────
class _TipNavBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _TipNavBtn({
    required this.icon,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? color.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          icon,
          color: enabled ? color : _FC.inkMuted.withOpacity(0.30),
          size: 22,
        ),
      ),
    );
  }
}

// ── Veri modeli ───────────────────────────────────────────────────────────────
class _FarmTip {
  final String season;
  final String seasonIcon;
  final Color seasonColor;
  final Color seasonBg;
  final IconData icon;
  final String title;
  final String body;

  const _FarmTip({
    required this.season,
    required this.seasonIcon,
    required this.seasonColor,
    required this.seasonBg,
    required this.icon,
    required this.title,
    required this.body,
  });
}