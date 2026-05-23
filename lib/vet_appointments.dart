import 'dart:convert';

import 'package:flutter/material.dart';

import 'supabase_service.dart';
import 'vet_app_drawer.dart';

class VetAppointmentsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const VetAppointmentsScreen({super.key, required this.userData});

  @override
  State<VetAppointmentsScreen> createState() => _VetAppointmentsScreenState();
}

class _VetAppointmentsScreenState extends State<VetAppointmentsScreen> {
  static const Color primaryBlue = Color(0xFF1D4ED8);
  static const Color darkBlue = Color(0xFF13244A);
  static const Color lightBackground = Color(0xFFFAFBFF);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  bool _isLoading = true;
  String _selectedStatus = 'pending';
  List<Map<String, dynamic>> _appointments = [];
  final Set<String> _updatingIds = <String>{};
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String get _doctorId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    if (fromData.isNotEmpty) return fromData;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    final doctorId = _doctorId;
    if (doctorId.isEmpty) return;

    if (mounted) setState(() => _isLoading = true);

    try {
      final rows = await SupabaseService()
          .client
          .from('appointments')
          .select(
            'id,created_at,farmer_id,doctor_id,appointment_date,appointment_time,location_type,status,animal_details,notes',
          )
          .eq('doctor_id', doctorId)
          .eq('status', _selectedStatus)
          .order('created_at', ascending: false);

      final appointmentRows = List<Map<String, dynamic>>.from(rows);
      final farmerIds = appointmentRows
          .map((row) => (row['farmer_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final farmersById = <String, Map<String, dynamic>>{};
      if (farmerIds.isNotEmpty) {
        final users = await SupabaseService()
            .client
            .from('users')
            .select('id, ad, soyad, username, telefon, email, sehir, rol, avatar_url')
            .inFilter('id', farmerIds);

        for (final user in List<Map<String, dynamic>>.from(users)) {
          final id = (user['id'] ?? '').toString();
          if (id.isNotEmpty) farmersById[id] = user;
        }
      }

      final enriched = appointmentRows.map((row) {
        final farmer = farmersById[(row['farmer_id'] ?? '').toString()] ?? <String, dynamic>{};
        return {
          ...row,
          'farmer': farmer,
          'farmerName': _buildUserName(farmer),
        };
      }).toList();

      if (mounted) setState(() => _appointments = enriched);
    } catch (e) {
      debugPrint('Veteriner randevuları yüklenemedi: $e');
      if (mounted) _showSnackBar('Randevu talepleri yüklenemedi.', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String appointmentId, String status) async {
    if (_updatingIds.contains(appointmentId)) return;

    setState(() => _updatingIds.add(appointmentId));
    try {
      await SupabaseService()
          .client
          .from('appointments')
          .update({'status': status}).eq('id', appointmentId);

      await _loadAppointments();
      if (mounted) {
        _showSnackBar(status == 'approved' ? 'Randevu onaylandı.' : 'Randevu reddedildi.');
      }
    } catch (e) {
      debugPrint('Randevu durum güncelleme hatası: $e');
      if (mounted) _showSnackBar('Randevu durumu güncellenemedi.', isError: true);
    } finally {
      if (mounted) setState(() => _updatingIds.remove(appointmentId));
    }
  }

  String _buildUserName(Map<String, dynamic> user) {
    final ad = (user['ad'] ?? '').toString().trim();
    final soyad = (user['soyad'] ?? '').toString().trim();
    final full = '$ad $soyad'.trim();
    if (full.isNotEmpty) return full;
    final username = (user['username'] ?? '').toString().trim();
    return username.isEmpty ? 'Çiftçi' : username;
  }

  List<Map<String, dynamic>> _parseAnimalDetails(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is List) {
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }

  String _formatDate(dynamic raw) {
    final dt = DateTime.tryParse((raw ?? '').toString());
    if (dt == null) return 'Tarih yok';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  }

  String _locationLabel(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'clinic':
        return 'Klinikte';
      case 'farm':
      default:
        return 'Çiftlikte';
    }
  }

  String _statusLabel(String raw) {
    switch (raw) {
      case 'approved':
        return 'Onaylanan';
      case 'rejected':
        return 'Reddedilen';
      default:
        return 'Bekleyen';
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: lightBackground,
      drawer: VetAppDrawer(
        userData: widget.userData,
        currentPage: VetDrawerPage.appointments,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primaryBlue,
          onRefresh: _loadAppointments,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(context),
                      const SizedBox(height: 22),
                      _buildHeader(),
                      const SizedBox(height: 18),
                      _buildStatusTabs(),
                      const SizedBox(height: 16),
                      if (_isLoading)
                        Column(
                          children: List.generate(3, (_) => _loadingCard()),
                        )
                      else if (_appointments.isEmpty)
                        _emptyState()
                      else
                        Column(children: _appointments.map(_appointmentCard).toList()),
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

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        Material(
          color: cardWhite,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 52,
              height: 52,
              child: Icon(Icons.menu_rounded, color: darkText),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Randevu Talepleri',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: darkBlue,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 44),
          SizedBox(height: 18),
          Text(
            'Çiftçilerden gelen\nrandevu istekleri',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.12,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Bekleyen talepleri inceleyip uygun olanları onaylayabilir veya reddedebilirsin.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: ['pending', 'approved', 'rejected'].map((status) {
          final selected = _selectedStatus == status;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedStatus = status);
                _loadAppointments();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? primaryBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: selected ? Colors.white : mutedText,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> appointment) {
    final farmer = Map<String, dynamic>.from(appointment['farmer'] ?? {});
    final farmerName = (appointment['farmerName'] ?? 'Çiftçi').toString();
    final animalDetails = _parseAnimalDetails(appointment['animal_details']);
    final status = (appointment['status'] ?? 'pending').toString();
    final isUpdating = _updatingIds.contains((appointment['id'] ?? '').toString());

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(26),
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
              _avatar((farmer['avatar_url'] ?? '').toString(), farmerName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farmerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: darkText, fontSize: 16.5, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (farmer['sehir'] ?? 'Şehir belirtilmemiş').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow(Icons.calendar_month_rounded, 'Tarih', _formatDate(appointment['appointment_date'])),
          const SizedBox(height: 8),
          _infoRow(Icons.access_time_rounded, 'Saat', (appointment['appointment_time'] ?? '').toString()),
          const SizedBox(height: 8),
          _infoRow(Icons.place_outlined, 'Yer', _locationLabel((appointment['location_type'] ?? '').toString())),
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
                    style: const TextStyle(color: darkText, fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                );
              }).toList(),
            ),
          ],
          if ((appointment['notes'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                (appointment['notes'] ?? '').toString(),
                style: const TextStyle(color: mutedText, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isUpdating ? null : () => _updateStatus((appointment['id'] ?? '').toString(), 'rejected'),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reddet'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade100),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isUpdating ? null : () => _updateStatus((appointment['id'] ?? '').toString(), 'approved'),
                    icon: isUpdating
                        ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded),
                    label: const Text('Onayla'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatar(String url, String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'Ç';
    final value = url.trim();

    Widget child = Center(
      child: Text(initial, style: const TextStyle(color: darkBlue, fontSize: 22, fontWeight: FontWeight.w900)),
    );

    if (value.startsWith('data:image')) {
      try {
        child = Image.memory(base64Decode(value.split(',').last), fit: BoxFit.cover);
      } catch (_) {}
    } else if (value.startsWith('http://') || value.startsWith('https://')) {
      child = Image.network(value, fit: BoxFit.cover, errorBuilder: (_, __, ___) => child);
    }

    return Container(
      width: 54,
      height: 54,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: mutedText),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: mutedText, fontWeight: FontWeight.w800)),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _loadingCard() {
    return Container(
      height: 180,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: cardWhite, borderRadius: BorderRadius.circular(26)),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: const [
          Icon(Icons.event_busy_rounded, color: primaryBlue, size: 54),
          SizedBox(height: 14),
          Text('Bu durumda randevu yok', style: TextStyle(color: darkText, fontWeight: FontWeight.w900, fontSize: 18)),
          SizedBox(height: 8),
          Text(
            'Farklı sekmeye geçerek bekleyen, onaylanan veya reddedilen talepleri görüntüleyebilirsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: mutedText, fontWeight: FontWeight.w600, height: 1.45),
          ),
        ],
      ),
    );
  }
}
