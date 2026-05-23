import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'vet_appointments.dart';
import 'vet_app_drawer.dart';
import 'vet_messages.dart';

class VetListingsRequestsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const VetListingsRequestsScreen({super.key, required this.userData});

  @override
  State<VetListingsRequestsScreen> createState() => _VetListingsRequestsScreenState();
}

class _VetListingsRequestsScreenState extends State<VetListingsRequestsScreen> {
  static const Color primaryBlue = Color(0xFF1D4ED8);
  static const Color darkBlue = Color(0xFF13244A);
  static const Color navyBlue = Color(0xFF111B35);
  static const Color softBlue = Color(0xFFEFF6FF);
  static const Color lightBackground = Color(0xFFFAFBFF);
  static const Color darkText = Color(0xFF111827);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;
  static const Color dangerRed = Color(0xFFE11D48);

  bool _isLoading = true;
  bool _showListings = true;
  List<Map<String, dynamic>> _listings = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _farmerRequests = <Map<String, dynamic>>[];
  int _farmerRequestCount = 0;

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    if (fromData.isNotEmpty) return fromData;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  String get _name => (widget.userData['ad'] ?? '').toString().trim();
  String get _surname => (widget.userData['soyad'] ?? '').toString().trim();
  String get _fullName {
    final full = '$_name $_surname'.trim();
    return full.isEmpty ? 'Veteriner' : full;
  }

