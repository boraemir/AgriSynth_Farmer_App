import 'dart:convert';

import 'package:flutter/material.dart';
import 'farmer_app_drawer.dart';
import 'package:image_picker/image_picker.dart';

import 'supabase_service.dart';

class FieldsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const FieldsScreen({super.key, required this.userData});

  @override
  State<FieldsScreen> createState() => _FieldsScreenState();
}

class _FieldsScreenState extends State<FieldsScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF064E3B);
  static const Color lightBackground = Color(0xFFF6FAF5);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  bool _isLoading = true;
  String? _errorText;
  List<Map<String, dynamic>> _fields = [];

  String get _authUserId => SupabaseService().client.auth.currentUser?.id ?? '';

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    return fromData.isNotEmpty ? fromData : _authUserId;
  }

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      if (_userId.isEmpty) {
        throw Exception('Kullanıcı oturumu bulunamadı.');
      }

      final data = await SupabaseService()
          .client
          .from('fields')
          .select(
            'id,created_at,field_name,city,address,area_sqm,has_animals,tree_count,tree_types,animal_count,animal_types,photos,user_id',
          )
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _fields = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Fields load error: $e');
      if (!mounted) return;
      setState(() => _errorText = 'Araziler yüklenirken bir sorun oluştu.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openFieldForm({Map<String, dynamic>? field}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FieldFormScreen(
          userData: widget.userData,
          field: field,
        ),
      ),
    );

    if (changed == true && mounted) {
      await _loadFields();
    }
  }

  Future<void> _deleteField(Map<String, dynamic> field) async {
    final fieldName = (field['field_name'] ?? 'Arazi').toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Arazi silinsin mi?'),
          content: Text('$fieldName adlı arazi kalıcı olarak silinecek.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade500,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      await SupabaseService().client.from('fields').delete().eq('id', field['id']);

      if (!mounted) return;
      _showSnack('Arazi silindi.');
      await _loadFields();
    } catch (e) {
      debugPrint('Field delete error: $e');
      if (!mounted) return;
      _showSnack('Arazi silinemedi.', isError: true);
    }
  }

  List<String> _parsePhotos(dynamic value) {
    if (value == null) return [];
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'null') return [];

    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) {
                if (e is Map) {
                  return (e['url'] ?? e['src'] ?? e['data'] ?? e['photo'] ?? '').toString();
                }
                return e.toString();
              })
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    if (raw.startsWith('data:image') || raw.startsWith('http')) return [raw];

    return raw
        .split(RegExp(r'\s*\|\|\|\s*|\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Widget _imageFromSource(String source, {BoxFit fit = BoxFit.cover}) {
    final cleaned = source.trim();

    if (cleaned.startsWith('data:image')) {
      try {
        final commaIndex = cleaned.indexOf(',');
        if (commaIndex == -1) return _photoFallback();
        final base64Part = cleaned.substring(commaIndex + 1);
        return Image.memory(
          base64Decode(base64Part),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _photoFallback(),
        );
      } catch (_) {
        return _photoFallback();
      }
    }

    if (cleaned.startsWith('http')) {
      return Image.network(
        cleaned,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _photoFallback(),
      );
    }

    // Eski kayıtlar bazen sadece base64 gövdesi olarak gelebilir.
    if (cleaned.length > 150 && !cleaned.contains(' ')) {
      try {
        return Image.memory(
          base64Decode(cleaned),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _photoFallback(),
        );
      } catch (_) {}
    }

    return _photoFallback();
  }

  Widget _photoFallback() {
    return Container(
      color: const Color(0xFFEAF7EF),
      child: const Center(
        child: Icon(Icons.landscape_rounded, color: primaryGreen, size: 34),
      ),
    );
  }

  String _formatCount(dynamic value) {
    final n = num.tryParse((value ?? '').toString());
    if (n == null) return '0';
    if (n % 1 == 0) return n.toInt().toString();
    return n.toStringAsFixed(1);
  }

  String _formatArea(dynamic value) => '${_formatCount(value)} m²';

  List<_TreeSummary> _parseTreeSummaries(dynamic treeTypes, dynamic fallbackCount) {
    final raw = (treeTypes ?? '').toString().trim();
    final fallback = int.tryParse((fallbackCount ?? '0').toString()) ?? 0;
    if (raw.isEmpty) {
      return fallback > 0 ? [_TreeSummary(type: 'Belirtilmemiş', count: fallback)] : [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final items = decoded.map((e) {
          if (e is Map) {
            final type = (e['type'] ?? e['name'] ?? e['tur'] ?? e['tree_type'] ?? '').toString().trim();
            final countRaw = e['count'] ?? e['adet'] ?? e['quantity'] ?? e['total'];
            final count = int.tryParse((countRaw ?? '0').toString()) ?? 0;
            return _TreeSummary(type: type.isEmpty ? 'Belirtilmemiş' : type, count: count);
          }
          return _parseTreeText(e.toString());
        }).whereType<_TreeSummary>().where((e) => e.type.isNotEmpty).toList();
        if (items.isNotEmpty) return items;
      }
    } catch (_) {}

    final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [];

    return parts.map((part) => _parseTreeText(part)).whereType<_TreeSummary>().toList();
  }

  _TreeSummary? _parseTreeText(String part) {
    final raw = part.trim();
    if (raw.isEmpty) return null;

    if (raw.contains(':')) {
      final split = raw.split(':');
      final type = split.first.trim();
      final count = int.tryParse(split.length > 1 ? split[1].trim() : '') ?? 0;
      return _TreeSummary(type: type.isEmpty ? 'Belirtilmemiş' : type, count: count);
    }

    final countAtStart = RegExp(r'^(\d+)\s+(.+)$').firstMatch(raw);
    if (countAtStart != null) {
      return _TreeSummary(
        type: countAtStart.group(2)!.trim(),
        count: int.tryParse(countAtStart.group(1)!) ?? 0,
      );
    }

    return _TreeSummary(type: raw, count: 0);
  }

  List<_AnimalSummary> _parseAnimalSummaries(dynamic animalTypes, dynamic fallbackCount) {
    final raw = (animalTypes ?? '').toString().trim();
    final fallback = int.tryParse((fallbackCount ?? '0').toString()) ?? 0;
    if (raw.isEmpty) {
      return fallback > 0 ? [_AnimalSummary(type: 'Belirtilmemiş', total: fallback)] : [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final items = decoded.map((e) {
          if (e is Map) {
            final type = (e['type'] ?? e['name'] ?? e['tur'] ?? e['animal_type'] ?? '').toString().trim();
            final totalRaw = e['total'] ?? e['count'] ?? e['adet'] ?? e['quantity'];
            final maleRaw = e['male'] ?? e['erkek'];
            final femaleRaw = e['female'] ?? e['disi'] ?? e['dişi'];
            final notes = (e['notes'] ?? e['notlar'] ?? '').toString().trim();
            return _AnimalSummary(
              type: type.isEmpty ? 'Belirtilmemiş' : type,
              total: int.tryParse((totalRaw ?? '0').toString()) ?? 0,
              male: int.tryParse((maleRaw ?? '').toString()),
              female: int.tryParse((femaleRaw ?? '').toString()),
              notes: notes,
            );
          }
          return _parseAnimalText(e.toString());
        }).whereType<_AnimalSummary>().where((e) => e.type.isNotEmpty).toList();
        if (items.isNotEmpty) return items;
      }
    } catch (_) {}

    final parts = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return [];

    return parts.map((part) => _parseAnimalText(part)).whereType<_AnimalSummary>().toList();
  }

  _AnimalSummary? _parseAnimalText(String part) {
    final raw = part.trim();
    if (raw.isEmpty) return null;

    if (raw.contains(':')) {
      final split = raw.split(':');
      final type = split.first.trim();
      final total = int.tryParse(split.length > 1 ? split[1].trim() : '') ?? 0;
      return _AnimalSummary(type: type.isEmpty ? 'Belirtilmemiş' : type, total: total);
    }

    final countAtStart = RegExp(r'^(\d+)\s+(.+)$').firstMatch(raw);
    if (countAtStart != null) {
      return _AnimalSummary(
        type: countAtStart.group(2)!.trim(),
        total: int.tryParse(countAtStart.group(1)!) ?? 0,
      );
    }

    return _AnimalSummary(type: raw, total: 0);
  }

  String _treeDisplayText(Map<String, dynamic> field) {
    final items = _parseTreeSummaries(field['tree_types'], field['tree_count']);
    if (items.isEmpty) return '-';
    return items.map((e) => e.count > 0 ? '${e.count} ${e.type}' : e.type).join(', ');
  }

  String _animalDisplayText(Map<String, dynamic> field) {
    final hasAnimals = field['has_animals'] == true;
    if (!hasAnimals) return '-';
    final items = _parseAnimalSummaries(field['animal_types'], field['animal_count']);
    if (items.isEmpty) return '-';
    return items.map((e) {
      final details = <String>[];
      if (e.male != null) details.add('${e.male} erkek');
      if (e.female != null) details.add('${e.female} dişi');
      final base = e.total > 0 ? '${e.total} ${e.type}' : e.type;
      return details.isEmpty ? base : '$base (${details.join(', ')})';
    }).join(', ');
  }

  int _totalTrees() {
    var total = 0;
    for (final field in _fields) {
      final summaries = _parseTreeSummaries(field['tree_types'], field['tree_count']);
      if (summaries.isNotEmpty) {
        total += summaries.fold<int>(0, (sum, item) => sum + item.count);
      } else {
        total += int.tryParse('${field['tree_count'] ?? 0}') ?? 0;
      }
    }
    return total;
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade500 : primaryGreen,
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
      drawer: FarmerAppDrawer(
        userData: widget.userData,
        currentPage: FarmerDrawerPage.fields,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primaryGreen,
          onRefresh: _loadFields,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 22),
                      _buildHeader(),
                      const SizedBox(height: 22),
                      if (_isLoading)
                        Column(children: List.generate(3, (_) => _buildLoadingCard()))
                      else if (_errorText != null)
                        _buildErrorState()
                      else if (_fields.isEmpty)
                        _buildEmptyState()
                      else
                        Column(children: _fields.map(_buildFieldCard).toList()),
                      const SizedBox(height: 30),
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
        InkWell(
          onTap: () => _scaffoldKey.currentState?.openDrawer(),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.menu_rounded, color: darkText, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terrain_rounded, color: primaryGreen, size: 22),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Arazilerim',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: darkGreen,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: () => _openFieldForm(),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: primaryGreen.withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 21),
                SizedBox(width: 7),
                Text(
                  'Yeni Ekle',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF047857)],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryGreen.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(Icons.eco_rounded, size: 110, color: Colors.white.withOpacity(0.08)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.map_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 18),
              const Text(
                'Tarlalarını tek yerden yönet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Arazinin konumunu, alanını, ağaç/hayvan bilgisini ve hatırlatma fotoğraflarını burada takip edebilirsin.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard(Map<String, dynamic> field) {
    final photos = _parsePhotos(field['photos']);
    final title = (field['field_name'] ?? 'Arazi').toString();
    final city = (field['city'] ?? '').toString();
    final address = (field['address'] ?? '').toString();
    final treeText = _treeDisplayText(field);
    final animalText = _animalDisplayText(field);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photos.isNotEmpty)
            FieldPhotoCarousel(
              photos: photos,
              imageBuilder: (source) => _imageFromSource(source),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: darkText, fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 16, color: mutedText),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  city.isEmpty ? 'Şehir girilmemiş' : city,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: mutedText, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF7EF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _formatArea(field['area_sqm']),
                        style: const TextStyle(color: darkGreen, fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _infoRow('Adres', address.isEmpty ? '-' : address),
                _infoRow('Ağaçlar (${field['tree_count'] ?? 0})', treeText),
                _infoRow('Hayvanlar', animalText),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _actionButton(
                  label: 'Düzenle',
                  icon: Icons.edit_rounded,
                  color: const Color(0xFF0284C7),
                  background: const Color(0xFFE0F2FE),
                  onTap: () => _openFieldForm(field: field),
                ),
                const SizedBox(width: 10),
                _actionButton(
                  label: 'Sil',
                  icon: Icons.delete_outline_rounded,
                  color: Colors.red.shade500,
                  background: const Color(0xFFFEE2E2),
                  onTap: () => _deleteField(field),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE5EAF0)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: mutedText, fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(color: darkText, fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required Color background,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      height: 170,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: const Center(child: CircularProgressIndicator(color: primaryGreen)),
    );
  }

  Widget _buildErrorState() {
    return _stateCard(
      icon: Icons.error_outline_rounded,
      title: 'Araziler alınamadı',
      subtitle: _errorText ?? 'Tekrar dene.',
      buttonText: 'Tekrar Dene',
      onTap: _loadFields,
    );
  }

  Widget _buildEmptyState() {
    return _stateCard(
      icon: Icons.add_location_alt_rounded,
      title: 'Henüz arazi eklenmemiş',
      subtitle: 'İlk tarlanı ekleyerek konum, alan, ağaç ve hayvan bilgilerini takip etmeye başlayabilirsin.',
      buttonText: 'Arazi Ekle',
      onTap: () => _openFieldForm(),
    );
  }

  Widget _stateCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonText,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Column(
        children: [
          Icon(icon, color: primaryGreen, size: 44),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: darkText, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: mutedText, fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(buttonText),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class FieldPhotoCarousel extends StatefulWidget {
  final List<String> photos;
  final Widget Function(String source) imageBuilder;

  const FieldPhotoCarousel({
    super.key,
    required this.photos,
    required this.imageBuilder,
  });

  @override
  State<FieldPhotoCarousel> createState() => _FieldPhotoCarouselState();
}

class _FieldPhotoCarouselState extends State<FieldPhotoCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (index < 0 || index >= widget.photos.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = widget.photos.length > 1;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SizedBox(
        width: double.infinity,
        height: 198,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) => widget.imageBuilder(widget.photos[index]),
            ),
            if (hasMultiple) ...[
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _carouselButton(Icons.chevron_left_rounded, () => _goTo(_index - 1)),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _carouselButton(Icons.chevron_right_rounded, () => _goTo(_index + 1)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.photos.length, (i) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _index ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(i == _index ? 0.95 : 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
            ],
            Positioned(
              right: 12,
              bottom: hasMultiple ? 34 : 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.42),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.photos.length} fotoğraf',
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carouselButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.42), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}

class FieldFormScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final Map<String, dynamic>? field;

  const FieldFormScreen({
    super.key,
    required this.userData,
    this.field,
  });

  @override
  State<FieldFormScreen> createState() => _FieldFormScreenState();
}

class _FieldFormScreenState extends State<FieldFormScreen> {
  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF064E3B);
  static const Color lightBackground = Color(0xFFF6FAF5);
  static const Color darkText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _fieldNameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  final List<_TreeEntry> _treeEntries = [];
  final List<_AnimalEntry> _animalEntries = [];
  final List<String> _photos = [];

  bool _hasAnimals = false;
  bool _isSaving = false;
  bool _isPickingPhotos = false;

  bool get _isEdit => widget.field != null;

  String get _authUserId => SupabaseService().client.auth.currentUser?.id ?? '';

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    return fromData.isNotEmpty ? fromData : _authUserId;
  }

  @override
  void initState() {
    super.initState();
    _fillInitialValues();
  }

  void _fillInitialValues() {
    final field = widget.field;
    if (field == null) {
      _treeEntries.add(_TreeEntry());
      _animalEntries.add(_AnimalEntry());
      return;
    }

    _fieldNameCtrl.text = (field['field_name'] ?? '').toString();
    _cityCtrl.text = (field['city'] ?? '').toString();
    _addressCtrl.text = (field['address'] ?? '').toString();
    _areaCtrl.text = (field['area_sqm'] ?? '').toString();
    _hasAnimals = field['has_animals'] == true;
    _photos.addAll(_parsePhotos(field['photos']));

    _treeEntries.addAll(_parseTreeEntries(field['tree_types'], field['tree_count']));
    _animalEntries.addAll(_parseAnimalEntries(field['animal_types'], field['animal_count']));

    if (_treeEntries.isEmpty) _treeEntries.add(_TreeEntry());
    if (_animalEntries.isEmpty) _animalEntries.add(_AnimalEntry());
  }

  @override
  void dispose() {
    _fieldNameCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _areaCtrl.dispose();
    for (final entry in _treeEntries) {
      entry.dispose();
    }
    for (final entry in _animalEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  List<String> _parsePhotos(dynamic value) {
    if (value == null) return [];
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'null') return [];

    if (raw.startsWith('[')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) {
                if (e is Map) {
                  return (e['url'] ?? e['src'] ?? e['data'] ?? e['photo'] ?? '').toString();
                }
                return e.toString();
              })
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    if (raw.startsWith('data:image') || raw.startsWith('http')) return [raw];

    return raw
        .split(RegExp(r'\s*\|\|\|\s*|\n+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<_TreeEntry> _parseTreeEntries(dynamic treeTypes, dynamic fallbackCount) {
    final raw = (treeTypes ?? '').toString().trim();
    final fallback = int.tryParse((fallbackCount ?? '0').toString()) ?? 0;
    if (raw.isEmpty) {
      return fallback > 0 ? [_TreeEntry(type: 'Belirtilmemiş', count: '$fallback')] : [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) {
          if (e is Map) {
            final type = (e['type'] ?? e['name'] ?? e['tur'] ?? e['tree_type'] ?? '').toString();
            final count = (e['count'] ?? e['adet'] ?? e['quantity'] ?? e['total'] ?? '').toString();
            return _TreeEntry(type: type, count: count);
          }
          return _parseTreeText(e.toString());
        }).whereType<_TreeEntry>().toList();
      }
    } catch (_) {}

    return raw
        .split(',')
        .map((e) => _parseTreeText(e))
        .whereType<_TreeEntry>()
        .toList();
  }

  _TreeEntry? _parseTreeText(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;
    if (raw.contains(':')) {
      final parts = raw.split(':');
      return _TreeEntry(type: parts.first.trim(), count: parts.length > 1 ? parts[1].trim() : '');
    }
    final match = RegExp(r'^(\d+)\s+(.+)$').firstMatch(raw);
    if (match != null) {
      return _TreeEntry(type: match.group(2)!.trim(), count: match.group(1)!.trim());
    }
    return _TreeEntry(type: raw, count: '');
  }

  List<_AnimalEntry> _parseAnimalEntries(dynamic animalTypes, dynamic fallbackCount) {
    final raw = (animalTypes ?? '').toString().trim();
    final fallback = int.tryParse((fallbackCount ?? '0').toString()) ?? 0;
    if (raw.isEmpty) {
      return fallback > 0 ? [_AnimalEntry(type: 'Belirtilmemiş', total: '$fallback')] : [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) {
          if (e is Map) {
            final type = (e['type'] ?? e['name'] ?? e['tur'] ?? e['animal_type'] ?? '').toString();
            final total = (e['total'] ?? e['count'] ?? e['adet'] ?? e['quantity'] ?? '').toString();
            final male = (e['male'] ?? e['erkek'] ?? '').toString();
            final female = (e['female'] ?? e['disi'] ?? e['dişi'] ?? '').toString();
            final notes = (e['notes'] ?? e['notlar'] ?? '').toString();
            return _AnimalEntry(type: type, total: total, male: male, female: female, notes: notes);
          }
          return _parseAnimalText(e.toString());
        }).whereType<_AnimalEntry>().toList();
      }
    } catch (_) {}

    return raw
        .split(',')
        .map((e) => _parseAnimalText(e))
        .whereType<_AnimalEntry>()
        .toList();
  }

  _AnimalEntry? _parseAnimalText(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;
    if (raw.contains(':')) {
      final parts = raw.split(':');
      return _AnimalEntry(type: parts.first.trim(), total: parts.length > 1 ? parts[1].trim() : '');
    }
    final match = RegExp(r'^(\d+)\s+(.+)$').firstMatch(raw);
    if (match != null) {
      return _AnimalEntry(type: match.group(2)!.trim(), total: match.group(1)!.trim());
    }
    return _AnimalEntry(type: raw, total: '');
  }

  Future<void> _pickPhotos() async {
    if (_isPickingPhotos || _photos.length >= 10) return;

    setState(() => _isPickingPhotos = true);

    try {
      final images = await _picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 72,
      );

      if (images.isEmpty) return;

      final available = 10 - _photos.length;
      final selected = images.take(available);
      final converted = <String>[];

      for (final image in selected) {
        final bytes = await image.readAsBytes();
        if (bytes.length > 3 * 1024 * 1024) {
          continue;
        }
        final ext = image.name.toLowerCase();
        final mime = ext.endsWith('.png')
            ? 'image/png'
            : ext.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
        converted.add('data:$mime;base64,${base64Encode(bytes)}');
      }

      if (!mounted) return;
      if (converted.isEmpty) {
        _showSnack('Seçilen fotoğraflar çok büyük olabilir.', isError: true);
        return;
      }
      setState(() => _photos.addAll(converted));
    } catch (e) {
      debugPrint('Field photo pick error: $e');
      if (mounted) _showSnack('Fotoğraf seçilemedi.', isError: true);
    } finally {
      if (mounted) setState(() => _isPickingPhotos = false);
    }
  }

  Widget _imageFromSource(String source, {BoxFit fit = BoxFit.cover}) {
    final cleaned = source.trim();

    if (cleaned.startsWith('data:image')) {
      try {
        final commaIndex = cleaned.indexOf(',');
        if (commaIndex == -1) return _photoFallback();
        return Image.memory(
          base64Decode(cleaned.substring(commaIndex + 1)),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _photoFallback(),
        );
      } catch (_) {
        return _photoFallback();
      }
    }

    if (cleaned.startsWith('http')) {
      return Image.network(cleaned, fit: fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => _photoFallback());
    }

    if (cleaned.length > 150 && !cleaned.contains(' ')) {
      try {
        return Image.memory(base64Decode(cleaned), fit: fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => _photoFallback());
      } catch (_) {}
    }

    return _photoFallback();
  }

  Widget _photoFallback() {
    return Container(
      color: const Color(0xFFEAF7EF),
      child: const Center(child: Icon(Icons.landscape_rounded, color: primaryGreen, size: 34)),
    );
  }

  int _intFromController(TextEditingController controller) {
    return int.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
  }

  String? _serializeTreeTypes() {
    final items = _treeEntries.map((entry) {
      final type = entry.typeCtrl.text.trim();
      final count = _intFromController(entry.countCtrl);
      if (type.isEmpty && count == 0) return null;
      return <String, dynamic>{
        'type': type.isEmpty ? 'Belirtilmemiş' : type,
        'count': count,
      };
    }).whereType<Map<String, dynamic>>().toList();

    if (items.isEmpty) return null;
    return jsonEncode(items);
  }

  int _sumTreeCounts() {
    return _treeEntries.fold<int>(0, (sum, entry) => sum + _intFromController(entry.countCtrl));
  }

  String? _serializeAnimalTypes() {
    if (!_hasAnimals) return null;

    final items = _animalEntries.map((entry) {
      final type = entry.typeCtrl.text.trim();
      final oldTotal = _intFromController(entry.totalCtrl);
      final male = _intFromController(entry.maleCtrl);
      final female = _intFromController(entry.femaleCtrl);
      final total = (male + female) > 0 ? male + female : oldTotal;
      final notes = entry.notesCtrl.text.trim();
      if (type.isEmpty && total == 0 && male == 0 && female == 0 && notes.isEmpty) return null;
      return <String, dynamic>{
        'type': type.isEmpty ? 'Belirtilmemiş' : type,
        // Toplam alanı kullanıcıdan ayrı alınmıyor; erkek + dişi toplamından otomatik hesaplanıyor.
        // Eski kayıtlarda sadece total varsa, o değer korunuyor.
        'total': total,
        'male': male,
        'female': female,
        'notes': notes,
      };
    }).whereType<Map<String, dynamic>>().toList();

    if (items.isEmpty) return null;
    return jsonEncode(items);
  }

  int _sumAnimalCounts() {
    if (!_hasAnimals) return 0;
    return _animalEntries.fold<int>(0, (sum, entry) {
      final oldTotal = _intFromController(entry.totalCtrl);
      final male = _intFromController(entry.maleCtrl);
      final female = _intFromController(entry.femaleCtrl);
      final computedTotal = (male + female) > 0 ? male + female : oldTotal;
      return sum + computedTotal;
    });
  }

  Future<void> _saveField() async {
    FocusScope.of(context).unfocus();
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    if (_userId.isEmpty) {
      _showSnack('Kullanıcı oturumu bulunamadı.', isError: true);
      return;
    }

    final area = double.tryParse(_areaCtrl.text.trim().replaceAll(',', '.'));
    if (area == null || area <= 0) {
      _showSnack('Alan bilgisi geçerli olmalı.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final payload = <String, dynamic>{
        'field_name': _fieldNameCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'area_sqm': area,
        'has_animals': _hasAnimals,
        'tree_count': _sumTreeCounts(),
        'tree_types': _serializeTreeTypes(),
        'animal_count': _sumAnimalCounts(),
        'animal_types': _serializeAnimalTypes(),
        'photos': _photos.isEmpty ? null : jsonEncode(_photos),
        'user_id': _userId,
      };

      if (_isEdit) {
        await SupabaseService().client.from('fields').update(payload).eq('id', widget.field!['id']);
      } else {
        await SupabaseService().client.from('fields').insert(payload);
      }

      if (!mounted) return;
      _showSnack(_isEdit ? 'Arazi güncellendi.' : 'Arazi eklendi.');
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Field save error: $e');
      if (!mounted) return;
      _showSnack('Arazi kaydedilemedi. Veritabanı izinlerini kontrol et.', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade500 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isSaving,
      child: Scaffold(
        backgroundColor: lightBackground,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
                    children: [
                      _buildMainCard(),
                      const SizedBox(height: 18),
                      _buildPhotosCard(),
                      const SizedBox(height: 18),
                      _buildTreesCard(),
                      const SizedBox(height: 18),
                      _buildAnimalsCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            decoration: BoxDecoration(
              color: cardWhite,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('İptal', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveField,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_isSaving ? 'Kaydediliyor' : 'Kaydet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
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

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Row(
        children: [
          InkWell(
            onTap: _isSaving ? null : () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cardWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: darkText, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEdit ? 'Araziyi Düzenle' : 'Yeni Arazi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: darkGreen, fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainCard() {
    return _card(
      title: 'Arazi Bilgileri',
      icon: Icons.map_rounded,
      child: Column(
        children: [
          _input(
            controller: _fieldNameCtrl,
            label: 'Tarla Adı',
            hint: 'Örn: Kuzey Bahçesi',
            icon: Icons.terrain_rounded,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Tarla adı zorunlu' : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _input(
                  controller: _cityCtrl,
                  label: 'Şehir / İlçe',
                  hint: 'Örn: Tekirdağ',
                  icon: Icons.location_city_rounded,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Şehir zorunlu' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _input(
                  controller: _areaCtrl,
                  label: 'Alan (m²)',
                  hint: 'Örn: 4000',
                  icon: Icons.square_foot_rounded,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) == null) ? 'Alan giriniz' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _input(
            controller: _addressCtrl,
            label: 'Açık Adres',
            hint: 'Mahalle, sokak, no...',
            icon: Icons.pin_drop_rounded,
            maxLines: 3,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Adres zorunlu' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosCard() {
    return _card(
      title: 'Fotoğraflar',
      icon: Icons.photo_library_rounded,
      trailing: Text('${_photos.length}/10', style: const TextStyle(color: mutedText, fontWeight: FontWeight.w800, fontSize: 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _isPickingPhotos ? null : _pickPhotos,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: primaryGreen.withOpacity(0.10), shape: BoxShape.circle),
                    child: _isPickingPhotos
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(strokeWidth: 2, color: primaryGreen),
                          )
                        : const Icon(Icons.add_photo_alternate_rounded, color: primaryGreen),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _photos.isEmpty ? 'Araziyi hatırlamak için fotoğraf ekle' : 'Yeni fotoğraf ekle',
                      style: const TextStyle(color: darkText, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: mutedText),
                ],
              ),
            ),
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final source = _photos[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(width: 92, height: 92, child: _imageFromSource(source)),
                      ),
                      Positioned(
                        top: 5,
                        right: 5,
                        child: InkWell(
                          onTap: () => setState(() => _photos.removeAt(index)),
                          borderRadius: BorderRadius.circular(99),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 17),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTreesCard() {
    return _card(
      title: 'Ağaç Türleri ve Adetleri',
      icon: Icons.park_rounded,
      child: Column(
        children: [
          ...List.generate(_treeEntries.length, (index) {
            return _treeRow(
              entry: _treeEntries[index],
              canRemove: _treeEntries.length > 1,
              onRemove: () {
                final removed = _treeEntries.removeAt(index);
                removed.dispose();
                setState(() {});
              },
            );
          }),
          _addRowButton(label: 'Ağaç Ekle', onTap: () => setState(() => _treeEntries.add(_TreeEntry()))),
        ],
      ),
    );
  }

  Widget _buildAnimalsCard() {
    return _card(
      title: 'Hayvan Envanteri',
      icon: Icons.pets_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(18)),
            child: CheckboxListTile(
              value: _hasAnimals,
              activeColor: primaryGreen,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: const Text(
                'Bu arazide hayvancılık var mı?',
                style: TextStyle(color: darkText, fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
              onChanged: (value) => setState(() => _hasAnimals = value ?? false),
            ),
          ),
          if (_hasAnimals) ...[
            const SizedBox(height: 14),
            ...List.generate(_animalEntries.length, (index) {
              return _animalRow(
                entry: _animalEntries[index],
                canRemove: _animalEntries.length > 1,
                onRemove: () {
                  final removed = _animalEntries.removeAt(index);
                  removed.dispose();
                  setState(() {});
                },
              );
            }),
            _addRowButton(label: 'Hayvan Ekle', onTap: () => setState(() => _animalEntries.add(_AnimalEntry()))),
          ],
        ],
      ),
    );
  }

  Widget _treeRow({required _TreeEntry entry, required bool canRemove, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _plainInput(controller: entry.typeCtrl, hint: 'Tür', keyboardType: TextInputType.text),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _plainInput(controller: entry.countCtrl, hint: 'Adet', keyboardType: TextInputType.number),
          ),
          const SizedBox(width: 10),
          _removeButton(enabled: canRemove, onTap: onRemove),
        ],
      ),
    );
  }

  Widget _animalRow({required _AnimalEntry entry, required bool canRemove, required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _plainInput(
                  controller: entry.typeCtrl,
                  hint: 'Tür',
                  keyboardType: TextInputType.text,
                ),
              ),
              const SizedBox(width: 8),
              _removeButton(enabled: canRemove, onTap: onRemove),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _plainInput(controller: entry.maleCtrl, hint: 'Erkek', keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              Expanded(child: _plainInput(controller: entry.femaleCtrl, hint: 'Dişi', keyboardType: TextInputType.number)),
            ],
          ),
          const SizedBox(height: 10),
          _plainInput(controller: entry.notesCtrl, hint: 'Notlar', keyboardType: TextInputType.text),
        ],
      ),
    );
  }

  Widget _removeButton({required bool enabled, required VoidCallback onTap}) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 50,
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFFFF1F2) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: enabled ? Colors.red.shade300 : const Color(0xFFE2E8F0)),
        ),
        child: Icon(Icons.close_rounded, color: enabled ? Colors.red.shade500 : mutedText),
      ),
    );
  }

  Widget _addRowButton({required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: darkText),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: darkText, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required IconData icon, required Widget child, Widget? trailing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 7)),
        ],
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: darkText, size: 23),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(color: darkText, fontSize: 17, fontWeight: FontWeight.w900))),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: darkText, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: mutedText),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: primaryGreen, width: 1.5)),
      ),
    );
  }

  Widget _plainInput({required TextEditingController controller, required String hint, required TextInputType keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: darkText, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryGreen, width: 1.5)),
      ),
    );
  }
}

