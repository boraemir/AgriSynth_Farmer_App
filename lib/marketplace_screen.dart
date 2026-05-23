import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'farmer_app_drawer.dart';
import 'messages.dart';
import 'supabase_service.dart';

class MarketplaceScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const MarketplaceScreen({super.key, required this.userData});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF047857);
  static const Color deepText = Color(0xFF0F172A);
  static const Color mutedText = Color(0xFF64748B);
  static const Color softBg = Color(0xFFF8FAFC);
  static const Color softGreen = Color(0xFFECFDF5);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const String listingPhotosBucket = 'listing-photos';

  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  final Map<String, Future<String>> _photoUrlCache = <String, Future<String>>{};

  bool _isLoading = true;
  bool _isSaving = false;
  String _viewMode = 'browse'; // browse | mine | purchased | requests
  String _typeFilter = 'all';
  String _categoryFilter = 'all';
  String _sort = 'newest';
  String _search = '';
  double? _minPrice;
  double? _maxPrice;
  final Set<String> _deletingIds = <String>{};
  final Set<String> _processingPurchaseRequestIds = <String>{};

  List<Map<String, dynamic>> _allListings = [];
  List<Map<String, dynamic>> _myPurchases = [];
  List<Map<String, dynamic>> _purchaseRequests = [];

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    if (fromData.isNotEmpty) return fromData;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  String get _role => (widget.userData['rol'] ?? widget.userData['role'] ?? '').toString().trim().toLowerCase();
  bool get _isVet => _role == 'doktor' || _role == 'veteriner' || _role == 'doctor';

  String get _firstName => (widget.userData['ad'] ?? widget.userData['first_name'] ?? '').toString().trim();
  String get _lastName => (widget.userData['soyad'] ?? widget.userData['last_name'] ?? '').toString().trim();
  String get _fullName {
    final name = '$_firstName $_lastName'.trim();
    if (name.isNotEmpty) return name;
    final username = (widget.userData['username'] ?? '').toString().trim();
    return username.isNotEmpty ? username : 'Kullanıcı';
  }

  static const List<_MarketplaceCategory> _categories = [
    _MarketplaceCategory('all', 'Tüm Kategoriler', Icons.layers_rounded),
    _MarketplaceCategory('land', 'Arazi', Icons.landscape_rounded),
    _MarketplaceCategory('fruit', 'Meyve / Mahsul', Icons.local_florist_rounded),
    _MarketplaceCategory('animal', 'Hayvan', Icons.pets_rounded),
    _MarketplaceCategory('tree', 'Ağaç / Fidan', Icons.park_rounded),
    _MarketplaceCategory('equipment', 'Ekipman', Icons.agriculture_rounded),
    _MarketplaceCategory('veteriner', 'Veteriner / Sağlık', Icons.medical_services_rounded),
    _MarketplaceCategory('other', 'Diğer', Icons.inventory_2_rounded),
  ];

  List<Map<String, dynamic>> get _filteredListings {
    final q = _search.trim().toLowerCase();
    var items = _allListings.where((item) {
      final isMine = (item['user_id'] ?? '').toString() == _userId;
      final type = (item['listing_type'] ?? '').toString();
      final category = (item['category'] ?? '').toString();
      final price = _toDouble(item['price']);

      if (_viewMode == 'mine' && !isMine) return false;
      if (_typeFilter == 'sell' && type != 'sell') return false;
      if (_typeFilter == 'buy' && type != 'buy') return false;
      if (_categoryFilter != 'all' && category != _categoryFilter) return false;

      if (_minPrice != null && price != null && price < _minPrice!) return false;
      if (_minPrice != null && price == null) return false;
      if (_maxPrice != null && price != null && price > _maxPrice!) return false;
      if (_maxPrice != null && price == null) return false;

      if (q.isEmpty) return true;
      final haystack = [
        item['title'],
        item['description'],
        item['location'],
        item['ownerName'],
        _categoryLabel(category),
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return haystack.contains(q);
    }).toList();

    switch (_sort) {
      case 'oldest':
        items.sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
        break;
      case 'price-asc':
        items.sort((a, b) => (_toDouble(a['price']) ?? 0).compareTo(_toDouble(b['price']) ?? 0));
        break;
      case 'price-desc':
        items.sort((a, b) => (_toDouble(b['price']) ?? 0).compareTo(_toDouble(a['price']) ?? 0));
        break;
      case 'newest':
      default:
        items.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
        break;
    }
    return items;
  }



  List<Map<String, dynamic>> get _filteredPurchases {
    final q = _search.trim().toLowerCase();
    var items = _myPurchases.where((purchase) {
      if (q.isEmpty) return true;
      final haystack = [
        purchase['title'],
        purchase['location'],
        purchase['sellerName'],
        purchase['statusLabel'],
        _categoryLabel((purchase['category'] ?? 'other').toString()),
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return haystack.contains(q);
    }).toList();

    switch (_sort) {
      case 'oldest':
        items.sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
        break;
      case 'price-asc':
        items.sort((a, b) => (_toDouble(a['price']) ?? 0).compareTo(_toDouble(b['price']) ?? 0));
        break;
      case 'price-desc':
        items.sort((a, b) => (_toDouble(b['price']) ?? 0).compareTo(_toDouble(a['price']) ?? 0));
        break;
      case 'newest':
      default:
        items.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
        break;
    }
    return items;
  }


  List<Map<String, dynamic>> get _filteredPurchaseRequests {
    final q = _search.trim().toLowerCase();
    var items = _purchaseRequests.where((request) {
      if (q.isEmpty) return true;
      final haystack = [
        request['title'],
        request['message'],
        request['buyerName'],
        request['buyerEmail'],
        request['buyerPhone'],
        request['buyerCity'],
        request['location'],
        request['statusLabel'],
        _categoryLabel((request['category'] ?? 'other').toString()),
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return haystack.contains(q);
    }).toList();

    switch (_sort) {
      case 'oldest':
        items.sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));
        break;
      case 'price-asc':
        items.sort((a, b) => (_toDouble(a['price']) ?? 0).compareTo(_toDouble(b['price']) ?? 0));
        break;
      case 'price-desc':
        items.sort((a, b) => (_toDouble(b['price']) ?? 0).compareTo(_toDouble(a['price']) ?? 0));
        break;
      case 'newest':
      default:
        items.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
        break;
    }
    return items;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _search = _searchController.text);
    });
    _loadMarketplaceData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadMarketplaceData() async {
    await _loadListings();
    await _loadPurchases();
    await _loadPurchaseRequests();
  }

  Future<void> _loadPurchases() async {
    if (_userId.isEmpty) return;
    try {
      final rows = await SupabaseService()
          .client
          .from('purchases')
          .select('id,buyer_id,listing_id,seller_id,title,price,category,location,status,created_at')
          .eq('buyer_id', _userId)
          .order('created_at', ascending: false);

      final rawPurchases = List<Map<String, dynamic>>.from(rows as List);
      final sellerIds = rawPurchases
          .map((e) => (e['seller_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final sellers = <String, Map<String, dynamic>>{};
      if (sellerIds.isNotEmpty) {
        try {
          final sellerRows = await SupabaseService()
              .client
              .from('users')
              .select('id, ad, soyad, username, email, telefon, sehir, avatar_url, rol')
              .inFilter('id', sellerIds);
          for (final seller in List<Map<String, dynamic>>.from(sellerRows as List)) {
            sellers[(seller['id'] ?? '').toString()] = seller;
          }
        } catch (e) {
          debugPrint('Marketplace purchase sellers warning: $e');
        }
      }

      final listingIds = rawPurchases
          .map((e) => (e['listing_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final linkedListings = <String, Map<String, dynamic>>{};
      if (listingIds.isNotEmpty) {
        try {
          final listingRows = await SupabaseService()
              .client
              .from('listings')
              .select('id, listing_type, title, description, price, category, location, photos, created_at')
              .inFilter('id', listingIds);
          for (final listing in List<Map<String, dynamic>>.from(listingRows as List)) {
            linkedListings[(listing['id'] ?? '').toString()] = listing;
          }
        } catch (e) {
          debugPrint('Marketplace linked listing warning: $e');
        }
      }

      final normalized = rawPurchases.map((row) {
        final sellerId = (row['seller_id'] ?? '').toString();
        final seller = sellers[sellerId] ?? <String, dynamic>{};
        final status = (row['status'] ?? 'pending').toString();
        final listingId = (row['listing_id'] ?? '').toString();
        final linked = linkedListings[listingId] ?? <String, dynamic>{};
        final mergedCategory = _normalizeCategory((row['category'] ?? linked['category'] ?? 'other').toString());
        final photos = _parsePhotos(linked['photos']);
        return <String, dynamic>{
          ...row,
          'listing': linked,
          'title': (row['title'] ?? linked['title'] ?? 'Satın alma talebi').toString(),
          'price': row['price'] ?? linked['price'],
          'category': mergedCategory,
          'location': (row['location'] ?? linked['location'] ?? '').toString(),
          'description': (linked['description'] ?? '').toString(),
          'photosList': photos,
          'listingType': (linked['listing_type'] ?? 'sell').toString(),
          'sellerName': _ownerName(sellerId, seller),
          'sellerRoleLabel': _roleLabel((seller['rol'] ?? '').toString()),
          'sellerAvatar': (seller['avatar_url'] ?? '').toString(),
          'sellerEmail': (seller['email'] ?? '').toString(),
          'sellerPhone': (seller['telefon'] ?? '').toString(),
          'sellerCity': (seller['sehir'] ?? '').toString(),
          'statusLabel': _purchaseStatusLabel(status),
        };
      }).toList();

      if (mounted) setState(() => _myPurchases = normalized);
    } catch (e) {
      debugPrint('Marketplace purchases load warning: $e');
      if (mounted) setState(() => _myPurchases = []);
    }
  }


  Future<void> _loadPurchaseRequests() async {
    if (_userId.isEmpty) return;
    try {
      final rows = await SupabaseService()
          .client
          .from('notifications')
          .select('id,user_id,type,title,message,data,is_read,created_at')
          .eq('user_id', _userId)
          .eq('type', 'purchase_request')
          .order('created_at', ascending: false);

      final rawRequests = List<Map<String, dynamic>>.from(rows as List);

      Map<String, dynamic> readData(Map<String, dynamic> row) {
        final raw = row['data'];
        if (raw is Map<String, dynamic>) return raw;
        if (raw is Map) return Map<String, dynamic>.from(raw);
        if (raw is String && raw.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } catch (_) {}
        }
        return <String, dynamic>{};
      }

      final datas = <String, Map<String, dynamic>>{};
      for (final row in rawRequests) {
        datas[(row['id'] ?? '').toString()] = readData(row);
      }

      final buyerIds = datas.values
          .map((data) => (data['buyer_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final listingIds = datas.values
          .map((data) => (data['listing_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final purchaseIds = datas.values
          .map((data) => (data['purchase_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final buyers = <String, Map<String, dynamic>>{};
      if (buyerIds.isNotEmpty) {
        try {
          final buyerRows = await SupabaseService()
              .client
              .from('users')
              .select('id, ad, soyad, username, email, telefon, sehir, avatar_url, rol')
              .inFilter('id', buyerIds);
          for (final buyer in List<Map<String, dynamic>>.from(buyerRows as List)) {
            buyers[(buyer['id'] ?? '').toString()] = buyer;
          }
        } catch (e) {
          debugPrint('Marketplace request buyers warning: $e');
        }
      }

      final listings = <String, Map<String, dynamic>>{};
      if (listingIds.isNotEmpty) {
        try {
          final listingRows = await SupabaseService()
              .client
              .from('listings')
              .select('id, listing_type, title, description, price, category, location, photos, created_at')
              .inFilter('id', listingIds);
          for (final listing in List<Map<String, dynamic>>.from(listingRows as List)) {
            listings[(listing['id'] ?? '').toString()] = listing;
          }
        } catch (e) {
          debugPrint('Marketplace request listings warning: $e');
        }
      }

      final purchases = <String, Map<String, dynamic>>{};
      if (purchaseIds.isNotEmpty) {
        try {
          final purchaseRows = await SupabaseService()
              .client
              .from('purchases')
              .select('id,buyer_id,listing_id,seller_id,title,price,category,location,status,created_at')
              .inFilter('id', purchaseIds);
          for (final purchase in List<Map<String, dynamic>>.from(purchaseRows as List)) {
            purchases[(purchase['id'] ?? '').toString()] = purchase;
          }
        } catch (e) {
          debugPrint('Marketplace request purchases warning: $e');
        }
      }

      final normalized = rawRequests.map((row) {
        final rowId = (row['id'] ?? '').toString();
        final data = datas[rowId] ?? <String, dynamic>{};
        final buyerId = (data['buyer_id'] ?? '').toString();
        final listingId = (data['listing_id'] ?? '').toString();
        final purchaseId = (data['purchase_id'] ?? '').toString();
        final buyer = buyers[buyerId] ?? <String, dynamic>{};
        final listing = listings[listingId] ?? <String, dynamic>{};
        final purchase = purchases[purchaseId] ?? <String, dynamic>{};
        final status = (purchase['status'] ?? data['status'] ?? 'pending').toString();
        final category = _normalizeCategory((purchase['category'] ?? data['category'] ?? listing['category'] ?? 'other').toString());
        final photos = _parsePhotos(listing['photos']);
        final title = (data['listing_title'] ?? purchase['title'] ?? listing['title'] ?? 'Satın alma talebi').toString();
        final location = (purchase['location'] ?? data['location'] ?? listing['location'] ?? '').toString();
        final buyerName = _ownerName(buyerId, buyer).replaceAll('İlan Sahibi', 'Alıcı');
        return <String, dynamic>{
          ...row,
          'notificationId': rowId,
          'dataMap': data,
          'purchase_id': purchaseId,
          'listing_id': listingId,
          'buyer_id': buyerId,
          'buyer': buyer,
          'listing': listing,
          'purchase': purchase,
          'title': title,
          'message': (row['message'] ?? '').toString(),
          'price': purchase['price'] ?? data['price'] ?? listing['price'],
          'category': category,
          'location': location,
          'description': (listing['description'] ?? '').toString(),
          'photosList': photos,
          'status': status,
          'statusLabel': _purchaseStatusLabel(status),
          'buyerName': buyerName,
          'buyerRoleLabel': _roleLabel((buyer['rol'] ?? '').toString()),
          'buyerAvatar': (buyer['avatar_url'] ?? '').toString(),
          'buyerEmail': (buyer['email'] ?? '').toString(),
          'buyerPhone': (buyer['telefon'] ?? '').toString(),
          'buyerCity': (buyer['sehir'] ?? '').toString(),
          'is_read': row['is_read'] == true,
        };
      }).toList();

      if (mounted) setState(() => _purchaseRequests = normalized);
    } catch (e) {
      debugPrint('Marketplace purchase requests load warning: $e');
      if (mounted) setState(() => _purchaseRequests = []);
    }
  }

  Future<void> _loadListings() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final rows = await SupabaseService()
          .client
          .from('listings')
          .select('*')
          .order('created_at', ascending: false);

      final rawListings = List<Map<String, dynamic>>.from(rows as List)
          .where((row) => row['is_active'] == null || row['is_active'] == true)
          .toList();

      final userIds = rawListings
          .map((e) => (e['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final users = <String, Map<String, dynamic>>{};
      if (userIds.isNotEmpty) {
        try {
          final userRows = await SupabaseService()
              .client
              .from('users')
              .select('id, ad, soyad, username, email, telefon, sehir, avatar_url, rol')
              .inFilter('id', userIds);
          for (final user in List<Map<String, dynamic>>.from(userRows as List)) {
            users[(user['id'] ?? '').toString()] = user;
          }
        } catch (e) {
          debugPrint('Marketplace users load warning: $e');
        }
      }

      final normalized = rawListings.map((row) {
        final ownerId = (row['user_id'] ?? '').toString();
        final owner = users[ownerId] ?? <String, dynamic>{};
        final type = _normalizeType((row['listing_type'] ?? 'sell').toString());
        final category = _normalizeCategory((row['category'] ?? 'other').toString());
        final photos = _extractPhotos(row);
        final ownerName = _ownerName(ownerId, owner);
        return <String, dynamic>{
          ...row,
          'listing_type': type,
          'category': category,
          'photosList': photos,
          'owner': owner,
          'ownerName': ownerName,
          'ownerRoleLabel': _roleLabel((owner['rol'] ?? '').toString()),
          'ownerAvatar': (owner['avatar_url'] ?? '').toString(),
        };
      }).toList();

      if (!mounted) return;
      setState(() => _allListings = normalized);
    } catch (e) {
      debugPrint('Marketplace load error: $e');
      if (mounted) _showSnackBar('İlanlar yüklenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _ownerName(String ownerId, Map<String, dynamic> owner) {
    final ad = (owner['ad'] ?? '').toString().trim();
    final soyad = (owner['soyad'] ?? '').toString().trim();
    final full = '$ad $soyad'.trim();
    if (full.isNotEmpty) return full;
    final username = (owner['username'] ?? '').toString().trim();
    if (username.isNotEmpty) return username;
    if (ownerId == _userId) return _fullName;
    return 'İlan Sahibi';
  }

  List<String> _extractPhotos(Map<String, dynamic> row) {
    final result = <String>[];
    void add(dynamic value) {
      for (final p in _parsePhotos(value)) {
        if (p.isNotEmpty && !result.contains(p)) result.add(p);
      }
    }

    add(row['photos']);
    add(row['photo']);
    add(row['photo_url']);
    add(row['image']);
    add(row['image_url']);
    add(row['images']);
    add(row['cover_photo']);
    add(row['cover_photo_url']);
    add(row['media']);
    add(row['media_urls']);
    return result;
  }

  List<String> _parsePhotos(dynamic raw) {
    if (raw == null) return [];
    final photos = <String>[];

    void addOne(dynamic value) {
      dynamic source = value;
      if (value is Map) {
        source = value['url'] ?? value['publicUrl'] ?? value['public_url'] ?? value['path'];
      }
      final normalized = _normalizePhotoValue(source);
      if (normalized.isNotEmpty && !photos.contains(normalized)) photos.add(normalized);
    }

    if (raw is List) {
      for (final item in raw) addOne(item);
      return photos;
    }
    if (raw is Map) {
      addOne(raw);
      return photos;
    }

    final value = raw.toString().trim();
    if (value.isEmpty || value == '[]' || value.toLowerCase() == 'null') return [];

    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        for (final item in decoded) addOne(item);
      } else {
        addOne(decoded);
      }
      return photos;
    } catch (_) {}

    final cleaned = value
        .replaceAll(RegExp(r'^\[+'), '')
        .replaceAll(RegExp(r'\]+$'), '')
        .trim();
    if (cleaned.contains('\n')) {
      for (final part in cleaned.split('\n')) addOne(part);
      return photos;
    }
    if (cleaned.contains(',') && !cleaned.startsWith('data:image')) {
      for (final part in cleaned.split(',')) addOne(part);
      return photos;
    }
    addOne(cleaned);
    return photos;
  }

  String _normalizePhotoValue(dynamic value) {
    if (value == null) return '';
    var photo = value.toString().trim();
    if (photo.isEmpty || photo.toLowerCase() == 'null') return '';
    photo = photo
        .replaceAll(RegExp(r'^\[+'), '')
        .replaceAll(RegExp(r'\]+$'), '')
        .replaceAll(RegExp(r'''^["']+'''), '')
        .replaceAll(RegExp(r'''["']+$'''), '')
        .trim();
    if (photo.startsWith('http://') || photo.startsWith('https://') || photo.startsWith('data:image')) return photo;

    var path = photo;
    if (path.startsWith('$listingPhotosBucket/')) {
      path = path.substring(listingPhotosBucket.length + 1);
    }
    return SupabaseService().client.storage.from(listingPhotosBucket).getPublicUrl(path);
  }

  Future<String> _displayPhotoUrl(String raw) {
    final key = raw.trim();
    return _photoUrlCache.putIfAbsent(key, () async {
      if (key.isEmpty || key.startsWith('data:image')) return key;
      final path = key.startsWith('http') ? _storagePathFromUrl(key) : key;
      if (path == null || path.isEmpty) return key;
      try {
        return await SupabaseService()
            .client
            .storage
            .from(listingPhotosBucket)
            .createSignedUrl(path, 60 * 60)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        return key.startsWith('http')
            ? key
            : SupabaseService().client.storage.from(listingPhotosBucket).getPublicUrl(path);
      }
    });
  }

  String? _storagePathFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.map(Uri.decodeComponent).toList();
      final bucketIndex = segments.indexOf(listingPhotosBucket);
      if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return null;
      return segments.sublist(bucketIndex + 1).join('/');
    } catch (_) {
      return null;
    }
  }

  String _normalizeType(String value) {
    final v = value.toLowerCase().trim();
    if (v == 'buy' || v == 'aranıyor' || v == 'araniyor') return 'buy';
    return 'sell';
  }

  String _normalizeCategory(String value) {
    final v = value.toLowerCase().trim();
    switch (v) {
      case 'land':
      case 'arazi':
      case 'tarla':
        return 'land';
      case 'fruit':
      case 'meyve':
      case 'mahsul':
      case 'meyve / mahsul':
        return 'fruit';
      case 'animal':
      case 'hayvan':
        return 'animal';
      case 'tree':
      case 'ağaç':
      case 'agac':
      case 'fidan':
      case 'ağaç/fidan':
        return 'tree';
      case 'equipment':
      case 'ekipman':
      case 'makine':
        return 'equipment';
      case 'veteriner':
      case 'veterinary':
      case 'saglik':
      case 'sağlık':
      case 'veteriner / sağlık':
      case 'veteriner/sağlık':
        return 'veteriner';
      default:
        return 'other';
    }
  }

  String _categoryLabel(String key) {
    return _categories.firstWhere((c) => c.key == key, orElse: () => _categories.last).label;
  }

  IconData _categoryIcon(String key) {
    return _categories.firstWhere((c) => c.key == key, orElse: () => _categories.last).icon;
  }

  String _typeLabel(String key) => key == 'buy' ? 'Aranıyor' : 'Satılık';

  String _primaryListingBadgeLabel(String type, String category) {
    return category == 'veteriner' ? 'Veteriner / Sağlık' : _typeLabel(type);
  }

  Color _primaryListingBadgeColor(String type, String category) {
    if (category == 'veteriner') return const Color(0xFF6366F1);
    return type == 'sell' ? primaryGreen : const Color(0xFF3B82F6);
  }

  String _purchaseStatusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'approved':
      case 'accepted':
      case 'completed':
        return 'Onaylandı';
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return 'Reddedildi';
      case 'pending':
      default:
        return 'Beklemede';
    }
  }

  Color _purchaseStatusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'approved':
      case 'accepted':
      case 'completed':
        return primaryGreen;
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return Colors.redAccent;
      case 'pending':
      default:
        return const Color(0xFFF59E0B);
    }
  }



  bool _isRejectedPurchaseStatus(String status) {
    final normalized = status.toLowerCase().trim();
    return normalized == 'rejected' || normalized == 'cancelled' || normalized == 'canceled';
  }

  bool _isApprovedPurchaseStatus(String status) {
    final normalized = status.toLowerCase().trim();
    return normalized == 'approved' || normalized == 'accepted' || normalized == 'completed';
  }

  String _roleLabel(String value) {
    switch (value.toLowerCase().trim()) {
      case 'ciftci':
      case 'çiftçi':
      case 'farmer':
        return 'Çiftçi';
      case 'doktor':
      case 'veteriner':
      case 'doctor':
        return 'Veteriner';
      case 'user':
      case 'normal':
        return 'Bireysel Kullanıcı';
      default:
        return 'Bireysel Kullanıcı';
    }
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }

  DateTime _dateOf(Map<String, dynamic> row) {
    return DateTime.tryParse((row['created_at'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _formatDate(DateTime dt) {
    const months = ['', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatMoney(dynamic value) {
    final number = _toDouble(value);
    if (number == null) return 'Fiyat belirtilmemiş';
    final asInt = number.round();
    final text = asInt.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
    }
    return '${buffer.toString()} ₺';
  }

  double? _parsePrice(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9,\.]'), '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<List<XFile>> _pickListingPhotos(int remaining) async {
    if (remaining <= 0) return [];
    try {
      final files = await _imagePicker.pickMultiImage(
        imageQuality: 68,
        maxWidth: 1280,
        maxHeight: 1280,
        requestFullMetadata: false,
      );
      return files.take(remaining).toList();
    } catch (e) {
      if (mounted) _showSnackBar('Fotoğraf seçilemedi: $e', isError: true);
      return [];
    }
  }

  Future<String> _uploadListingPhoto(XFile file) async {
    final userId = _userId;
    if (userId.isEmpty) throw Exception('Oturum bilgisi bulunamadı.');

    final bytes = await file.readAsBytes().timeout(const Duration(seconds: 15));
    if (bytes.isEmpty) throw Exception('Fotoğraf okunamadı.');
    const maxBytes = 8 * 1024 * 1024;
    if (bytes.length > maxBytes) throw Exception('Fotoğraf çok büyük. 8 MB altında bir görsel seç.');

    final original = file.name.trim().isEmpty ? 'photo.jpg' : file.name.trim();
    final ext = original.contains('.')
        ? original.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
        : 'jpg';
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final nameWithoutExt = original.contains('.') ? original.substring(0, original.lastIndexOf('.')) : original;
    final safeName = nameWithoutExt
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final fileName = safeName.isEmpty ? 'photo' : safeName;
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_${fileName}.$safeExt';

    await SupabaseService()
        .client
        .storage
        .from(listingPhotosBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: _contentTypeFor(safeExt),
          ),
        )
        .timeout(const Duration(seconds: 45));

    return SupabaseService().client.storage.from(listingPhotosBucket).getPublicUrl(path);
  }

  String _contentTypeFor(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _openListingForm({Map<String, dynamic>? listing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MarketplaceFormPage(
          listing: listing,
          categories: _categories.where((c) => c.key != 'all').toList(),
          defaultCategory: _isVet ? 'veteriner' : 'land',
          isVeterinarian: _isVet,
          buildPhoto: _buildPhoto,
          pickPhotos: _pickListingPhotos,
          save: _saveListing,
        ),
      ),
    );
    if (saved == true) await _loadListings();
  }

  Future<void> _saveListing({
    required Map<String, dynamic>? listing,
    required String listingType,
    required String category,
    required String title,
    required double? price,
    required String location,
    required String description,
    required List<String> existingPhotos,
    required List<XFile> newPhotos,
  }) async {
    if (_userId.isEmpty) throw Exception('Oturum bulunamadı.');
    if (title.trim().isEmpty || location.trim().isEmpty) {
      throw Exception('Başlık ve konum zorunludur.');
    }

    final uploaded = <String>[];
    for (final file in newPhotos) {
      uploaded.add(await _uploadListingPhoto(file));
    }
    final photos = <String>[...existingPhotos, ...uploaded].take(5).toList();

    final basePayload = <String, dynamic>{
      'user_id': _userId,
      'listing_type': listingType,
      'category': category,
      'title': title.trim(),
      'price': price,
      'location': location.trim(),
      'description': description.trim().isEmpty ? null : description.trim(),
      'photos': jsonEncode(photos),
    };

    final payloadWithOptionalColumns = <String, dynamic>{
      ...basePayload,
      'is_active': true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    Future<void> runInsertOrUpdate(Map<String, dynamic> payload) async {
      if (listing == null) {
        await SupabaseService().client.from('listings').insert(payload).timeout(const Duration(seconds: 25));
      } else {
        await SupabaseService()
            .client
            .from('listings')
            .update(payload)
            .eq('id', (listing['id'] ?? '').toString())
            .eq('user_id', _userId)
            .timeout(const Duration(seconds: 25));
      }
    }

    try {
      await runInsertOrUpdate(payloadWithOptionalColumns);
    } catch (_) {
      await runInsertOrUpdate(basePayload);
    }
  }

  Future<void> _deleteListing(Map<String, dynamic> listing) async {
    final id = (listing['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            title: const Text('İlanı sil'),
            content: Text('"${listing['title'] ?? 'İlan'}" ilanını silmek istediğine emin misin?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                child: const Text('Sil'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _deletingIds.add(id));
    try {
      try {
        await SupabaseService()
            .client
            .from('listings')
            .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', id)
            .eq('user_id', _userId);
      } catch (_) {
        await SupabaseService().client.from('listings').delete().eq('id', id).eq('user_id', _userId);
      }
      _showSnackBar('İlan kaldırıldı.');
      await _loadListings();
    } catch (e) {
      _showSnackBar('İlan silinemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _deletingIds.remove(id));
    }
  }

  Future<void> _openPurchaseDetail(Map<String, dynamic> purchase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PurchaseDetailPage(
          purchase: purchase,
          buildPhoto: _buildPhoto,
          categoryLabel: _categoryLabel,
          categoryIcon: _categoryIcon,
          roleLabel: _roleLabel,
          formatMoney: _formatMoney,
          formatDate: _formatDate,
          formatTime: _formatTime,
          onMessage: () => _messageSeller((purchase['seller_id'] ?? '').toString()),
        ),
      ),
    );
  }

  Future<void> _openDetail(Map<String, dynamic> listing) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _MarketplaceDetailPage(
          listing: listing,
          currentUserId: _userId,
          buildPhoto: _buildPhoto,
          categoryLabel: _categoryLabel,
          categoryIcon: _categoryIcon,
          typeLabel: _typeLabel,
          roleLabel: _roleLabel,
          formatMoney: _formatMoney,
          formatDate: _formatDate,
          onMessage: _messageSeller,
          onPurchase: _openPurchaseConfirm,
          onEdit: () async {
            Navigator.of(context).pop();
            await _openListingForm(listing: listing);
          },
          onDelete: () async {
            Navigator.of(context).pop();
            await _deleteListing(listing);
          },
        ),
      ),
    );
  }

  Future<void> _messageSeller(String sellerId) async {
    if (sellerId.isEmpty || sellerId == _userId) return;
    try {
      final id1 = _userId.compareTo(sellerId) <= 0 ? _userId : sellerId;
      final id2 = _userId.compareTo(sellerId) <= 0 ? sellerId : _userId;
      final existing = await SupabaseService()
          .client
          .from('chats')
          .select('id')
          .eq('user1_id', id1)
          .eq('user2_id', id2)
          .maybeSingle();
      if (existing == null) {
        await SupabaseService().client.from('chats').insert({'user1_id': id1, 'user2_id': id2});
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessagesScreen(
            userData: widget.userData,
            initialChatUserId: sellerId,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Sohbet başlatılamadı: $e', isError: true);
    }
  }

  Future<void> _openPurchaseConfirm(Map<String, dynamic> listing) async {
    final isMine = (listing['user_id'] ?? '').toString() == _userId;
    if (isMine) {
      _showSnackBar('Kendi ilanını satın alamazsın.', isError: true);
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Text('Satın Alma Onayı'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bu ürün için satıcıya satın alma talebi gönderilecek.'),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: softBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (listing['title'] ?? 'İlan').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: deepText),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatMoney(listing['price']),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: primaryGreen),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.shopping_cart_checkout_rounded),
                label: const Text('Satın Al'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      final purchase = await SupabaseService()
          .client
          .from('purchases')
          .insert({
            'buyer_id': _userId,
            'listing_id': listing['id'],
            'seller_id': listing['user_id'],
            'title': listing['title'],
            'price': _toDouble(listing['price']) ?? 0,
            'category': listing['category'],
            'location': listing['location'],
            'status': 'pending',
          })
          .select('id')
          .single();

      try {
        await SupabaseService().client.from('notifications').insert({
          'user_id': listing['user_id'],
          'type': 'purchase_request',
          'title': '🛒 Yeni Satın Alma Talebi',
          'message': '$_fullName, "${listing['title']}" ilanınızı satın almak istiyor.',
          'data': {
            'purchase_id': purchase['id'],
            'listing_id': listing['id'],
            'buyer_id': _userId,
            'buyer_name': _fullName,
            'listing_title': listing['title'],
            'category': listing['category'],
            'location': listing['location'],
            'price': _toDouble(listing['price']) ?? 0,
          },
        });
      } catch (notificationError) {
        debugPrint('Purchase notification warning: $notificationError');
      }
      await _loadPurchases();
      if (mounted) {
        setState(() {
          _viewMode = 'purchased';
          _typeFilter = 'all';
          _categoryFilter = 'all';
        });
      }
      _showSnackBar('Talebin iletildi. Satıcı onaylayacak.');
    } catch (e) {
      _showSnackBar('Satın alma talebi gönderilemedi: $e', isError: true);
    }
  }

  Widget _buildPhoto(
    String url, {
    required double height,
    required double width,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
  }) {
    final child = _photoWidget(url, height: height, width: width, fit: fit);
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius, child: child);
  }

  Widget _photoWidget(String url, {required double height, required double width, required BoxFit fit}) {
    final clean = url.trim();
    if (clean.startsWith('data:image')) {
      try {
        final base64Part = clean.substring(clean.indexOf(',') + 1);
        final bytes = base64Decode(base64Part);
        return Image.memory(bytes, height: height, width: width, fit: fit);
      } catch (_) {
        return _imageFallback(height: height, width: width);
      }
    }

    return FutureBuilder<String>(
      future: _displayPhotoUrl(clean),
      builder: (context, snapshot) {
        final displayUrl = snapshot.data ?? clean;
        if (displayUrl.isEmpty) return _imageFallback(height: height, width: width);
        return Image.network(
          displayUrl,
          height: height,
          width: width,
          fit: fit,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              height: height,
              width: width,
              color: const Color(0xFFEFF6F1),
              alignment: Alignment.center,
              child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
            );
          },
          errorBuilder: (_, error, __) {
            debugPrint('Listing image load error: $error');
            return _imageFallback(height: height, width: width);
          },
        );
      },
    );
  }

  Widget _imageFallback({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFFEFF6F1),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 38, color: primaryGreen.withOpacity(0.55)),
          const SizedBox(height: 8),
          const Text('Fotoğraf yok', style: TextStyle(color: mutedText, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showFilterSheet() {
    _minPriceController.text = _minPrice?.toStringAsFixed(0) ?? '';
    _maxPriceController.text = _maxPrice?.toStringAsFixed(0) ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        String tempSort = _sort;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Filtre ve Sıralama', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: deepText)),
                          ),
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Sıralama', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: deepText)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: tempSort,
                        decoration: _fieldDecoration('Sıralama seç'),
                        items: const [
                          DropdownMenuItem(value: 'newest', child: Text('En Yeni')),
                          DropdownMenuItem(value: 'oldest', child: Text('En Eski')),
                          DropdownMenuItem(value: 'price-asc', child: Text('Fiyat Artan')),
                          DropdownMenuItem(value: 'price-desc', child: Text('Fiyat Azalan')),
                        ],
                        onChanged: (v) => setModalState(() => tempSort = v ?? 'newest'),
                      ),
                      const SizedBox(height: 18),
                      const Text('Fiyat Aralığı', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: deepText)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: _minPriceController, keyboardType: TextInputType.number, decoration: _fieldDecoration('Min'))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: _maxPriceController, keyboardType: TextInputType.number, decoration: _fieldDecoration('Max'))),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _minPrice = null;
                                  _maxPrice = null;
                                  _sort = 'newest';
                                });
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded),
                              label: const Text('Temizle'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _sort = tempSort;
                                  _minPrice = _parsePrice(_minPriceController.text);
                                  _maxPrice = _parsePrice(_maxPriceController.text);
                                });
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryGreen,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('Uygula', style: TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: primaryGreen, width: 1.2)),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingPurchases = _viewMode == 'purchased';
    final showingPurchaseRequests = _viewMode == 'requests';
    final visible = _filteredListings;
    final visiblePurchases = _filteredPurchases;
    final visiblePurchaseRequests = _filteredPurchaseRequests;
    return Scaffold(
      backgroundColor: softBg,
      drawer: FarmerAppDrawer(userData: widget.userData, currentPage: FarmerDrawerPage.marketplace),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadMarketplaceData,
          color: primaryGreen,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildSearchAndFilters()),
              if (_isLoading && !showingPurchases && !showingPurchaseRequests)
                const SliverToBoxAdapter(child: _MarketplaceSkeleton())
              else if (showingPurchases && visiblePurchases.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildPurchasedEmptyState(),
                )
              else if (showingPurchaseRequests && visiblePurchaseRequests.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildPurchaseRequestsEmptyState(),
                )
              else if (!showingPurchases && !showingPurchaseRequests && visible.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                  sliver: SliverList.separated(
                    itemCount: showingPurchaseRequests ? visiblePurchaseRequests.length : (showingPurchases ? visiblePurchases.length : visible.length),
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      if (showingPurchaseRequests) return _buildPurchaseRequestCard(visiblePurchaseRequests[index]);
                      if (showingPurchases) return _buildPurchaseCard(visiblePurchases[index]);
                      return _buildListingCard(visible[index]);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: (showingPurchases || showingPurchaseRequests)
          ? null
          : FloatingActionButton.extended(
        onPressed: _isSaving ? null : () => _openListingForm(),
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        icon: _isSaving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_rounded),
        label: Text(_isSaving ? 'Kaydediliyor' : 'İlan Ver'),
      ),
    );
  }

  Widget _buildHeader() {
    final avatar = (widget.userData['avatar_url'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (context) => InkWell(
                  onTap: () => Scaffold.of(context).openDrawer(),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: _softShadow(),
                    ),
                    child: const Icon(Icons.menu_rounded, color: deepText, size: 30),
                  ),
                ),
              ),
            ),
            const IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.eco_rounded, color: primaryGreen, size: 27),
                  SizedBox(width: 8),
                  Text(
                    'AgriSynth',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: deepText,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: CircleAvatar(
                radius: 25,
                backgroundColor: softGreen,
                backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null,
                child: !avatar.startsWith('http')
                    ? Text(
                        _fullName.isNotEmpty ? _fullName[0].toUpperCase() : 'A',
                        style: const TextStyle(color: primaryGreen, fontWeight: FontWeight.w900),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF064E3B), Color(0xFF10B981)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: primaryGreen.withOpacity(0.22), blurRadius: 24, offset: const Offset(0, 14))],
      ),
      child: Stack(
        children: [
          Positioned(right: -18, top: -18, child: Icon(Icons.storefront_rounded, size: 122, color: Colors.white.withOpacity(0.10))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.16))),
                child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 22),
              const Text('İlan Pazarı', style: TextStyle(color: Colors.white, fontSize: 36, height: 1.08, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                _isVet
                    ? 'Veteriner / Sağlık ilanını yayınla, çiftçilerle doğrudan iletişim kur.'
                    : 'Tarım, hayvancılık ve veteriner hizmetleri için ilanları incele.',
                style: TextStyle(color: Colors.white.withOpacity(0.88), fontSize: 16, height: 1.45, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    final sellCount = _allListings.where((e) => e['listing_type'] == 'sell').length;
    final buyCount = _allListings.where((e) => e['listing_type'] == 'buy').length;
    final mineCount = _allListings.where((e) => (e['user_id'] ?? '').toString() == _userId).length;
    final requestCount = _purchaseRequests.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _modeButton(
                  keyName: 'mine',
                  label: 'İlanlarım',
                  count: mineCount,
                  icon: Icons.storefront_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _modeButton(
                  keyName: 'purchased',
                  label: 'Satın Alınanlar',
                  count: _myPurchases.length,
                  icon: Icons.shopping_bag_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _modeButton(
            keyName: 'requests',
            label: 'Satın Alma Talepleri',
            count: requestCount,
            icon: Icons.notifications_active_rounded,
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), boxShadow: _softShadow()),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'İlan ara...',
                prefixIcon: Icon(Icons.search_rounded),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _typeChip('all', 'Tümü', _allListings.length, Icons.grid_view_rounded),
                _typeChip('sell', 'Satılık', sellCount, Icons.trending_up_rounded),
                _typeChip('buy', 'Aranıyor', buyCount, Icons.search_rounded),
                _categoryQuickChip('veteriner', 'Veteriner / Sağlık', Icons.medical_services_rounded),
                _categoryQuickChip('animal', 'Hayvan', Icons.pets_rounded),
                _categoryQuickChip('equipment', 'Ekipman', Icons.agriculture_rounded),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final selected = _categoryFilter == cat.key;
                      return ChoiceChip(
                        selected: selected,
                        label: Text(cat.label),
                        avatar: Icon(cat.icon, size: 17, color: selected ? Colors.white : primaryGreen),
                        onSelected: (_) => setState(() {
                          _viewMode = 'browse';
                          _categoryFilter = cat.key;
                        }),
                        selectedColor: primaryGreen,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(color: selected ? Colors.white : deepText, fontWeight: FontWeight.w700, fontSize: 12.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: selected ? primaryGreen : borderColor)),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _roundIconButton(Icons.tune_rounded, _showFilterSheet),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _resultSummaryText(),
                  style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700),
                ),
              ),
              Text(_sortLabel(_sort), style: const TextStyle(color: primaryGreen, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }

  String _resultSummaryText() {
    if (_viewMode == 'purchased') return '${_filteredPurchases.length} satın alma kaydı';
    if (_viewMode == 'requests') return '${_filteredPurchaseRequests.length} satın alma talebi';
    if (_viewMode == 'mine') return '${_filteredListings.length} ilanım';
    return '${_filteredListings.length} ilan bulundu';
  }

  Widget _modeButton({required String keyName, required String label, required int count, required IconData icon}) {
    final selected = _viewMode == keyName;
    return InkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _viewMode = 'browse';
          } else {
            _viewMode = keyName;
            _typeFilter = 'all';
            if (keyName == 'purchased' || keyName == 'requests') _categoryFilter = 'all';
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? primaryGreen : borderColor),
          boxShadow: selected ? [BoxShadow(color: primaryGreen.withOpacity(0.20), blurRadius: 16, offset: const Offset(0, 9))] : _softShadow(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: selected ? Colors.white : primaryGreen),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: selected ? Colors.white : deepText, fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
            ),
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(0.18) : softGreen, borderRadius: BorderRadius.circular(999)),
              child: Text('$count', style: TextStyle(color: selected ? Colors.white : primaryGreen, fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryQuickChip(String key, String label, IconData icon) {
    final selected = _viewMode == 'browse' && _categoryFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() {
          _viewMode = 'browse';
          _categoryFilter = selected ? 'all' : key;
          _typeFilter = 'all';
        }),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primaryGreen : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? primaryGreen : borderColor),
            boxShadow: selected ? [BoxShadow(color: primaryGreen.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 8))] : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : mutedText),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: selected ? Colors.white : deepText, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String key, String label, int count, IconData icon) {
    final selected = _viewMode == 'browse' && _typeFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() {
          _viewMode = 'browse';
          _typeFilter = key;
        }),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? primaryGreen : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? primaryGreen : borderColor),
            boxShadow: selected ? [BoxShadow(color: primaryGreen.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 8))] : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : mutedText),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: selected ? Colors.white : deepText, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: selected ? Colors.white.withOpacity(0.18) : softBg, borderRadius: BorderRadius.circular(999)),
                child: Text('$count', style: TextStyle(color: selected ? Colors.white : mutedText, fontWeight: FontWeight.w800, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: _softShadow()),
        child: Icon(icon, color: deepText),
      ),
    );
  }

  String _sortLabel(String value) {
    switch (value) {
      case 'oldest':
        return 'En Eski';
      case 'price-asc':
        return 'Fiyat Artan';
      case 'price-desc':
        return 'Fiyat Azalan';
      case 'newest':
      default:
        return 'En Yeni';
    }
  }


  Widget _buildPurchaseRequestsEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: _softShadow()),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.notifications_active_outlined, color: primaryGreen, size: 54),
              SizedBox(height: 14),
              Text('Satın alma talebi yok', style: TextStyle(color: deepText, fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('İlanlarına gelen satın alma talepleri burada listelenir.', style: TextStyle(color: mutedText, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseRequestCard(Map<String, dynamic> request) {
    final title = (request['title'] ?? 'Satın alma talebi').toString();
    final buyerName = (request['buyerName'] ?? 'Alıcı').toString();
    final buyerEmail = (request['buyerEmail'] ?? '').toString().trim();
    final buyerPhone = (request['buyerPhone'] ?? '').toString().trim();
    final buyerCity = (request['buyerCity'] ?? '').toString().trim();
    final category = (request['category'] ?? 'other').toString();
    final status = (request['status'] ?? 'pending').toString().toLowerCase().trim();
    final statusLabel = (request['statusLabel'] ?? _purchaseStatusLabel(status)).toString();
    final statusColor = _purchaseStatusColor(status);
    final createdAt = _dateOf(request);
    final isRead = request['is_read'] == true;
    final requestId = _requestKey(request);
    final isProcessing = _processingPurchaseRequestIds.contains(requestId);
    final isPending = status == 'pending';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isRead ? borderColor : primaryGreen.withOpacity(0.35),
          width: isRead ? 1 : 1.4,
        ),
        boxShadow: _softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: isPending ? const Color(0xFFFFFBEB) : statusColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(bottom: BorderSide(color: statusColor.withOpacity(0.18))),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isPending
                        ? Icons.pending_actions_rounded
                        : _isRejectedPurchaseStatus(status)
                            ? Icons.cancel_rounded
                            : Icons.verified_rounded,
                    color: statusColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Satın Alma Talebi',
                        style: TextStyle(color: deepText, fontSize: 14.5, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatDate(createdAt)} • ${_formatTime(createdAt)}',
                        style: const TextStyle(color: mutedText, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (!isRead && isPending) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: primaryGreen.withOpacity(0.10), borderRadius: BorderRadius.circular(999)),
                    child: const Text('Yeni', style: TextStyle(color: primaryGreen, fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buyerAvatar(request, radius: 30),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            buyerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: deepText, fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '"$title" ilanını satın almak istiyor.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _miniInfo(Icons.category_rounded, _categoryLabel(category)),
                    const SizedBox(width: 8),
                    _miniInfo(Icons.location_on_rounded, buyerCity.isEmpty ? 'Şehir yok' : buyerCity),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: softBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.payments_rounded, color: primaryGreen, size: 19),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formatMoney(request['price']),
                              style: const TextStyle(color: primaryGreen, fontSize: 20, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _inlineContact(Icons.mail_outline_rounded, buyerEmail.isEmpty ? 'E-posta eklenmemiş' : buyerEmail),
                      const SizedBox(height: 7),
                      _inlineContact(Icons.phone_outlined, buyerPhone.isEmpty ? 'Telefon eklenmemiş' : buyerPhone),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isProcessing ? null : () => _messageSeller((request['buyer_id'] ?? '').toString()),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                        label: const Text('Mesaj'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: deepText,
                          side: const BorderSide(color: borderColor),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isProcessing ? null : () => _openPurchaseRequestDetail(request),
                        icon: const Icon(Icons.info_outline_rounded, size: 17),
                        label: const Text('Detay'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: darkGreen,
                          side: BorderSide(color: primaryGreen.withOpacity(0.25)),
                          backgroundColor: softGreen,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (isProcessing)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
                    child: const Center(
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: primaryGreen)),
                    ),
                  )
                else if (isPending)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmPurchaseRequestAction(request, 'completed'),
                          icon: const Icon(Icons.check_circle_rounded, size: 18),
                          label: const Text('Onayla'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _confirmPurchaseRequestAction(request, 'cancelled'),
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                          label: const Text('Reddet'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: statusColor.withOpacity(0.22))),
                    child: Row(
                      children: [
                        Icon(_isRejectedPurchaseStatus(status) ? Icons.cancel_rounded : Icons.check_circle_rounded, color: statusColor, size: 19),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            _isRejectedPurchaseStatus(status) ? 'Bu satın alma talebi reddedildi.' : 'Bu satın alma talebi onaylandı.',
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.w900),
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
    );
  }

  Widget _buyerAvatar(Map<String, dynamic> request, {double radius = 24}) {
    final avatar = (request['buyerAvatar'] ?? '').toString();
    final name = (request['buyerName'] ?? 'Alıcı').toString();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF3B82F6),
      backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null,
      child: !avatar.startsWith('http')
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'A', style: TextStyle(color: Colors.white, fontSize: radius * 0.82, fontWeight: FontWeight.w900))
          : null,
    );
  }

  Widget _inlineContact(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, color: mutedText, size: 16),
        const SizedBox(width: 7),
        Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700, fontSize: 12.5))),
      ],
    );
  }

  String _requestKey(Map<String, dynamic> request) {
    final purchaseId = (request['purchase_id'] ?? '').toString();
    if (purchaseId.isNotEmpty) return 'purchase:$purchaseId';
    final notificationId = (request['notificationId'] ?? request['id'] ?? '').toString();
    if (notificationId.isNotEmpty) return 'notification:$notificationId';
    return 'request:${request.hashCode}';
  }

  Future<void> _markPurchaseRequestRead(Map<String, dynamic> request) async {
    final id = (request['notificationId'] ?? request['id'] ?? '').toString();
    if (id.isEmpty || request['is_read'] == true) return;
    try {
      await SupabaseService().client.from('notifications').update({'is_read': true}).eq('id', id).eq('user_id', _userId);
      if (!mounted) return;
      setState(() {
        final index = _purchaseRequests.indexWhere((item) => (item['notificationId'] ?? item['id']).toString() == id);
        if (index != -1) _purchaseRequests[index] = {..._purchaseRequests[index], 'is_read': true};
      });
    } catch (e) {
      debugPrint('Purchase request read warning: $e');
    }
  }

  Future<void> _confirmPurchaseRequestAction(Map<String, dynamic> request, String nextStatus) async {
    final isApprove = nextStatus == 'completed' || nextStatus == 'approved' || nextStatus == 'accepted';
    final buyerName = (request['buyerName'] ?? 'Alıcı').toString();
    final title = (request['title'] ?? 'ilan').toString();

    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(isApprove ? 'Talebi onayla' : 'Talebi reddet'),
            content: Text(
              isApprove
                  ? '$buyerName kullanıcısının "$title" için gönderdiği satın alma talebini onaylamak istiyor musun?'
                  : '$buyerName kullanıcısının "$title" için gönderdiği satın alma talebini reddetmek istiyor musun?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: Icon(isApprove ? Icons.check_circle_rounded : Icons.cancel_rounded),
                label: Text(isApprove ? 'Onayla' : 'Reddet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isApprove ? primaryGreen : const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    await _updatePurchaseRequestStatus(request, nextStatus);
  }

  Future<void> _updatePurchaseRequestStatus(Map<String, dynamic> request, String nextStatus) async {
    final key = _requestKey(request);
    if (_processingPurchaseRequestIds.contains(key)) return;

    setState(() => _processingPurchaseRequestIds.add(key));

    final purchaseId = (request['purchase_id'] ?? '').toString();
    final notificationId = (request['notificationId'] ?? request['id'] ?? '').toString();
    final buyerId = (request['buyer_id'] ?? '').toString();
    final title = (request['title'] ?? 'İlan').toString();
    final currentData = request['dataMap'] is Map
        ? Map<String, dynamic>.from(request['dataMap'] as Map)
        : <String, dynamic>{};

    try {
      if (purchaseId.isNotEmpty) {
        await SupabaseService()
            .client
            .from('purchases')
            .update({'status': nextStatus})
            .eq('id', purchaseId)
            .eq('seller_id', _userId);
      }

      if (notificationId.isNotEmpty) {
        final updatedData = <String, dynamic>{
          ...currentData,
          'status': nextStatus,
          'responded_at': DateTime.now().toUtc().toIso8601String(),
          'responded_by': _userId,
        };
        await SupabaseService().client.from('notifications').update({
          'is_read': true,
          'data': updatedData,
        }).eq('id', notificationId).eq('user_id', _userId);
      }

      if (buyerId.isNotEmpty) {
        try {
          final approved = nextStatus == 'completed' || nextStatus == 'approved' || nextStatus == 'accepted';
          await SupabaseService().client.from('notifications').insert({
            'user_id': buyerId,
            'type': 'purchase_response',
            'title': approved ? '✅ Satın alma talebin onaylandı' : '❌ Satın alma talebin reddedildi',
            'message': approved
                ? '"$title" ilanı için satın alma talebin satıcı tarafından onaylandı.'
                : '"$title" ilanı için satın alma talebin satıcı tarafından reddedildi.',
            'data': {
              'purchase_id': purchaseId,
              'listing_id': (request['listing_id'] ?? '').toString(),
              'seller_id': _userId,
              'status': nextStatus,
              'listing_title': title,
            },
          });
        } catch (notificationError) {
          debugPrint('Purchase response notification warning: $notificationError');
        }
      }

      if (!mounted) return;
      setState(() {
        final index = _purchaseRequests.indexWhere((item) => _requestKey(item) == key);
        if (index != -1) {
          final dataMap = _purchaseRequests[index]['dataMap'] is Map
              ? Map<String, dynamic>.from(_purchaseRequests[index]['dataMap'] as Map)
              : <String, dynamic>{};
          dataMap['status'] = nextStatus;
          dataMap['responded_at'] = DateTime.now().toUtc().toIso8601String();
          _purchaseRequests[index] = {
            ..._purchaseRequests[index],
            'status': nextStatus,
            'statusLabel': _purchaseStatusLabel(nextStatus),
            'is_read': true,
            'dataMap': dataMap,
            'purchase': {
              ...Map<String, dynamic>.from((_purchaseRequests[index]['purchase'] as Map?) ?? const {}),
              'status': nextStatus,
            },
          };
        }
      });

      _showSnackBar(_isApprovedPurchaseStatus(nextStatus) ? 'Satın alma talebi onaylandı.' : 'Satın alma talebi reddedildi.');
    } catch (e) {
      _showSnackBar('Talep durumu güncellenemedi: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _processingPurchaseRequestIds.remove(key));
      }
    }
  }

  Future<void> _openPurchaseRequestDetail(Map<String, dynamic> request) async {
    await _markPurchaseRequestRead(request);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PurchaseRequestDetailPage(
          request: request,
          buildPhoto: _buildPhoto,
          categoryLabel: _categoryLabel,
          categoryIcon: _categoryIcon,
          formatMoney: _formatMoney,
          formatDate: _formatDate,
          formatTime: _formatTime,
          statusLabel: _purchaseStatusLabel,
          statusColor: _purchaseStatusColor,
          onMessage: () => _messageSeller((request['buyer_id'] ?? '').toString()),
          onApprove: () => _updatePurchaseRequestStatus(request, 'completed'),
          onReject: () => _updatePurchaseRequestStatus(request, 'cancelled'),
        ),
      ),
    );
  }

  Widget _buildPurchasedEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: _softShadow()),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.shopping_bag_outlined, color: primaryGreen, size: 54),
              SizedBox(height: 14),
              Text('Satın alınan ilan yok', style: TextStyle(color: deepText, fontSize: 20, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
              SizedBox(height: 8),
              Text('Satın alma talebi oluşturduğun ilanlar burada listelenir.', style: TextStyle(color: mutedText, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseCard(Map<String, dynamic> purchase) {
    final title = (purchase['title'] ?? 'Satın alma talebi').toString();
    final status = (purchase['status'] ?? 'pending').toString();
    final statusLabel = (purchase['statusLabel'] ?? _purchaseStatusLabel(status)).toString();
    final sellerName = (purchase['sellerName'] ?? 'Satıcı').toString();
    final category = (purchase['category'] ?? 'other').toString();
    final photos = List<String>.from(purchase['photosList'] ?? const <String>[]);
    final date = _dateOf(purchase);
    final color = _purchaseStatusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: borderColor),
        boxShadow: _softShadow(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: softGreen,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: borderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photos.isNotEmpty
                      ? _buildPhoto(
                          photos.first,
                          height: 70,
                          width: 70,
                          borderRadius: BorderRadius.circular(18),
                        )
                      : Container(
                          color: const Color(0xFFEFF6F1),
                          alignment: Alignment.center,
                          child: Icon(_categoryIcon(category), color: primaryGreen, size: 30),
                        ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: deepText, fontSize: 17, height: 1.25, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 7),
                      Text('Satıcı: $sellerName', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.25))),
                  child: Text(statusLabel, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _miniInfo(Icons.category_rounded, _categoryLabel(category)),
                const SizedBox(width: 8),
                _miniInfo(Icons.location_on_rounded, (purchase['location'] ?? 'Konum yok').toString()),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Talep tarihi: ${_formatDate(date)}', style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700, fontSize: 12.5))),
                Text(_formatMoney(purchase['price']), style: const TextStyle(color: primaryGreen, fontSize: 18, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _messageSeller((purchase['seller_id'] ?? '').toString()),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                    label: const Text('Mesaj'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: deepText,
                      side: const BorderSide(color: borderColor),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openPurchaseDetail(purchase),
                    icon: const Icon(Icons.info_outline_rounded, size: 17),
                    label: const Text('Detay'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: softGreen,
                      foregroundColor: darkGreen,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(color: softBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
        child: Row(
          children: [
            Icon(icon, color: mutedText, size: 15),
            const SizedBox(width: 6),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700, fontSize: 12.5))),
          ],
        ),
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> item) {

    final photos = List<String>.from(item['photosList'] ?? const []);
    final isMine = (item['user_id'] ?? '').toString() == _userId;
    final isDeleting = _deletingIds.contains((item['id'] ?? '').toString());
    final category = (item['category'] ?? 'other').toString();
    final type = (item['listing_type'] ?? 'sell').toString();
    final date = _dateOf(item);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: () => _openDetail(item),
        borderRadius: BorderRadius.circular(26),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: borderColor),
            boxShadow: _softShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 210,
                    width: double.infinity,
                    child: photos.isNotEmpty
                        ? _buildPhoto(photos.first, height: 210, width: double.infinity, borderRadius: const BorderRadius.vertical(top: Radius.circular(26)))
                        : ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                            child: _imageFallback(height: 210, width: double.infinity),
                          ),
                  ),
                  Positioned(top: 12, left: 12, child: _badge(_primaryListingBadgeLabel(type, category), _primaryListingBadgeColor(type, category), whiteText: true)),
                  if (category != 'veteriner')
                    Positioned(top: 12, right: 12, child: _darkBadge(_categoryLabel(category))),
                  if (photos.length > 1)
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(999)),
                        child: Row(
                          children: [
                            const Icon(Icons.image_rounded, color: Colors.white, size: 14),
                            const SizedBox(width: 5),
                            Text('${photos.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatMoney(item['price']), style: const TextStyle(color: primaryGreen, fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 7),
                    Text(
                      (item['title'] ?? 'İlan').toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: deepText, fontSize: 18, fontWeight: FontWeight.w900, height: 1.25),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: mutedText, size: 18),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            (item['location'] ?? 'Konum belirtilmemiş').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: mutedText, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
                ),
                child: Row(
                  children: [
                    _sellerAvatar(item, radius: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (item['ownerName'] ?? 'Kullanıcı').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: mutedText, fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(_formatDate(date), style: const TextStyle(color: mutedText, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (isMine)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: isDeleting ? null : () => _openListingForm(listing: item),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Düzenle'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF3B82F6),
                            side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.25)),
                            backgroundColor: const Color(0xFF3B82F6).withOpacity(0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 52,
                        child: OutlinedButton(
                          onPressed: isDeleting ? null : () => _deleteListing(item),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: Colors.redAccent.withOpacity(0.30)),
                            backgroundColor: Colors.redAccent.withOpacity(0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: isDeleting
                              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.delete_outline_rounded, size: 19),
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

  Widget _badge(String text, Color color, {bool whiteText = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: whiteText ? color.withOpacity(0.90) : color.withOpacity(0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.20))),
      child: Text(text, style: TextStyle(color: whiteText ? Colors.white : color, fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }

  Widget _darkBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.48), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _sellerAvatar(Map<String, dynamic> item, {double radius = 24}) {
    final avatar = (item['ownerAvatar'] ?? '').toString();
    final name = (item['ownerName'] ?? 'Kullanıcı').toString();
    return CircleAvatar(
      radius: radius,
      backgroundColor: primaryGreen,
      backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null,
      child: !avatar.startsWith('http')
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'K', style: TextStyle(color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.w900))
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(color: softGreen, borderRadius: BorderRadius.circular(30)),
              child: const Icon(Icons.inventory_2_outlined, color: primaryGreen, size: 42),
            ),
            const SizedBox(height: 18),
            const Text('İlan bulunamadı', style: TextStyle(color: deepText, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Filtreleri değiştirerek tekrar deneyebilirsin.', textAlign: TextAlign.center, style: TextStyle(color: mutedText, fontWeight: FontWeight.w600, height: 1.45)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _openListingForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Yeni İlan Ver'),
              style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ],
        ),
      ),
    );
  }

  List<BoxShadow> _softShadow() {
    return [BoxShadow(color: Colors.black.withOpacity(0.045), blurRadius: 18, offset: const Offset(0, 9))];
  }
}

class _MarketplaceCategory {
  final String key;
  final String label;
  final IconData icon;
  const _MarketplaceCategory(this.key, this.label, this.icon);
}

class _MarketplaceSkeleton extends StatelessWidget {
  const _MarketplaceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
      child: Column(
        children: List.generate(3, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 320,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: _MarketplaceScreenState.borderColor)),
            child: Column(
              children: [
                Container(height: 200, decoration: const BoxDecoration(color: Color(0xFFEFF4F0), borderRadius: BorderRadius.vertical(top: Radius.circular(26)))),
                const SizedBox(height: 18),
                Container(width: double.infinity, height: 18, margin: const EdgeInsets.symmetric(horizontal: 18), decoration: BoxDecoration(color: const Color(0xFFEFF4F0), borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 12),
                Container(width: double.infinity, height: 14, margin: const EdgeInsets.symmetric(horizontal: 18), decoration: BoxDecoration(color: const Color(0xFFEFF4F0), borderRadius: BorderRadius.circular(10))),
              ],
            ),
          );
        }),
      ),
    );
  }
}