  String get _avatar => (widget.userData['avatar_url'] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    await Future.wait([_loadListings(), _loadFarmerVetRequests()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadListings() async {
    final userId = _userId;
    if (userId.isEmpty) return;

    try {
      final rows = await SupabaseService()
          .client
          .from('listings')
          .select('*')
          .eq('user_id', userId)
          .eq('category', 'veteriner')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 20));

      _listings = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Vet listings load error: $e');
      _listings = <Map<String, dynamic>>[];
      if (mounted) _showSnackBar('İlanlar yüklenemedi: $e', isError: true);
    }
  }

  Future<void> _loadFarmerVetRequests() async {
    final userId = _userId;
    if (userId.isEmpty) return;

    try {
      final rowsRaw = await SupabaseService()
          .client
          .from('listings')
          .select('*')
          .eq('category', 'veteriner')
          .order('created_at', ascending: false)
          .timeout(const Duration(seconds: 20));

      final rows = List<Map<String, dynamic>>.from(rowsRaw)
          .where((item) {
            final ownerId = (item['user_id'] ?? '').toString();
            if (ownerId.isEmpty || ownerId == userId) return false;
            if (item.containsKey('is_active') && item['is_active'] == false) return false;
            return true;
          })
          .toList();

      final farmerIds = rows
          .map((item) => (item['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usersMap = <String, Map<String, dynamic>>{};
      if (farmerIds.isNotEmpty) {
        final usersRows = await SupabaseService()
            .client
            .from('users')
            .select('id, ad, soyad, email, telefon, sehir, rol, avatar_url')
            .inFilter('id', farmerIds)
            .timeout(const Duration(seconds: 20));

        for (final user in List<Map<String, dynamic>>.from(usersRows)) {
          usersMap[(user['id'] ?? '').toString()] = user;
        }
      }

      final enrichedRequests = rows.map((item) {
        final ownerId = (item['user_id'] ?? '').toString();
        return {
          ...item,
          'farmer': usersMap[ownerId] ?? <String, dynamic>{},
        };
      }).toList();

      _farmerRequests = enrichedRequests.where((item) {
        final farmer = Map<String, dynamic>.from(item['farmer'] ?? {});
        final role = (farmer['rol'] ?? '').toString().toLowerCase().trim();
        return role != 'doktor' && role != 'doctor' && role != 'veteriner';
      }).toList();
      _farmerRequestCount = _farmerRequests.length;
    } catch (e) {
      debugPrint('Farmer vet requests load error: $e');
      _farmerRequests = <Map<String, dynamic>>[];
      _farmerRequestCount = 0;
      if (mounted) _showSnackBar('Çiftçi talepleri yüklenemedi: $e', isError: true);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? listing}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VetListingFormScreen(
          userData: widget.userData,
          listing: listing,
        ),
      ),
    );

    if (saved == true && mounted) {
      await _loadData();
    }
  }

  Future<void> _deleteListing(Map<String, dynamic> listing) async {
    final id = (listing['id'] ?? '').toString();
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('İlan silinsin mi?'),
        content: const Text('Bu veteriner ilanı kalıcı olarak silinecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SupabaseService()
          .client
          .from('listings')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => _listings.removeWhere((item) => (item['id'] ?? '').toString() == id));
      _showSnackBar('İlan silindi.');
    } catch (e) {
      debugPrint('Vet listing delete error: $e');
      if (mounted) _showSnackBar('İlan silinemedi: $e', isError: true);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> listing) async {
    final id = (listing['id'] ?? '').toString();
    if (id.isEmpty) return;
    final current = listing['is_active'] == true;

    try {
      await SupabaseService()
          .client
          .from('listings')
          .update({'is_active': !current})
          .eq('id', id)
          .eq('user_id', _userId)
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() => listing['is_active'] = !current);
      _showSnackBar(!current ? 'İlan aktif edildi.' : 'İlan pasife alındı.');
    } catch (e) {
      debugPrint('Vet listing active toggle error: $e');
      if (mounted) _showSnackBar('Durum güncellenemedi: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      drawer: VetAppDrawer(
        userData: widget.userData,
        currentPage: VetDrawerPage.listings,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryBlue))
            : RefreshIndicator(
                color: primaryBlue,
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 20),
                      _buildHero(),
                      const SizedBox(height: 18),
                      _buildSegmentedControl(),
                      const SizedBox(height: 18),
                      if (_showListings) _buildListingsSection() else _buildRequestsSection(),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _showListings
          ? Transform.translate(
              offset: const Offset(0, 14),
              child: FloatingActionButton.extended(
                heroTag: 'vetListingFab',
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('İlan Yayınla'),
              ),
            )
          : null,
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Builder(
          builder: (drawerContext) => IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: cardWhite,
              foregroundColor: navyBlue,
              fixedSize: const Size(48, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Scaffold.of(drawerContext).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'İlanlar & Talepler',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: darkText,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ),
        ClipOval(child: _buildAvatar(44, 16)),
      ],
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [navyBlue, Color(0xFF1E3A8A)],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withOpacity(0.18),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -6,
            child: Icon(
              Icons.medical_services_rounded,
              color: Colors.white.withOpacity(0.07),
              size: 125,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_rounded, color: Colors.white, size: 34),
              const SizedBox(height: 16),
              const Text(
                'Veteriner profilini\nyayınla ve talepleri yönet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Çiftçiler Veteriner / Sağlık kategorisinde yardım talebi oluşturduğunda bu ekranda görebilir, uygun olanlara doğrudan mesaj gönderebilirsin.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(child: _segmentButton('İlanlarım', _showListings, () => setState(() => _showListings = true))),
          Expanded(child: _segmentButton('Çiftçi Talepleri', !_showListings, () => setState(() => _showListings = false))),
        ],
      ),
    );
  }

  Widget _segmentButton(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? primaryBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : mutedText,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListingsSection() {
    if (_listings.isEmpty) {
      return _emptyBox(
        icon: Icons.campaign_rounded,
        title: 'Henüz veteriner ilanı yok',
        message: 'Profilini yayınlayarak çiftçilerin E‑Veteriner ekranında seni görmesini sağlayabilirsin.',
        actionText: 'İlan Yayınla',
        onAction: () => _openForm(),
      );
    }

    return Column(
      children: _listings.map(_listingCard).toList(),
    );
  }

  Widget _listingCard(Map<String, dynamic> listing) {
    final title = (listing['title'] ?? 'Veteriner Hizmeti').toString();
    final description = (listing['description'] ?? 'Açıklama eklenmemiş.').toString();
    final location = (listing['location'] ?? 'Konum belirtilmemiş').toString();
    final active = listing['is_active'] == true;
    final photos = _parsePhotos(listing['photos']);
    final coverPhoto = photos.isNotEmpty ? photos.first : '';
    final price = _toDouble(listing['price']);
    final detailMap = _parseVetDescription(description);
    final specialty = (detailMap['specialty'] ?? '').toString();
    final experience = (detailMap['experience'] ?? '').toString();
    final clinic = (detailMap['clinic'] ?? '').toString();
    final serviceDescription = (detailMap['description'] ?? description).toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (coverPhoto.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _buildListingImage(coverPhoto, height: 150, width: double.infinity),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              ClipOval(child: _buildAvatar(54, 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 17, color: mutedText),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: mutedText,
                              fontSize: 13.5,
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFEFFDF5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              active ? 'Aktif İlan' : 'Pasif İlan',
              style: TextStyle(
                color: active ? const Color(0xFF047857) : mutedText,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (specialty.isNotEmpty) _infoChip(Icons.local_hospital_rounded, specialty),
              if (experience.isNotEmpty) _infoChip(Icons.history_rounded, experience),
              if (clinic.isNotEmpty) _infoChip(Icons.business_rounded, clinic),
              if (price != null && price > 0) _infoChip(Icons.payments_rounded, '${_formatPrice(price)} ₺'),
              if (photos.length > 1) _infoChip(Icons.photo_library_rounded, '${photos.length} fotoğraf'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Açıklama: $serviceDescription',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: darkText,
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openForm(listing: listing),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Düzenle'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryBlue,
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _deleteListing(listing),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('İlanı Sil'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dangerRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsSection() {
    if (_farmerRequests.isEmpty) {
      return _emptyBox(
        icon: Icons.volunteer_activism_rounded,
        title: 'Çiftçi talebi yok',
        message: 'Çiftçiler İlan Pazarı tarafında Veteriner / Sağlık kategorisiyle yardım talebi oluşturduğunda burada görünecek.',
        actionText: 'Yenile',
        onAction: _loadData,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: softBlue,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.medical_services_rounded, color: primaryBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_farmerRequestCount çiftçi talebi',
                      style: const TextStyle(
                        color: darkText,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Veteriner / Sağlık kategorisindeki yardım taleplerini inceleyip çiftçiye mesaj gönderebilirsin.',
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ..._farmerRequests.map(_farmerRequestCard),
      ],
    );
  }

  Widget _farmerRequestCard(Map<String, dynamic> request) {
    final farmer = Map<String, dynamic>.from(request['farmer'] ?? {});
    final farmerName = _personName(farmer, fallback: 'Çiftçi');
    final title = (request['title'] ?? 'Veteriner desteği talebi').toString();
    final description = (request['description'] ?? 'Açıklama eklenmemiş.').toString();
    final location = (request['location'] ?? farmer['sehir'] ?? 'Konum belirtilmemiş').toString();
    final price = _toDouble(request['price']);
    final photos = _parsePhotos(request['photos']);
    final createdAt = _formatDateTime(request['created_at']);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(child: _buildPersonAvatar(farmer, 52, 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            farmerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: darkText,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFFDF5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Çiftçi Talebi',
                            style: TextStyle(
                              color: Color(0xFF047857),
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: mutedText),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: mutedText,
                              fontSize: 13,
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
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: darkText,
              fontSize: 18,
              height: 1.25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: mutedText,
              fontSize: 14.2,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip(Icons.medical_services_rounded, 'Veteriner / Sağlık'),
              _infoChip(Icons.schedule_rounded, createdAt),
              if (price != null && price > 0) _infoChip(Icons.payments_rounded, '${_formatPrice(price)} ₺'),
              if (photos.isNotEmpty) _infoChip(Icons.photo_library_rounded, '${photos.length} fotoğraf'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openRequestDetail(request),
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('Detay'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryBlue,
                    side: const BorderSide(color: Color(0xFFBFDBFE)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _messageFarmer(request),
                  icon: const Icon(Icons.chat_bubble_rounded),
                  label: const Text('Mesaj Gönder'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRequestDetail(Map<String, dynamic> request) async {
    final farmer = Map<String, dynamic>.from(request['farmer'] ?? {});
    final farmerName = _personName(farmer, fallback: 'Çiftçi');
    final title = (request['title'] ?? 'Veteriner desteği talebi').toString();
    final description = (request['description'] ?? 'Açıklama eklenmemiş.').toString();
    final location = (request['location'] ?? farmer['sehir'] ?? 'Konum belirtilmemiş').toString();
    final price = _toDouble(request['price']);
    final createdAt = _formatDateTime(request['created_at']);
    final email = (farmer['email'] ?? 'E-posta eklenmemiş').toString();
    final phone = (farmer['telefon'] ?? 'Telefon eklenmemiş').toString();
    final city = (farmer['sehir'] ?? 'Şehir belirtilmemiş').toString();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      ClipOval(child: _buildPersonAvatar(farmer, 58, 20)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              farmerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: darkText,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Çiftçi Talebi • Veteriner / Sağlık',
                              style: TextStyle(
                                color: primaryBlue,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _detailInfoBox('Talep Başlığı', title, Icons.title_rounded),
                  _detailInfoBox('Açıklama', description, Icons.notes_rounded, multiline: true),
                  _detailInfoBox('Konum', location, Icons.location_on_rounded),
                  _detailInfoBox('Talep Tarihi', createdAt, Icons.schedule_rounded),
                  if (price != null && price > 0)
                    _detailInfoBox('Belirtilen Bütçe / Ücret', '${_formatPrice(price)} ₺', Icons.payments_rounded),
                  const SizedBox(height: 10),
                  const Text(
                    'Çiftçi Bilgileri',
                    style: TextStyle(
                      color: darkText,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _contactRow(Icons.mail_outline_rounded, 'E-posta', email),
                  _contactRow(Icons.phone_rounded, 'Telefon', phone),
                  _contactRow(Icons.location_city_rounded, 'Şehir', city),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _messageFarmer(request);
                      },
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: const Text('Çiftçiye Mesaj Gönder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _messageFarmer(Map<String, dynamic> request) async {
    final farmerId = (request['user_id'] ?? '').toString();
    final currentUserId = _userId;
    if (farmerId.isEmpty || currentUserId.isEmpty) {
      _showSnackBar('Mesaj başlatmak için kullanıcı bilgisi bulunamadı.', isError: true);
      return;
    }
    if (farmerId == currentUserId) {
      _showSnackBar('Kendi talebine mesaj gönderemezsin.', isError: true);
      return;
    }

    try {
      final id1 = currentUserId.compareTo(farmerId) <= 0 ? currentUserId : farmerId;
      final id2 = currentUserId.compareTo(farmerId) <= 0 ? farmerId : currentUserId;

      final existing = await SupabaseService()
          .client
          .from('chats')
          .select('id')
          .eq('user1_id', id1)
          .eq('user2_id', id2)
          .maybeSingle()
          .timeout(const Duration(seconds: 20));

      if (existing == null) {
        await SupabaseService()
            .client
            .from('chats')
            .insert({'user1_id': id1, 'user2_id': id2})
            .timeout(const Duration(seconds: 20));
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VetMessagesScreen(userData: widget.userData)),
      );
    } catch (e) {
      debugPrint('Start farmer chat error: $e');
      if (mounted) _showSnackBar('Mesaj başlatılamadı: $e', isError: true);
    }
  }

  Widget _detailInfoBox(String label, String value, IconData icon, {bool multiline = false}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: primaryBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 14.3,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: softBlue,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryBlue, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              style: const TextStyle(
                color: darkText,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _personName(Map<String, dynamic> person, {required String fallback}) {
    final ad = (person['ad'] ?? person['first_name'] ?? '').toString().trim();
    final soyad = (person['soyad'] ?? person['last_name'] ?? '').toString().trim();
    final full = '$ad $soyad'.trim();
    return full.isEmpty ? fallback : full;
  }

  Widget _buildPersonAvatar(Map<String, dynamic> person, double size, double fontSize) {
    final avatar = (person['avatar_url'] ?? '').toString().trim();
    final name = _personName(person, fallback: 'Çiftçi');
    if (avatar.startsWith('data:image')) {
      final bytes = _decodeDataImage(avatar);
      if (bytes != null) {
        return Image.memory(bytes, width: size, height: size, fit: BoxFit.cover);
      }
    }
    if (avatar.startsWith('http')) {
      return Image.network(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _personAvatarFallback(name, size, fontSize),
      );
    }
    return _personAvatarFallback(name, size, fontSize);
  }

  Widget _personAvatarFallback(String name, double size, double fontSize) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'Ç';
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFEFFDF5),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: const Color(0xFF047857),
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  String _formatDateTime(dynamic value) {
    final dt = DateTime.tryParse(value?.toString() ?? '');
    if (dt == null) return 'Tarih belirtilmemiş';
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _emptyBox({
    required IconData icon,
    required String title,
    required String message,
    required String actionText,
    required VoidCallback onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: softBlue,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: primaryBlue, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: darkText, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: mutedText, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onAction,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: Text(actionText, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: softBlue,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primaryBlue),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: primaryBlue,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListingImage(String source, {required double height, required double width}) {
    if (source.startsWith('data:image')) {
      final bytes = _decodeDataImage(source);
      if (bytes != null) {
        return Image.memory(bytes, height: height, width: width, fit: BoxFit.cover);
      }
    }
    if (source.startsWith('http')) {
      return Image.network(
        source,
        height: height,
        width: width,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _listingImageFallback(height, width),
      );
    }
    return _listingImageFallback(height, width);
  }

  Widget _listingImageFallback(double height, double width) {
    return Container(
      height: height,
      width: width,
      color: softBlue,
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported_outlined, color: primaryBlue, size: 34),
    );
  }

  List<String> _parsePhotos(dynamic value) {
    if (value == null) return <String>[];
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'null') return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (decoded is String && decoded.trim().isNotEmpty) return <String>[decoded.trim()];
    } catch (_) {}
    return <String>[raw];
  }

  Uint8List? _decodeDataImage(String value) {
    try {
      final comma = value.indexOf(',');
      if (comma == -1) return null;
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  String _formatPrice(double value) {
    final asInt = value.truncateToDouble() == value;
    return value.toStringAsFixed(asInt ? 0 : 2).replaceAll('.', ',');
  }

  Map<String, String> _parseVetDescription(String raw) {
    final result = <String, String>{'description': raw};
    final lines = raw.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('uzmanlık alanı:')) {
        result['specialty'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (lower.startsWith('deneyim süresi:') || lower.startsWith('deneyim:')) {
        result['experience'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (lower.startsWith('klinik / şirket adı:') || lower.startsWith('klinik / şirket:')) {
        result['clinic'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (lower.startsWith('hizmet açıklaması:') || lower.startsWith('açıklama:')) {
        result['description'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      }
    }
    return result;
  }

  Widget _buildAvatar(double size, double fontSize) {
    if (_avatar.startsWith('data:image')) {
      try {
        final comma = _avatar.indexOf(',');
        if (comma != -1) {
          final bytes = base64Decode(_avatar.substring(comma + 1));
          return Image.memory(Uint8List.fromList(bytes), width: size, height: size, fit: BoxFit.cover);
        }
      } catch (_) {}
    }
    if (_avatar.startsWith('http')) {
      return Image.network(
        _avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarFallback(size, fontSize),
      );
    }
    return _avatarFallback(size, fontSize);
  }

  Widget _avatarFallback(double size, double fontSize) {
    final letter = _name.isNotEmpty ? _name[0].toUpperCase() : 'V';
    return Container(
      width: size,
      height: size,
      color: softBlue,
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(color: primaryBlue, fontSize: fontSize, fontWeight: FontWeight.w900)),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? dangerRed : primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class VetListingFormScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic>? listing;

  const VetListingFormScreen({super.key, required this.userData, this.listing});

  @override
  State<VetListingFormScreen> createState() => _VetListingFormScreenState();
}

class _VetListingFormScreenState extends State<VetListingFormScreen> {
  static const Color primaryBlue = Color(0xFF1D4ED8);
  static const Color navyBlue = Color(0xFF111B35);
  static const Color lightBackground = Color(0xFFFAFBFF);
  static const Color darkText = Color(0xFF111827);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;
  static const String listingPhotosBucket = 'listing-photos';

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _experienceController = TextEditingController();
  final _clinicController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  String _specialty = 'Büyükbaş';
  bool _isActive = true;
  bool _isSaving = false;
  final List<String> _existingPhotos = <String>[];
  final List<XFile> _pickedPhotos = <XFile>[];

  final List<String> _specialtyOptions = const <String>[
    'Büyükbaş',
    'Küçükbaş',
    'Kanatlı',
    'Evcil Hayvan',
    'Acil Müdahale',
    'Aşılama',
    'Genel Veterinerlik',
  ];

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    if (fromData.isNotEmpty) return fromData;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    _titleController.text = (listing?['title'] ?? '').toString();
    if (_titleController.text.trim().isEmpty) {
      _titleController.text = 'Uzman Büyükbaş Hekimi - 7/24 Acil Müdahale';
    }
    _locationController.text = (listing?['location'] ?? widget.userData['sehir'] ?? '').toString();
    _priceController.text = _priceToText(listing?['price']);
    _isActive = listing == null ? true : listing['is_active'] == true;
    _existingPhotos.addAll(_parsePhotos(listing?['photos']));

    final descriptionRaw = (listing?['description'] ?? '').toString();
    final parsed = _parseVetDescription(descriptionRaw);
    _specialty = parsed['specialty'] ?? 'Büyükbaş';
    if (!_specialtyOptions.contains(_specialty)) _specialty = 'Genel Veterinerlik';
    _experienceController.text = parsed['experience'] ?? '';
    _clinicController.text = parsed['clinic'] ?? '';
    _descriptionController.text = parsed['description'] ?? descriptionRaw;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _experienceController.dispose();
    _clinicController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    if (_isSaving) return;
    final remaining = 3 - _existingPhotos.length - _pickedPhotos.length;
    if (remaining <= 0) {
      _showSnackBar('En fazla 3 fotoğraf ekleyebilirsin.', isError: true);
      return;
    }

    try {
      final files = await _imagePicker.pickMultiImage(
        imageQuality: 72,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (files.isEmpty) return;
      setState(() => _pickedPhotos.addAll(files.take(remaining)));
    } catch (e) {
      if (mounted) _showSnackBar('Fotoğraf seçilemedi: $e', isError: true);
    }
  }

  Future<List<String>> _uploadPickedPhotos(String userId) async {
    final uploaded = <String>[];
    for (final file in _pickedPhotos) {
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw Exception('${file.name} 8 MB üstünde. Daha küçük bir fotoğraf seç.');
      }

      final extension = _safeExtension(file.name);
      final safeName = _safeFileName(file.name);
      final path = '$userId/vet_${DateTime.now().millisecondsSinceEpoch}_$safeName.$extension';
      final contentType = _contentType(extension);

      await SupabaseService()
          .client
          .storage
          .from(listingPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: contentType,
            ),
          )
          .timeout(const Duration(seconds: 35));

      uploaded.add(SupabaseService().client.storage.from(listingPhotosBucket).getPublicUrl(path));
    }
    return uploaded;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final userId = _userId;
    if (userId.isEmpty) {
      _showSnackBar('Oturum bilgisi bulunamadı.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uploadedPhotos = await _uploadPickedPhotos(userId);
      final allPhotos = <String>[..._existingPhotos, ...uploadedPhotos];
      final description = _buildDescriptionPayload();
      final payload = <String, dynamic>{
        'listing_type': 'sell',
        'category': 'veteriner',
        'title': _titleController.text.trim(),
        'description': description,
        'price': _parsePrice(_priceController.text),
        'location': _locationController.text.trim().isEmpty ? 'Konum belirtilmemiş' : _locationController.text.trim(),
        'photos': jsonEncode(allPhotos),
        'is_active': _isActive,
      };

      final listingId = (widget.listing?['id'] ?? '').toString();
      if (listingId.isEmpty) {
        payload['user_id'] = userId;
        await _insertListingWithFallback(payload);
      } else {
        await _updateListingWithFallback(payload, listingId, userId);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Vet listing save error: $e');
      if (mounted) _showSnackBar('İlan kaydedilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _insertListingWithFallback(Map<String, dynamic> payload) async {
    try {
      await SupabaseService().client.from('listings').insert(payload).timeout(const Duration(seconds: 25));
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('is_active') || text.contains('photos')) {
        final fallback = Map<String, dynamic>.from(payload)..remove('is_active');
        await SupabaseService().client.from('listings').insert(fallback).timeout(const Duration(seconds: 25));
      } else {
        rethrow;
      }
    }
  }

  Future<void> _updateListingWithFallback(Map<String, dynamic> payload, String listingId, String userId) async {
    try {
      await SupabaseService()
          .client
          .from('listings')
          .update(payload)
          .eq('id', listingId)
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      final text = e.toString().toLowerCase();
      if (text.contains('is_active') || text.contains('photos')) {
        final fallback = Map<String, dynamic>.from(payload)..remove('is_active');
        await SupabaseService()
            .client
            .from('listings')
            .update(fallback)
            .eq('id', listingId)
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 25));
      } else {
        rethrow;
      }
    }
  }

  String _buildDescriptionPayload() {
    final experience = _experienceController.text.trim();
    final clinic = _clinicController.text.trim();
    final description = _descriptionController.text.trim();
    return [
      'Uzmanlık Alanı: $_specialty',
      if (experience.isNotEmpty) 'Deneyim Süresi: $experience',
      if (clinic.isNotEmpty) 'Klinik / Şirket Adı: $clinic',
      'Hizmet Açıklaması: ${description.isEmpty ? 'Açıklama bilgisi eklenmemiş.' : description}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        backgroundColor: lightBackground,
        appBar: AppBar(
          backgroundColor: lightBackground,
          elevation: 0,
          foregroundColor: darkText,
          title: Text(widget.listing == null ? 'Hizmet Profilini Yayınla' : 'Hizmet Profilini Düzenle'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoBox(),
                  const SizedBox(height: 20),
                  _label('İlan Başlığı'),
                  _input(
                    controller: _titleController,
                    hint: 'Örn: Uzman Büyükbaş Hekimi - 7/24 Acil Müdahale',
                    validator: (value) => (value ?? '').trim().isEmpty ? 'İlan başlığı gerekli' : null,
                  ),
                  const SizedBox(height: 16),
                  _responsiveFieldPair(
                    left: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Uzmanlık Alanı'),
                        _specialtyDropdown(),
                      ],
                    ),
                    right: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Deneyim Süresi'),
                        _input(
                          controller: _experienceController,
                          hint: 'Örn: 5 Yıl',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _responsiveFieldPair(
                    left: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelWithOptional('Klinik / Şirket Adı'),
                        _input(
                          controller: _clinicController,
                          hint: 'Örn: AgriVet Kliniği',
                        ),
                      ],
                    ),
                    right: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Muayene Başlangıç (₺)'),
                        _input(
                          controller: _priceController,
                          hint: 'Örn: 1000',
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _label('Hizmet Bölgesi / Adres'),
                  _input(
                    controller: _locationController,
                    hint: 'Örn: Tekirdağ ve Çevresi',
                    validator: (value) => (value ?? '').trim().isEmpty ? 'Hizmet bölgesi gerekli' : null,
                  ),
                  const SizedBox(height: 16),
                  _label('Hizmet Açıklaması'),
                  _input(
                    controller: _descriptionController,
                    hint: 'Sunduğunuz hizmetler, aşı takvimi, cerrahi müdahaleler vb. detayları yazın...',
                    maxLines: 5,
                    validator: (value) => (value ?? '').trim().isEmpty ? 'Hizmet açıklaması gerekli' : null,
                  ),
                  const SizedBox(height: 18),
                  _label('Profil / Klinik Fotoğrafları (Maks 3)'),
                  _photoPicker(),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    activeColor: primaryBlue,
                    title: const Text('İlan aktif olsun', style: TextStyle(fontWeight: FontWeight.w900, color: darkText)),
                    subtitle: const Text('Pasife alırsan çiftçiler seni listede göremez.', style: TextStyle(color: mutedText)),
                    onChanged: _isSaving ? null : (value) => setState(() => _isActive = value),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: mutedText,
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                          child: const Text('İptal', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _save,
                          icon: _isSaving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check_rounded),
                          label: Text(_isSaving ? 'Yayınlanıyor...' : 'Yayına Al'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _responsiveFieldPair({
    required Widget left,
    required Widget right,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              left,
              const SizedBox(height: 16),
              right,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _infoBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [navyBlue, Color(0xFF1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Text(
        'Bu hizmet profili E‑Veteriner ekranında çiftçilere görünecek. Hizmet bölgeni, uzmanlık alanını ve muayene başlangıç ücretini net yazman önerilir.',
        style: TextStyle(color: Colors.white, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _specialtyDropdown() {
    return DropdownButtonFormField<String>(
      value: _specialty,
      items: _specialtyOptions
          .map((item) => DropdownMenuItem<String>(value: item, child: Text(item)))
          .toList(),
      onChanged: _isSaving ? null : (value) => setState(() => _specialty = value ?? 'Büyükbaş'),
      decoration: _inputDecoration('Uzmanlık seçin'),
    );
  }

  Widget _photoPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _pickPhotos,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD7E3F8)),
            ),
            child: Column(
              children: const [
                Icon(Icons.image_outlined, color: navyBlue, size: 34),
                SizedBox(height: 8),
                Text(
                  'Fotoğraf eklemek için tıklayın',
                  style: TextStyle(color: mutedText, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'JPG/PNG önerilir. En fazla 3 fotoğraf.',
                  style: TextStyle(color: mutedText, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_existingPhotos.isNotEmpty || _pickedPhotos.isNotEmpty)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _existingPhotos.length; i++) _existingPhotoItem(i),
              for (var i = 0; i < _pickedPhotos.length; i++) _pickedPhotoItem(i),
            ],
          ),
      ],
    );
  }

  Widget _existingPhotoItem(int index) {
    final url = _existingPhotos[index];
    return _photoShell(
      child: _imageFromSource(url, height: 82, width: 82),
      onRemove: () => setState(() => _existingPhotos.removeAt(index)),
    );
  }

  Widget _pickedPhotoItem(int index) {
    final file = _pickedPhotos[index];
    return _photoShell(
      child: Image.file(File(file.path), height: 82, width: 82, fit: BoxFit.cover),
      onRemove: () => setState(() => _pickedPhotos.removeAt(index)),
    );
  }

  Widget _photoShell({required Widget child, required VoidCallback onRemove}) {
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
        Positioned(
          right: 4,
          top: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.90), borderRadius: BorderRadius.circular(99)),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageFromSource(String source, {required double height, required double width}) {
    if (source.startsWith('data:image')) {
      final bytes = _decodeDataImage(source);
      if (bytes != null) return Image.memory(bytes, height: height, width: width, fit: BoxFit.cover);
    }
    if (source.startsWith('http')) {
      return Image.network(
        source,
        height: height,
        width: width,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _photoFallback(height, width),
      );
    }
    return _photoFallback(height, width);
  }

  Widget _photoFallback(double height, double width) {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFFEFF6FF),
      child: const Icon(Icons.image_not_supported_outlined, color: primaryBlue),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: darkText, fontSize: 14.5, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _labelWithOptional(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(color: darkText, fontSize: 14.5, fontWeight: FontWeight.w900),
          children: [
            TextSpan(text: text),
            const TextSpan(
              text: ' (Opsiyonel)',
              style: TextStyle(color: mutedText, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: primaryBlue, width: 1.5)),
    );
  }

  List<String> _parsePhotos(dynamic value) {
    if (value == null) return <String>[];
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'null') return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
    } catch (_) {}
    return <String>[raw];
  }

  Uint8List? _decodeDataImage(String value) {
    try {
      final comma = value.indexOf(',');
      if (comma == -1) return null;
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _parseVetDescription(String raw) {
    final result = <String, String>{'description': raw};
    final lines = raw.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('uzmanlık alanı:')) {
        result['specialty'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (lower.startsWith('deneyim süresi:') || lower.startsWith('deneyim:')) {
        result['experience'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (lower.startsWith('klinik / şirket adı:') || lower.startsWith('klinik / şirket:')) {
        result['clinic'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      } else if (lower.startsWith('hizmet açıklaması:') || lower.startsWith('açıklama:')) {
        result['description'] = trimmed.substring(trimmed.indexOf(':') + 1).trim();
      }
    }
    return result;
  }

  double? _parsePrice(String value) {
    final cleaned = value.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  String _priceToText(dynamic value) {
    if (value == null) return '';
    final parsed = value is num ? value.toDouble() : double.tryParse(value.toString());
    if (parsed == null || parsed <= 0) return '';
    return parsed.truncateToDouble() == parsed ? parsed.toStringAsFixed(0) : parsed.toString();
  }

  String _safeExtension(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
    return allowed.contains(ext) ? ext : 'jpg';
  }

  String _safeFileName(String name) {
    final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final safe = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return safe.isEmpty ? 'vet_photo' : safe;
  }

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFE11D48) : primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