class _TreeSummary {
  final String type;
  final int count;

  _TreeSummary({required this.type, required this.count});
}

class _AnimalSummary {
  final String type;
  final int total;
  final int? male;
  final int? female;
  final String notes;

  _AnimalSummary({required this.type, required this.total, this.male, this.female, this.notes = ''});
}

class _TreeEntry {
  final TextEditingController typeCtrl;
  final TextEditingController countCtrl;

  _TreeEntry({String type = '', String count = ''})
      : typeCtrl = TextEditingController(text: type),
        countCtrl = TextEditingController(text: count);

  void dispose() {
    typeCtrl.dispose();
    countCtrl.dispose();
  }
}

class _AnimalEntry {
  final TextEditingController typeCtrl;
  final TextEditingController totalCtrl;
  final TextEditingController maleCtrl;
  final TextEditingController femaleCtrl;
  final TextEditingController notesCtrl;

  _AnimalEntry({String type = '', String total = '', String male = '', String female = '', String notes = ''})
      : typeCtrl = TextEditingController(text: type),
        totalCtrl = TextEditingController(text: total),
        maleCtrl = TextEditingController(text: male),
        femaleCtrl = TextEditingController(text: female),
        notesCtrl = TextEditingController(text: notes);

  void dispose() {
    typeCtrl.dispose();
    totalCtrl.dispose();
    maleCtrl.dispose();
    femaleCtrl.dispose();
    notesCtrl.dispose();
  }
}