class _PurchaseDetailPage extends StatelessWidget {
  final Map<String, dynamic> purchase;
  final Widget Function(String url, {required double height, required double width, BoxFit fit, BorderRadius? borderRadius}) buildPhoto;
  final String Function(String category) categoryLabel;
  final IconData Function(String category) categoryIcon;
  final String Function(String role) roleLabel;
  final String Function(dynamic value) formatMoney;
  final String Function(DateTime date) formatDate;
  final String Function(DateTime date) formatTime;
  final VoidCallback onMessage;

  const _PurchaseDetailPage({
    required this.purchase,
    required this.buildPhoto,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.roleLabel,
    required this.formatMoney,
    required this.formatDate,
    required this.formatTime,
    required this.onMessage,
  });

  static const Color primaryGreen = _MarketplaceScreenState.primaryGreen;
  static const Color deepText = _MarketplaceScreenState.deepText;
  static const Color mutedText = _MarketplaceScreenState.mutedText;
  static const Color softBg = _MarketplaceScreenState.softBg;
  static const Color softGreen = _MarketplaceScreenState.softGreen;
  static const Color borderColor = _MarketplaceScreenState.borderColor;

  Color _statusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'approved':
      case 'accepted':
      case 'completed':
        return primaryGreen;
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return Colors.redAccent;
      case 'pending':
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'approved':
      case 'accepted':
      case 'completed':
        return 'Onaylandı';
      case 'rejected':
      case 'cancelled':
      case 'canceled':
        return 'Reddedildi';
      case 'pending':
      default:
        return 'Bekleyen';
    }
  }

  DateTime _dateOf(Map<String, dynamic> row) {
    return DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final title = (purchase['title'] ?? 'Satın alma detayı').toString();
    final category = (purchase['category'] ?? 'other').toString();
    final location = (purchase['location'] ?? 'Konum belirtilmemiş').toString();
    final status = (purchase['status'] ?? 'pending').toString();
    final statusColor = _statusColor(status);
    final createdAt = _dateOf(purchase);
    final sellerName = (purchase['sellerName'] ?? 'Satıcı').toString();
    final sellerRole = (purchase['sellerRoleLabel'] ?? roleLabel('')).toString();
    final sellerEmail = (purchase['sellerEmail'] ?? '').toString().trim();
    final sellerPhone = (purchase['sellerPhone'] ?? '').toString().trim();
    final sellerCity = (purchase['sellerCity'] ?? '').toString().trim();
    final sellerAvatar = (purchase['sellerAvatar'] ?? '').toString();
    final photos = List<String>.from(purchase['photosList'] ?? const []);

    return Scaffold(
      backgroundColor: softBg,
      appBar: AppBar(
        backgroundColor: softBg,
        elevation: 0,
        foregroundColor: deepText,
        titleSpacing: 0,
        title: const Text('Alışveriş Detayı', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (photos.isNotEmpty)
            Container(
              height: 210,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 10))]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: PageView.builder(
                  itemCount: photos.length,
                  itemBuilder: (_, i) => buildPhoto(photos[i], height: 210, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
            ),
          _sectionTitle(Icons.inventory_2_outlined, 'Ürün Bilgileri'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.75,
            children: [
              _infoBox('Ürün Adı', title),
              _infoBox('Tutar', formatMoney(purchase['price']), valueColor: primaryGreen),
              _infoBox('Kategori', categoryLabel(category), icon: categoryIcon(category)),
              _infoBox('Konum', location),
              _infoBox('Tarih', formatDate(createdAt)),
              _infoBox('Saat', formatTime(createdAt)),
            ],
          ),
          const SizedBox(height: 12),
          _wideInfoBox('Durum', _statusLabel(status), statusColor, Icons.schedule_rounded),
          const SizedBox(height: 24),
          _sectionTitle(Icons.person_outline_rounded, 'Satıcı Bilgileri'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: primaryGreen,
                  backgroundImage: sellerAvatar.startsWith('http') ? NetworkImage(sellerAvatar) : null,
                  child: !sellerAvatar.startsWith('http')
                      ? Text(sellerName.isNotEmpty ? sellerName[0].toUpperCase() : 'S', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sellerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: deepText, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(sellerRole.isEmpty ? 'Bireysel Kullanıcı' : sellerRole, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _contactBox(Icons.mail_outline_rounded, 'E-posta', sellerEmail.isEmpty ? 'E-posta bilgisi eklenmemiş' : sellerEmail),
          const SizedBox(height: 10),
          _contactBox(Icons.phone_outlined, 'Telefon', sellerPhone.isEmpty ? 'Telefon bilgisi eklenmemiş' : sellerPhone),
          const SizedBox(height: 10),
          _contactBox(Icons.location_on_outlined, 'Şehir', sellerCity.isEmpty ? 'Şehir bilgisi eklenmemiş' : sellerCity),
          const SizedBox(height: 24),
          _sectionTitle(Icons.bolt_rounded, 'Eylemler'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onMessage();
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Satıcıya Mesaj Gönder'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              foregroundColor: deepText,
              side: const BorderSide(color: borderColor),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: primaryGreen, size: 24),
        const SizedBox(width: 9),
        Text(title, style: const TextStyle(color: primaryGreen, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor));
  }

  Widget _infoBox(String label, String value, {Color? valueColor, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 7),
          Row(
            children: [
              if (icon != null) ...[Icon(icon, color: primaryGreen, size: 18), const SizedBox(width: 5)],
              Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: valueColor ?? deepText, fontSize: 16, fontWeight: FontWeight.w900))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wideInfoBox(String label, String value, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactBox(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: deepText, fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _PurchaseRequestDetailPage extends StatelessWidget {
  static const Color primaryGreen = _MarketplaceScreenState.primaryGreen;
  static const Color deepText = _MarketplaceScreenState.deepText;
  static const Color mutedText = _MarketplaceScreenState.mutedText;
  static const Color softBg = _MarketplaceScreenState.softBg;
  static const Color borderColor = _MarketplaceScreenState.borderColor;

  final Map<String, dynamic> request;
  final Widget Function(String url, {required double height, required double width, BoxFit fit, BorderRadius? borderRadius}) buildPhoto;
  final String Function(String key) categoryLabel;
  final IconData Function(String key) categoryIcon;
  final String Function(dynamic value) formatMoney;
  final String Function(DateTime value) formatDate;
  final String Function(DateTime value) formatTime;
  final String Function(String status) statusLabel;
  final Color Function(String status) statusColor;
  final VoidCallback onMessage;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  const _PurchaseRequestDetailPage({
    required this.request,
    required this.buildPhoto,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.formatMoney,
    required this.formatDate,
    required this.formatTime,
    required this.statusLabel,
    required this.statusColor,
    required this.onMessage,
    required this.onApprove,
    required this.onReject,
  });

  DateTime _dateOf(Map<String, dynamic> row) {
    return DateTime.tryParse((row['created_at'] ?? '').toString())?.toLocal() ?? DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final title = (request['title'] ?? 'Satın alma talebi').toString();
    final category = (request['category'] ?? 'other').toString();
    final location = (request['location'] ?? 'Konum belirtilmemiş').toString();
    final buyerName = (request['buyerName'] ?? 'Alıcı').toString();
    final buyerRole = (request['buyerRoleLabel'] ?? 'Bireysel Kullanıcı').toString();
    final buyerEmail = (request['buyerEmail'] ?? '').toString().trim();
    final buyerPhone = (request['buyerPhone'] ?? '').toString().trim();
    final buyerCity = (request['buyerCity'] ?? '').toString().trim();
    final buyerAvatar = (request['buyerAvatar'] ?? '').toString();
    final status = (request['status'] ?? 'pending').toString();
    final statusClr = statusColor(status);
    final createdAt = _dateOf(request);
    final photos = List<String>.from(request['photosList'] ?? const []);
    final message = (request['message'] ?? '').toString().trim();

    return Scaffold(
      backgroundColor: softBg,
      appBar: AppBar(
        backgroundColor: softBg,
        elevation: 0,
        foregroundColor: deepText,
        titleSpacing: 0,
        title: const Text('Satın Alma Talebi', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (photos.isNotEmpty)
            Container(
              height: 210,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 10))]),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: PageView.builder(
                  itemCount: photos.length,
                  itemBuilder: (_, i) => buildPhoto(photos[i], height: 210, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
            ),
          _sectionTitle(Icons.shopping_cart_checkout_rounded, 'Talep Bilgileri'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.62,
            children: [
              _infoBox('İlan', title),
              _infoBox('Tutar', formatMoney(request['price']), valueColor: primaryGreen),
              _infoBox('Kategori', categoryLabel(category), icon: categoryIcon(category)),
              _infoBox('Konum', location),
              _infoBox('Tarih', formatDate(createdAt)),
              _infoBox('Saat', formatTime(createdAt)),
            ],
          ),
          const SizedBox(height: 12),
          _wideInfoBox('Durum', statusLabel(status), statusClr, Icons.schedule_rounded),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            _messageBox(message),
          ],
          const SizedBox(height: 24),
          _sectionTitle(Icons.person_outline_rounded, 'Alıcı Bilgileri'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFF3B82F6),
                  backgroundImage: buyerAvatar.startsWith('http') ? NetworkImage(buyerAvatar) : null,
                  child: !buyerAvatar.startsWith('http')
                      ? Text(buyerName.isNotEmpty ? buyerName[0].toUpperCase() : 'A', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(buyerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: deepText, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(buyerRole.isEmpty ? 'Bireysel Kullanıcı' : buyerRole, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _contactBox(Icons.mail_outline_rounded, 'E-posta', buyerEmail.isEmpty ? 'E-posta bilgisi eklenmemiş' : buyerEmail),
          const SizedBox(height: 10),
          _contactBox(Icons.phone_outlined, 'Telefon', buyerPhone.isEmpty ? 'Telefon bilgisi eklenmemiş' : buyerPhone),
          const SizedBox(height: 10),
          _contactBox(Icons.location_on_outlined, 'Şehir', buyerCity.isEmpty ? 'Şehir bilgisi eklenmemiş' : buyerCity),
          const SizedBox(height: 24),
          _sectionTitle(Icons.bolt_rounded, 'Eylemler'),
          const SizedBox(height: 12),
          if (status == 'pending') ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await onApprove();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Onayla'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await onReject();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.cancel_rounded),
                    label: const Text('Reddet'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onMessage();
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            label: const Text('Alıcıya Mesaj Gönder'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              backgroundColor: status == 'pending' ? deepText : primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: primaryGreen, size: 24),
        const SizedBox(width: 9),
        Text(title, style: const TextStyle(color: primaryGreen, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: borderColor));
  }

  Widget _infoBox(String label, String value, {Color? valueColor, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 7),
          Row(
            children: [
              if (icon != null) ...[Icon(icon, color: primaryGreen, size: 18), const SizedBox(width: 5)],
              Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: valueColor ?? deepText, fontSize: 15.5, fontWeight: FontWeight.w900))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wideInfoBox(String label, String value, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bildirim Mesajı', style: TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: deepText, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _contactBox(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration().copyWith(color: const Color(0xFFF1F5F9)),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: deepText, fontSize: 16, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceFormPage extends StatefulWidget {
  final Map<String, dynamic>? listing;
  final List<_MarketplaceCategory> categories;
  final String defaultCategory;
  final bool isVeterinarian;
  final Widget Function(String url, {required double height, required double width, BoxFit fit, BorderRadius? borderRadius}) buildPhoto;
  final Future<List<XFile>> Function(int remaining) pickPhotos;
  final Future<void> Function({
    required Map<String, dynamic>? listing,
    required String listingType,
    required String category,
    required String title,
    required double? price,
    required String location,
    required String description,
    required List<String> existingPhotos,
    required List<XFile> newPhotos,
  }) save;

  const _MarketplaceFormPage({
    required this.listing,
    required this.categories,
    required this.defaultCategory,
    required this.isVeterinarian,
    required this.buildPhoto,
    required this.pickPhotos,
    required this.save,
  });

  @override
  State<_MarketplaceFormPage> createState() => _MarketplaceFormPageState();
}

class _MarketplaceFormPageState extends State<_MarketplaceFormPage> {
  static const Color primaryGreen = _MarketplaceScreenState.primaryGreen;
  static const Color deepText = _MarketplaceScreenState.deepText;
  static const Color mutedText = _MarketplaceScreenState.mutedText;
  static const Color softBg = _MarketplaceScreenState.softBg;
  static const Color borderColor = _MarketplaceScreenState.borderColor;

  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _type = 'sell';
  String _category = 'land';
  bool _saving = false;
  List<String> _existingPhotos = [];
  final List<XFile> _newPhotos = [];

  bool get _isEdit => widget.listing != null;




  @override
  void initState() {
    super.initState();
    final listing = widget.listing;
    if (listing != null) {
      _type = (listing['listing_type'] ?? 'sell').toString();
      _category = (listing['category'] ?? widget.defaultCategory).toString();
      _titleController.text = (listing['title'] ?? '').toString();
      final rawPrice = listing['price'];
      final price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice?.toString().replaceAll(',', '.') ?? '');
      _priceController.text = price == null
          ? ''
          : price.toStringAsFixed(price.roundToDouble() == price ? 0 : 2);
      _locationController.text = (listing['location'] ?? '').toString();
      _descriptionController.text = (listing['description'] ?? '').toString();
      _existingPhotos = List<String>.from(listing['photosList'] ?? const []);
    } else {
      _category = widget.defaultCategory;
      if (widget.isVeterinarian) {
        _type = 'sell';
        _titleController.text = 'Uzman Veteriner Hizmeti';
        _descriptionController.text = 'Her türlü veteriner / sağlık hizmeti için iletişime geçebilirsiniz.';
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  double? _parsePrice(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9,\.]'), '').replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _addPhotos() async {
    final remaining = 5 - _existingPhotos.length - _newPhotos.length;
    if (remaining <= 0) {
      _snack('En fazla 5 fotoğraf eklenebilir.', isError: true);
      return;
    }
    final picked = await widget.pickPhotos(remaining);
    if (!mounted || picked.isEmpty) return;
    setState(() => _newPhotos.addAll(picked));
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    if (title.isEmpty || location.isEmpty) {
      _snack('Başlık ve konum alanları zorunludur.', isError: true);
      return;
    }
    final price = _parsePrice(_priceController.text.trim());
    if (_priceController.text.trim().isNotEmpty && price == null) {
      _snack('Geçerli bir fiyat gir.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.save(
        listing: widget.listing,
        listingType: _type,
        category: _category,
        title: title,
        price: price,
        location: location,
        description: _descriptionController.text,
        existingPhotos: _existingPhotos,
        newPhotos: _newPhotos,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      _snack('İlan kaydedilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : primaryGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: softBg,
      appBar: AppBar(
        backgroundColor: softBg,
        elevation: 0,
        foregroundColor: deepText,
        title: Text(_isEdit ? 'İlanı Düzenle' : 'Yeni İlan Ver', style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w900, color: primaryGreen)),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
          children: [
            _sectionCard(
              children: [
                _label('İlan Türü'),
                _dropdown(
                  value: _type,
                  items: const [
                    DropdownMenuItem(value: 'sell', child: Text('Satılık / Verilecek')),
                    DropdownMenuItem(value: 'buy', child: Text('Alınacak / Aranıyor')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'sell'),
                ),
                const SizedBox(height: 16),
                _label('Kategori'),
                _dropdown(
                  value: _category,
                  items: widget.categories
                      .map((c) => DropdownMenuItem(value: c.key, child: Text(c.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v ?? widget.defaultCategory),
                ),
                if (widget.isVeterinarian) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Veteriner ilanı için kategori olarak “Veteriner / Sağlık” seçebilirsin.',
                    style: TextStyle(color: mutedText, fontWeight: FontWeight.w600, fontSize: 12.5),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              children: [
                _textField(_titleController, 'Başlık', 'Örn: Uzman Büyükbaş Hekimi - 7/24'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: _textField(_priceController, 'Fiyat (₺)', '1000', keyboardType: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(child: _textField(_locationController, 'Konum', 'İstanbul ve çevresi')),
                  ],
                ),
                const SizedBox(height: 14),
                _textField(_descriptionController, 'Açıklama', 'İlan açıklamasını yaz...', minLines: 4, maxLines: 7),
              ],
            ),
            const SizedBox(height: 14),
            _sectionCard(
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Fotoğraflar', style: TextStyle(color: deepText, fontSize: 16, fontWeight: FontWeight.w900))),
                    Text('${_existingPhotos.length + _newPhotos.length}/5', style: const TextStyle(color: mutedText, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _addPhotos,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: softBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor, width: 1.4)),
                    child: const Column(
                      children: [
                        Icon(Icons.camera_alt_rounded, color: primaryGreen, size: 32),
                        SizedBox(height: 8),
                        Text('Fotoğraf eklemek için tıkla', style: TextStyle(color: deepText, fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text('JPG, PNG — maks 5 fotoğraf', style: TextStyle(color: mutedText, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ...List.generate(_existingPhotos.length, (index) {
                      final url = _existingPhotos[index];
                      return _photoPreview(
                        child: widget.buildPhoto(url, height: 82, width: 82, borderRadius: BorderRadius.circular(14)),
                        onRemove: () => setState(() => _existingPhotos.removeAt(index)),
                      );
                    }),
                    ...List.generate(_newPhotos.length, (index) {
                      final file = _newPhotos[index];
                      return _photoPreview(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(File(file.path), height: 82, width: 82, fit: BoxFit.cover),
                        ),
                        onRemove: () => setState(() => _newPhotos.removeAt(index)),
                      );
                    }),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Kaydediliyor...' : (_isEdit ? 'Değişiklikleri Kaydet' : 'İlanı Yayınla')),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 14, offset: const Offset(0, 7))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: mutedText, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
      );

  Widget _dropdown({required String value, required List<DropdownMenuItem<String>> items, required ValueChanged<String?> onChanged}) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: _decoration('Seç'),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _textField(TextEditingController controller, String label, String hint, {TextInputType keyboardType = TextInputType.text, int minLines = 1, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: maxLines,
          decoration: _decoration(hint),
        ),
      ],
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: softBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: primaryGreen, width: 1.2)),
    );
  }

  Widget _photoPreview({required Widget child, required VoidCallback onRemove}) {
    return Stack(
      children: [
        SizedBox(width: 82, height: 82, child: child),
        Positioned(
          right: 4,
          top: 4,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _MarketplaceDetailPage extends StatefulWidget {
  final Map<String, dynamic> listing;
  final String currentUserId;
  final Widget Function(String url, {required double height, required double width, BoxFit fit, BorderRadius? borderRadius}) buildPhoto;
  final String Function(String key) categoryLabel;
  final IconData Function(String key) categoryIcon;
  final String Function(String key) typeLabel;
  final String Function(String value) roleLabel;
  final String Function(dynamic value) formatMoney;
  final String Function(DateTime value) formatDate;
  final Future<void> Function(String sellerId) onMessage;
  final Future<void> Function(Map<String, dynamic> listing) onPurchase;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  const _MarketplaceDetailPage({
    required this.listing,
    required this.currentUserId,
    required this.buildPhoto,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.typeLabel,
    required this.roleLabel,
    required this.formatMoney,
    required this.formatDate,
    required this.onMessage,
    required this.onPurchase,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_MarketplaceDetailPage> createState() => _MarketplaceDetailPageState();
}

class _MarketplaceDetailPageState extends State<_MarketplaceDetailPage> {
  static const Color primaryGreen = _MarketplaceScreenState.primaryGreen;
  static const Color deepText = _MarketplaceScreenState.deepText;
  static const Color mutedText = _MarketplaceScreenState.mutedText;
  static const Color borderColor = _MarketplaceScreenState.borderColor;
  static const Color softBg = _MarketplaceScreenState.softBg;

  final PageController _pageController = PageController();
  int _slide = 0;

  bool get _isMine => (widget.listing['user_id'] ?? '').toString() == widget.currentUserId;
  List<String> get _photos => List<String>.from(widget.listing['photosList'] ?? const []);

  DateTime get _createdAt => DateTime.tryParse((widget.listing['created_at'] ?? '').toString()) ?? DateTime.now();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = (widget.listing['category'] ?? 'other').toString();
    final type = (widget.listing['listing_type'] ?? 'sell').toString();
    final sellerName = (widget.listing['ownerName'] ?? 'İlan Sahibi').toString();
    final sellerRole = (widget.listing['ownerRoleLabel'] ?? '').toString();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _photoHeader(category),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (category == 'veteriner')
                              _pill('Veteriner / Sağlık', const Color(0xFF6366F1), filled: false, icon: widget.categoryIcon(category))
                            else ...[
                              _pill(widget.typeLabel(type), type == 'sell' ? primaryGreen : const Color(0xFF3B82F6), filled: false),
                              _pill(widget.categoryLabel(category), const Color(0xFF6366F1), filled: false, icon: widget.categoryIcon(category)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(widget.formatMoney(widget.listing['price']), style: const TextStyle(color: primaryGreen, fontSize: 32, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Text(
                          (widget.listing['title'] ?? 'İlan').toString(),
                          style: const TextStyle(color: deepText, fontSize: 25, height: 1.15, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded, color: mutedText, size: 20),
                            const SizedBox(width: 6),
                            Expanded(child: Text((widget.listing['location'] ?? 'Konum belirtilmemiş').toString(), style: const TextStyle(color: mutedText, fontWeight: FontWeight.w700, fontSize: 15))),
                          ],
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(child: _metaBox('İlan Tarihi', widget.formatDate(_createdAt))),
                            const SizedBox(width: 10),
                            Expanded(child: _metaBox('Kategori', widget.categoryLabel(category), icon: widget.categoryIcon(category))),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle('Açıklama', Icons.subject_rounded),
                        const SizedBox(height: 10),
                        Text(
                          (widget.listing['description'] ?? 'Açıklama eklenmemiş.').toString(),
                          style: const TextStyle(color: mutedText, fontSize: 15.5, height: 1.6, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: borderColor),
                        const SizedBox(height: 16),
                        _sectionTitle('İlan Sahibi', Icons.person_outline_rounded),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: softBg, borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor)),
                          child: Row(
                            children: [
                              _sellerAvatar(widget.listing, radius: 30),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(sellerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: deepText, fontSize: 17, fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 4),
                                    Text(sellerRole.isEmpty ? 'Bireysel Kullanıcı' : sellerRole, style: const TextStyle(color: mutedText, fontSize: 13, fontWeight: FontWeight.w700)),
                                  ],
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
            _actionBar(type),
          ],
        ),
      ),
    );
  }

  Widget _photoHeader(String category) {
    return Stack(
      children: [
        SizedBox(
          height: 360,
          width: double.infinity,
          child: _photos.isEmpty
              ? Container(
                  color: const Color(0xFF111111),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_outlined, color: Colors.white.withOpacity(0.35), size: 58),
                      const SizedBox(height: 10),
                      Text('Fotoğraf yok', style: TextStyle(color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w700)),
                    ],
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  itemCount: _photos.length,
                  onPageChanged: (i) => setState(() => _slide = i),
                  itemBuilder: (context, index) => widget.buildPhoto(_photos[index], height: 360, width: double.infinity),
                ),
        ),
        Positioned(
          top: 14,
          left: 14,
          child: _roundOverlayButton(Icons.arrow_back_rounded, () => Navigator.pop(context)),
        ),
        Positioned(
          top: 14,
          right: 14,
          child: _roundOverlayButton(Icons.close_rounded, () => Navigator.pop(context)),
        ),
        if (_photos.length > 1) ...[
          Positioned(
            left: 12,
            top: 165,
            child: _roundOverlayButton(Icons.chevron_left_rounded, () {
              final next = (_slide - 1 + _photos.length) % _photos.length;
              _pageController.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            }),
          ),
          Positioned(
            right: 12,
            top: 165,
            child: _roundOverlayButton(Icons.chevron_right_rounded, () {
              final next = (_slide + 1) % _photos.length;
              _pageController.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
            }),
          ),
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_photos.length, (index) {
                final selected = _slide == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: selected ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(color: selected ? Colors.white : Colors.white.withOpacity(0.45), borderRadius: BorderRadius.circular(99)),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _roundOverlayButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _pill(String label, Color color, {bool filled = true, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: filled ? color : color.withOpacity(0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(0.24))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 15, color: filled ? Colors.white : color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(color: filled ? Colors.white : color, fontSize: 12.5, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _metaBox(String label, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: softBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(color: mutedText, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: primaryGreen), const SizedBox(width: 6)],
              Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: deepText, fontSize: 14.5, fontWeight: FontWeight.w900))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: primaryGreen),
        const SizedBox(width: 7),
        Text(title.toUpperCase(), style: const TextStyle(color: primaryGreen, fontSize: 12, letterSpacing: 0.5, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _sellerAvatar(Map<String, dynamic> item, {double radius = 24}) {
    final avatar = (item['ownerAvatar'] ?? '').toString();
    final name = (item['ownerName'] ?? 'Kullanıcı').toString();
    return CircleAvatar(
      radius: radius,
      backgroundColor: primaryGreen,
      backgroundImage: avatar.startsWith('http') ? NetworkImage(avatar) : null,
      child: !avatar.startsWith('http')
          ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'K', style: TextStyle(color: Colors.white, fontSize: radius * 0.85, fontWeight: FontWeight.w900))
          : null,
    );
  }

  Widget _actionBar(String type) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: borderColor))),
      child: Row(
        children: _isMine
            ? [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Düzenle'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: const Color(0xFF3B82F6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Sil'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: Colors.redAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ]
            : [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const Text('Kapat', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => widget.onMessage((widget.listing['user_id'] ?? '').toString()),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('Mesaj Gönder'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: primaryGreen, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
                if (type == 'sell') ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => widget.onPurchase(widget.listing),
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: const Text('Satın Al'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    ),
                  ),
                ],
              ],
      ),
    );
  }
}
