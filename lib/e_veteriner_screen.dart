import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'farmer_app_drawer.dart';

import 'supabase_service.dart';

class EVeterinerScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const EVeterinerScreen({super.key, required this.userData});

  @override
  State<EVeterinerScreen> createState() => _EVeterinerScreenState();
}

class _EVeterinerScreenState extends State<EVeterinerScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF065F46);
  static const Color lightBackground = Color(0xFFF6FAF7);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  final TextEditingController _searchController = TextEditingController();

  bool _loadingDoctors = true;
  bool _loadingAppointments = false;
  bool _savingAppointment = false;
  int _selectedTab = 0;
  String _searchQuery = '';

  List<Map<String, dynamic>> _doctorListings = [];
  List<Map<String, dynamic>> _appointments = [];
  final Set<String> _deletingAppointmentIds = <String>{};

  String get _currentUserId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    if (fromData.isNotEmpty) return fromData;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _loadDoctors();
    _loadAppointments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredDoctors {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return _doctorListings;

    return _doctorListings.where((doctor) {
      final name = (doctor['doctorName'] ?? '').toString().toLowerCase();
      final title = (doctor['title'] ?? '').toString().toLowerCase();
      final description = (doctor['description'] ?? '').toString().toLowerCase();
      final city = (doctor['city'] ?? '').toString().toLowerCase();
      final location = (doctor['location'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          title.contains(query) ||
          description.contains(query) ||
          city.contains(query) ||
          location.contains(query);
    }).toList();
  }

  Future<void> _refresh() async {
    await Future.wait([_loadDoctors(), _loadAppointments()]);
  }

  Future<void> _loadDoctors() async {
    if (mounted) setState(() => _loadingDoctors = true);

    try {
      final rows = await SupabaseService()
          .client
          .from('listings')
          .select(
            'id,user_id,title,description,location,photos,category,is_active,created_at',
          )
          .eq('is_active', true)
          .eq('category', 'veteriner')
          .order('created_at', ascending: false);

      final listings = List<Map<String, dynamic>>.from(rows);
      final doctorIds = listings
          .map((row) => (row['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usersById = <String, Map<String, dynamic>>{};
      if (doctorIds.isNotEmpty) {
        try {
          final users = await SupabaseService()
              .client
              .from('users')
              .select('id, ad, soyad, username, email, telefon, sehir, rol, avatar_url')
              .inFilter('id', doctorIds);

          for (final raw in List<Map<String, dynamic>>.from(users)) {
            final id = (raw['id'] ?? '').toString();
            if (id.isNotEmpty) usersById[id] = raw;
          }
        } catch (e) {
          debugPrint('Veteriner kullanıcı bilgisi alınamadı: $e');
        }
      }

      final normalized = <Map<String, dynamic>>[];
      for (final listing in listings) {
        final doctorId = (listing['user_id'] ?? '').toString();
        final user = usersById[doctorId] ?? <String, dynamic>{};
        final role = (user['rol'] ?? '').toString().toLowerCase().trim();

        // Eski kayıtlarda rol boş olabilir; listing kategorisi veteriner olduğu için listeye alıyoruz.
        if (role.isNotEmpty && role != 'doktor') continue;

        normalized.add({
          ...listing,
          'doctorId': doctorId,
          'doctorName': _buildUserName(user),
          'doctorAvatar': (user['avatar_url'] ?? '').toString(),
          'doctorEmail': (user['email'] ?? '').toString(),
          'doctorPhone': (user['telefon'] ?? '').toString(),
          'city': (user['sehir'] ?? listing['location'] ?? '').toString(),
          'roleLabel': 'Veteriner',
          'photosList': _parsePhotos(listing['photos']),
        });
      }

      if (!mounted) return;
      setState(() => _doctorListings = normalized);
    } catch (e) {
      debugPrint('Veteriner ilanları yüklenemedi: $e');
      if (mounted) {
        _showSnackBar('Veteriner ilanları yüklenirken hata oluştu.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _loadingDoctors = false);
    }
  }

  Future<void> _loadAppointments() async {
    final userId = _currentUserId;
    if (userId.isEmpty) return;

    if (mounted) setState(() => _loadingAppointments = true);

    try {
      final rows = await SupabaseService()
          .client
          .from('appointments')
          .select(
            'id,created_at,farmer_id,doctor_id,appointment_date,appointment_time,location_type,status,animal_details,notes',
          )
          .eq('farmer_id', userId)
          .order('created_at', ascending: false);

      final appointmentRows = List<Map<String, dynamic>>.from(rows);
      final doctorIds = appointmentRows
          .map((row) => (row['doctor_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usersById = <String, Map<String, dynamic>>{};
      if (doctorIds.isNotEmpty) {
        final users = await SupabaseService()
            .client
            .from('users')
            .select('id, ad, soyad, avatar_url, telefon, email, sehir, rol')
            .inFilter('id', doctorIds);

        for (final raw in List<Map<String, dynamic>>.from(users)) {
          final id = (raw['id'] ?? '').toString();
          if (id.isNotEmpty) usersById[id] = raw;
        }
      }

      final enriched = appointmentRows.map((appointment) {
        final doctor = usersById[(appointment['doctor_id'] ?? '').toString()] ?? {};
        return {
          ...appointment,
          'doctor': doctor,
          'doctorName': _buildUserName(doctor),
          'doctorAvatar': (doctor['avatar_url'] ?? '').toString(),
        };
      }).toList();

      if (!mounted) return;
      setState(() => _appointments = enriched);
    } catch (e) {
      debugPrint('Randevular yüklenemedi: $e');
      if (mounted) {
        _showSnackBar('Randevular yüklenirken hata oluştu.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _loadingAppointments = false);
    }
  }

  String _buildUserName(Map<String, dynamic> user) {
    final ad = (user['ad'] ?? '').toString().trim();
    final soyad = (user['soyad'] ?? '').toString().trim();
    final full = '$ad $soyad'.trim();
    if (full.isNotEmpty) return full;
    final username = (user['username'] ?? '').toString().trim();
    return username.isEmpty ? 'Veteriner' : username;
  }

  List<String> _parsePhotos(dynamic raw) {
    if (raw == null) return [];
    final value = raw.toString().trim();
    if (value.isEmpty) return [];

    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}

    if (value.contains('\n')) {
      return value.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    // data:image base64 içinde virgül olduğu için önce onu ayırmıyoruz.
    if (!value.startsWith('data:image') && value.contains(',')) {
      return value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    return [value];
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse((value ?? '').toString());
    if (date == null) return 'Tarih yok';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  String _formatStatus(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'approved':
        return 'Onaylandı';
      case 'rejected':
        return 'Reddedildi';
      default:
        return 'Beklemede';
    }
  }

  Color _statusColor(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'approved':
        return primaryGreen;
      case 'rejected':
        return Colors.red.shade600;
      default:
        return Colors.orange.shade700;
    }
  }

  String _locationTypeLabel(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'clinic':
        return 'Klinikte';
      case 'farm':
      default:
        return 'Çiftlikte';
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _confirmDeleteAppointment(Map<String, dynamic> appointment) async {
    final appointmentId = (appointment['id'] ?? '').toString().trim();
    if (appointmentId.isEmpty) {
      _showSnackBar('Randevu bilgisi bulunamadı.', isError: true);
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: !_deletingAppointmentIds.contains(appointmentId),
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: cardWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
          actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          title: const Text(
            'Randevu silinsin mi?',
            style: TextStyle(
              color: darkText,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          content: Text(
            'Bu randevu talebi kalıcı olarak silinecek. Bu işlem geri alınamaz.',
            style: TextStyle(
              color: mutedText.withOpacity(0.95),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              style: TextButton.styleFrom(
                foregroundColor: mutedText,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Vazgeç',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Sil'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteAppointment(appointmentId);
    }
  }

  Future<void> _deleteAppointment(String appointmentId) async {
    final userId = _currentUserId;
    if (userId.isEmpty) {
      _showSnackBar('Oturum bilgisi bulunamadı.', isError: true);
      return;
    }

    if (_deletingAppointmentIds.contains(appointmentId)) return;

    if (mounted) {
      setState(() {
        _deletingAppointmentIds.add(appointmentId);
      });
    }

    try {
      await SupabaseService()
          .client
          .from('appointments')
          .delete()
          .eq('id', appointmentId)
          .eq('farmer_id', userId)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() {
        _appointments.removeWhere((item) => (item['id'] ?? '').toString() == appointmentId);
      });
      _showSnackBar('Randevu talebi silindi.');
    } catch (e) {
      debugPrint('Randevu silme hatası: $e');
      if (mounted) {
        _showSnackBar('Randevu silinemedi: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingAppointmentIds.remove(appointmentId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final doctors = _filteredDoctors;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: lightBackground,
      drawer: FarmerAppDrawer(
        userData: widget.userData,
        currentPage: FarmerDrawerPage.eVeteriner,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primaryGreen,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 22),
                      _buildHeader(),
                      const SizedBox(height: 18),
                      _buildTabSwitcher(),
                      const SizedBox(height: 16),
                      if (_selectedTab == 0) ...[
                        _buildSearchBar(),
                        const SizedBox(height: 16),
                        if (_loadingDoctors)
                          _buildLoadingList()
                        else if (doctors.isEmpty)
                          _buildEmptyState(
                            icon: Icons.medical_services_rounded,
                            title: 'Veteriner ilanı bulunamadı',
                            message:
                                'Aktif veteriner ilanı yoksa burada hekim görünmez. Veterinerlerin ilan kategorisi “veteriner” olmalı.',
                          )
                        else
                          Column(
                            children: doctors.map(_buildDoctorCard).toList(),
                          ),
                      ] else ...[
                        if (_loadingAppointments)
                          _buildLoadingList()
                        else if (_appointments.isEmpty)
                          _buildEmptyState(
                            icon: Icons.calendar_month_rounded,
                            title: 'Henüz randevu talebin yok',
                            message:
                                'Hekim Bul sekmesinden veteriner seçip randevu talebi oluşturabilirsin.',
                          )
                        else
                          Column(
                            children: _appointments.map(_buildAppointmentCard).toList(),
                          ),
                      ],
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        _roundIconButton(
          icon: Icons.menu_rounded,
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: const [
              Icon(Icons.medical_services_rounded, color: darkGreen, size: 23),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'E-Veteriner',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundIconButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: cardWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: darkText, size: 22),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            top: -10,
            child: Icon(Icons.local_hospital_rounded, size: 130, color: Colors.white.withOpacity(0.10)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pets_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 22),
              const Text(
                'Veteriner desteğini\nhızlıca planla',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1.12,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Veteriner ilanlarını incele, uygun hekimden randevu talebi oluştur ve durumunu buradan takip et.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.90),
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _tabButton('Hekim Bul', 0),
          _tabButton('Randevularım', 1),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: selected ? primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : mutedText,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Veteriner adı, hizmet veya şehir ara...',
          hintStyle: TextStyle(color: mutedText.withOpacity(0.8), fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: darkText),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => _searchController.clear(),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        ),
      ),
    );
  }

  Widget _buildDoctorCard(Map<String, dynamic> doctor) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _avatar(
                  url: (doctor['doctorAvatar'] ?? '').toString(),
                  name: (doctor['doctorName'] ?? 'Veteriner').toString(),
                  size: 70,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (doctor['doctorName'] ?? 'Veteriner').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 18.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _roleChip('Veteriner'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 17, color: mutedText),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              ((doctor['city'] ?? '').toString().trim().isEmpty)
                                  ? 'Şehir belirtilmemiş'
                                  : (doctor['city'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: mutedText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE2E8F0)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_hospital_outlined, color: darkGreen, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (doctor['title'] ?? 'Veteriner Hizmeti').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: darkText,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFE2E8F0)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _openDoctorProfile(doctor),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: darkText,
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'Profili İncele',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _openAppointmentSheet(doctor),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'Randevu Al',
                      style: TextStyle(fontWeight: FontWeight.w900),
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

  Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
    final status = (appointment['status'] ?? 'pending').toString();
    final appointmentId = (appointment['id'] ?? '').toString();
    final isDeleting = _deletingAppointmentIds.contains(appointmentId);
    final doctor = Map<String, dynamic>.from(appointment['doctor'] ?? {});
    final animalDetails = _parseAnimalDetails(appointment['animal_details']);

    return Stack(
      children: [
        AnimatedOpacity(
          opacity: isDeleting ? 0.55 : 1,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _avatar(
                      url: (doctor['avatar_url'] ?? '').toString(),
                      name: (appointment['doctorName'] ?? 'Veteriner').toString(),
                      size: 54,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (appointment['doctorName'] ?? 'Veteriner').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: darkText,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Veteriner',
                            style: TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        _formatStatus(status),
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      tooltip: 'Randevu işlemleri',
                      enabled: !isDeleting,
                      color: cardWhite,
                      elevation: 10,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      icon: const Icon(Icons.more_vert_rounded, color: mutedText),
                      onSelected: (value) {
                        if (value == 'delete') {
                          _confirmDeleteAppointment(appointment);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, color: Colors.red.shade600, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                'Randevuyu Sil',
                                style: TextStyle(
                                  color: Colors.red.shade600,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _infoRow(Icons.calendar_month_rounded, 'Tarih', _formatDate(appointment['appointment_date'])),
                const SizedBox(height: 9),
                _infoRow(Icons.access_time_rounded, 'Saat', (appointment['appointment_time'] ?? '').toString()),
                const SizedBox(height: 9),
                _infoRow(
                  Icons.place_outlined,
                  'Yer',
                  _locationTypeLabel((appointment['location_type'] ?? '').toString()),
                ),
                if (animalDetails.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: animalDetails.map((animal) {
                      final type = (animal['type'] ?? 'Hayvan').toString();
                      final count = (animal['count'] ?? '').toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          count.isEmpty ? type : '$type • $count',
                          style: const TextStyle(
                            color: darkText,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                finalNotes(appointment),
              ],
            ),
          ),
        ),
        if (isDeleting)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardWhite,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: primaryGreen),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget finalNotes(Map<String, dynamic> appointment) {
    final notes = (appointment['notes'] ?? '').toString().trim();
    if (notes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          notes,
          style: const TextStyle(
            color: mutedText,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _parseAnimalDetails(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is List) return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    return [];
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: mutedText),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            color: mutedText,
            fontWeight: FontWeight.w800,
            fontSize: 13.5,
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: darkText,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _roleChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, color: primaryGreen, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: primaryGreen,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar({required String url, required String name, required double size}) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'V';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _imageProviderWidget(url, fallback: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: darkGreen,
            fontSize: size * 0.40,
            fontWeight: FontWeight.w900,
          ),
        ),
      )),
    );
  }

  Widget _imageProviderWidget(String raw, {required Widget fallback, BoxFit fit = BoxFit.cover}) {
    final value = raw.trim();
    if (value.isEmpty) return fallback;

    if (value.startsWith('data:image')) {
      try {
        final base64Part = value.contains(',') ? value.split(',').last : value;
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, fit: fit, errorBuilder: (_, __, ___) => fallback);
      } catch (_) {
        return fallback;
      }
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Image.network(value, fit: fit, errorBuilder: (_, __, ___) => fallback);
    }

    return fallback;
  }

  Widget _buildLoadingList() {
    return Column(
      children: List.generate(
        3,
        (index) => Container(
          height: 170,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: cardWhite,
            borderRadius: BorderRadius.circular(26),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.10),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, color: primaryGreen, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: darkText, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: mutedText, fontWeight: FontWeight.w600, height: 1.45),
          ),
        ],
      ),
    );
  }

  void _openDoctorProfile(Map<String, dynamic> doctor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DoctorProfilePage(
          doctor: doctor,
          onAppointment: () => _openAppointmentSheet(doctor),
          avatarBuilder: (url, name, size) => _avatar(url: url, name: name, size: size),
        ),
      ),
    );
  }

  Future<void> _openAppointmentSheet(Map<String, dynamic> doctor) async {
    if (_currentUserId.isEmpty) {
      _showSnackBar('Oturum bilgisi bulunamadı.', isError: true);
      return;
    }

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AppointmentRequestPage(
          doctor: doctor,
          farmerId: _currentUserId,
        ),
      ),
    );

    if (!mounted) return;

    if (created == true) {
      await _loadAppointments();
      if (!mounted) return;
      setState(() => _selectedTab = 1);
      _showSnackBar('Randevu talebin veterinere gönderildi.');
    }
  }

  Widget _pickerBox({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: mutedText),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: darkText, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectChip({required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? primaryGreen.withOpacity(0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? primaryGreen : const Color(0xFFE2E8F0), width: 1.3),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? darkGreen : darkText,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primaryGreen, width: 1.4),
        ),
      ),
    );
  }

  Future<void> _createAppointment({
    required Map<String, dynamic> doctor,
    required DateTime date,
    required TimeOfDay time,
    required String locationType,
    required String animalType,
    required String animalCount,
    required String notes,
  }) async {
    if (mounted) setState(() => _savingAppointment = true);

    try {
      final animalDetails = <Map<String, dynamic>>[];
      if (animalType.trim().isNotEmpty || animalCount.trim().isNotEmpty) {
        animalDetails.add({
          'type': animalType.trim(),
          'count': int.tryParse(animalCount.trim()) ?? animalCount.trim(),
        });
      }

      await SupabaseService().client.from('appointments').insert({
        'farmer_id': _currentUserId,
        'doctor_id': (doctor['doctorId'] ?? doctor['user_id']).toString(),
        'appointment_date': _dateOnly(date),
        'appointment_time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        'location_type': locationType,
        'status': 'pending',
        'animal_details': animalDetails,
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      });

      await _loadAppointments();
      if (!mounted) return;
      setState(() => _selectedTab = 1);
      _showSnackBar('Randevu talebin veterinere gönderildi.');
    } catch (e) {
      debugPrint('Randevu oluşturma hatası: $e');
      if (mounted) {
        _showSnackBar('Randevu talebi oluşturulamadı: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _savingAppointment = false);
    }
  }

  String _dateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}


class _AppointmentRequestPage extends StatefulWidget {
  final Map<String, dynamic> doctor;
  final String farmerId;

  const _AppointmentRequestPage({
    required this.doctor,
    required this.farmerId,
  });

  @override
  State<_AppointmentRequestPage> createState() => _AppointmentRequestPageState();
}

class _AppointmentRequestPageState extends State<_AppointmentRequestPage> {
  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF065F46);
  static const Color lightBackground = Color(0xFFF6FAF7);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  final TextEditingController _animalTypeController = TextEditingController();
  final TextEditingController _animalCountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _locationType = 'farm';
  bool _saving = false;

  @override
  void dispose() {
    _animalTypeController.dispose();
    _animalCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _doctorName => (widget.doctor['doctorName'] ?? 'Veteriner').toString();

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryGreen),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 10, minute: 0),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryGreen),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  String _dateOnly(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_saving) return;

    if (_selectedDate == null) {
      _showSnackBar('Lütfen randevu tarihi seç.', isError: true);
      return;
    }

    if (_selectedTime == null) {
      _showSnackBar('Lütfen randevu saati seç.', isError: true);
      return;
    }

    if (widget.farmerId.trim().isEmpty) {
      _showSnackBar('Oturum bilgisi bulunamadı.', isError: true);
      return;
    }

    final doctorId = (widget.doctor['doctorId'] ?? widget.doctor['user_id'] ?? '').toString().trim();
    if (doctorId.isEmpty) {
      _showSnackBar('Veteriner bilgisi bulunamadı.', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final animalDetails = <Map<String, dynamic>>[];
      final animalType = _animalTypeController.text.trim();
      final animalCount = _animalCountController.text.trim();

      if (animalType.isNotEmpty || animalCount.isNotEmpty) {
        animalDetails.add({
          'type': animalType,
          'count': int.tryParse(animalCount) ?? animalCount,
        });
      }

      await SupabaseService().client.from('appointments').insert({
        'farmer_id': widget.farmerId,
        'doctor_id': doctorId,
        'appointment_date': _dateOnly(_selectedDate!),
        'appointment_time': _formatTime(_selectedTime!),
        'location_type': _locationType,
        'status': 'pending',
        'animal_details': animalDetails,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      }).timeout(const Duration(seconds: 25));

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Randevu oluşturma hatası: $e');
      if (mounted) {
        _showSnackBar('Randevu talebi oluşturulamadı: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: lightBackground,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Material(
                      color: cardWhite,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: _saving ? null : () => Navigator.pop(context, false),
                        borderRadius: BorderRadius.circular(18),
                        child: const SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(Icons.arrow_back_ios_new_rounded, color: darkText),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Randevu Oluştur',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: darkText,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            _doctorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: mutedText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF047857)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: primaryGreen.withOpacity(0.18),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.calendar_month_rounded, color: Colors.white, size: 38),
                            SizedBox(height: 16),
                            Text(
                              'Randevu talebini oluştur',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Talep veterinere beklemede olarak düşer. Veteriner uygun görürse onaylar veya reddeder.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      _sectionCard(
                        title: 'Tarih ve saat',
                        icon: Icons.schedule_rounded,
                        child: Row(
                          children: [
                            Expanded(
                              child: _pickerBox(
                                label: 'Tarih',
                                value: _selectedDate == null ? 'Tarih seç' : _formatDate(_selectedDate!),
                                icon: Icons.calendar_month_rounded,
                                onTap: _saving ? null : _pickDate,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _pickerBox(
                                label: 'Saat',
                                value: _selectedTime == null ? 'Saat seç' : _formatTime(_selectedTime!),
                                icon: Icons.access_time_rounded,
                                onTap: _saving ? null : _pickTime,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        title: 'Randevu yeri',
                        icon: Icons.place_outlined,
                        child: Row(
                          children: [
                            Expanded(
                              child: _selectChip(
                                label: 'Çiftlikte',
                                selected: _locationType == 'farm',
                                onTap: _saving ? null : () => setState(() => _locationType = 'farm'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _selectChip(
                                label: 'Klinikte',
                                selected: _locationType == 'clinic',
                                onTap: _saving ? null : () => setState(() => _locationType = 'clinic'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        title: 'Hayvan bilgisi',
                        icon: Icons.pets_rounded,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _textField(
                                controller: _animalTypeController,
                                label: 'Hayvan türü',
                                hint: 'Örn: İnek',
                                enabled: !_saving,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _textField(
                                controller: _animalCountController,
                                label: 'Adet',
                                hint: '10',
                                enabled: !_saving,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        title: 'Not',
                        icon: Icons.notes_rounded,
                        child: _textField(
                          controller: _notesController,
                          label: 'Ek bilgi',
                          hint: 'Hastalık belirtisi, aciliyet veya ek bilgi yaz...',
                          enabled: !_saving,
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(_saving ? 'Gönderiliyor...' : 'Randevu Talebi Gönder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(58),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
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
      ),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: darkGreen, size: 21),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _pickerBox({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: mutedText),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(color: mutedText, fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: darkText, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectChip({required String label, required bool selected, required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? primaryGreen.withOpacity(0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? primaryGreen : const Color(0xFFE2E8F0), width: 1.3),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? darkGreen : darkText,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primaryGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _DoctorProfilePage extends StatelessWidget {
  final Map<String, dynamic> doctor;
  final VoidCallback onAppointment;
  final Widget Function(String url, String name, double size) avatarBuilder;

  const _DoctorProfilePage({
    required this.doctor,
    required this.onAppointment,
    required this.avatarBuilder,
  });

  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF065F46);
  static const Color lightBackground = Color(0xFFF6FAF7);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  @override
  Widget build(BuildContext context) {
    final name = (doctor['doctorName'] ?? 'Veteriner').toString();
    final description = (doctor['description'] ?? '').toString().trim();
    final city = (doctor['city'] ?? '').toString().trim();
    final phone = (doctor['doctorPhone'] ?? '').toString().trim();
    final email = (doctor['doctorEmail'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: lightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Material(
                    color: cardWhite,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(18),
                      child: const SizedBox(
                        width: 52,
                        height: 52,
                        child: Icon(Icons.arrow_back_ios_new_rounded, color: darkText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Profil Bilgisi',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardWhite,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 120,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF047857)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -42),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: Column(
                          children: [
                            avatarBuilder((doctor['doctorAvatar'] ?? '').toString(), name, 92),
                            const SizedBox(height: 12),
                            Text(
                              name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: darkText,
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: primaryGreen.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'Veteriner',
                                style: TextStyle(color: primaryGreen, fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                      child: Column(
                        children: [
                          _profileInfoRow(Icons.local_hospital_rounded, 'Hizmet', (doctor['title'] ?? 'Veteriner Hizmeti').toString()),
                          _profileInfoRow(Icons.location_on_outlined, 'Şehir', city.isEmpty ? 'Belirtilmemiş' : city),
                          if (phone.isNotEmpty) _profileInfoRow(Icons.phone_outlined, 'Telefon', phone),
                          if (email.isNotEmpty) _profileInfoRow(Icons.email_outlined, 'E-posta', email),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: mutedText,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.45,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'Açıklama: ',
                                    style: TextStyle(color: darkText, fontWeight: FontWeight.w900),
                                  ),
                                  TextSpan(
                                    text: description.isEmpty
                                        ? 'Açıklama bilgisi eklenmemiş.'
                                        : description,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                Future.delayed(const Duration(milliseconds: 120), onAppointment);
                              },
                              icon: const Icon(Icons.calendar_month_rounded),
                              label: const Text('Randevu Al'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryGreen,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(56),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileInfoRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: darkGreen, size: 20),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(color: mutedText, fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
