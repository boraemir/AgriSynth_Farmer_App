import 'dart:async';
import 'package:flutter/material.dart';
import 'farmer_app_drawer.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

// ─────────────────────────────────────────────
//  MessagesScreen  –  AgriSynth Mesajlarım
// ─────────────────────────────────────────────
class MessagesScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String? initialChatUserId;

  const MessagesScreen({super.key, required this.userData, this.initialChatUserId});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ── Renkler (farmer_panel.dart ile aynı palet) ──────────────────
  static const Color primaryGreen = Color(0xFF1F6E43);
  static const Color darkGreen = Color(0xFF14452F);
  static const Color softGreen = Color(0xFFA7D7B5);
  static const Color lightBackground = Color(0xFFF6FAF5);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  // ── Kullanıcı bilgileri ─────────────────────────────────────────
  String _valueFromUserData(List<String> keys) {
    for (final key in keys) {
      final value = widget.userData[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  String get _userId {
    final fromWidget = _valueFromUserData(['id', 'user_id', 'uid']);
    if (fromWidget.isNotEmpty) return fromWidget;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  String get _userName => _valueFromUserData(['ad', 'first_name', 'name']);
  String get _avatarUrl => _valueFromUserData(['avatar_url', 'profile_image_url']);
  String get _fullName {
    final direct = _valueFromUserData(['full_name', 'display_name']);
    if (direct.isNotEmpty) return direct;

    final first = _valueFromUserData(['ad', 'first_name', 'name']);
    final last = _valueFromUserData(['soyad', 'last_name', 'surname']);
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Kullanıcı' : full;
  }

  // ── State ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> _chats = [];
  Map<String, dynamic>? _selectedChat;
  List<Map<String, dynamic>> _messages = [];
  bool _initialChatHandled = false;

  bool _loadingChats = true;
  bool _loadingMessages = false;
  bool _sendingMessage = false;
  final Set<String> _updatingMessageIds = <String>{};

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _msgScrollCtrl = ScrollController();
  final FocusNode _msgFocus = FocusNode();

  String _searchQuery = '';

  // Realtime abonelik
  RealtimeChannel? _messagesChannel;

  // Animasyon
  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _loadChats();
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _slideCtrl.dispose();
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    _msgScrollCtrl.dispose();
    _msgFocus.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════
  //  VERİ KATMANI
  // ════════════════════════════════════════════

  Future<void> _loadChats() async {
    final currentUserId = _userId;

    if (mounted) setState(() => _loadingChats = true);

    if (currentUserId.isEmpty) {
      debugPrint('Chat load error: Kullanıcı id bulunamadı.');
      if (mounted) {
        setState(() {
          _chats = [];
          _loadingChats = false;
        });
      }
      return;
    }

    try {
      // Senin Supabase şemanda chats tablosunda participant_ids yok.
      // Doğru kolonlar: user1_id ve user2_id.
      final data = await SupabaseService()
          .client
          .from('chats')
          .select('id, created_at, user1_id, user2_id')
          .or('user1_id.eq.$currentUserId,user2_id.eq.$currentUserId')
          .order('created_at', ascending: false);

      final enriched = <Map<String, dynamic>>[];

      for (final rawChat in List<Map<String, dynamic>>.from(data)) {
        final chat = Map<String, dynamic>.from(rawChat);
        final chatId = (chat['id'] ?? '').toString();
        final user1Id = (chat['user1_id'] ?? '').toString();
        final user2Id = (chat['user2_id'] ?? '').toString();

        final otherId = user1Id == currentUserId ? user2Id : user1Id;
        final otherUser = otherId.isEmpty
            ? <String, dynamic>{}
            : await _fetchUserById(otherId);

        final lastMessages = await _fetchMessagesByChatId(
          chatId,
          ascending: false,
          limit: 1,
        );
        final lastMsg = lastMessages.isNotEmpty ? lastMessages.first : null;

        enriched.add({
          ...chat,
          'other_user_id': otherId,
          'other_user': otherUser,
          'last_message': lastMsg,
          'unread_count': 0,
        });
      }

      enriched.sort((a, b) {
        final aTs = (a['last_message'] as Map<String, dynamic>?)?['created_at'] ??
            a['created_at'];
        final bTs = (b['last_message'] as Map<String, dynamic>?)?['created_at'] ??
            b['created_at'];

        final aDt = DateTime.tryParse(aTs?.toString() ?? '') ?? DateTime(1970);
        final bDt = DateTime.tryParse(bTs?.toString() ?? '') ?? DateTime(1970);
        return bDt.compareTo(aDt);
      });

      if (mounted) {
        setState(() => _chats = enriched);
        unawaited(_openInitialChatIfNeeded());
      }
    } catch (e) {
      debugPrint('Chat load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mesajlar yüklenemedi: $e'),
            backgroundColor: Colors.red.shade500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingChats = false);
    }
  }

  Future<Map<String, dynamic>> _fetchUserById(String userId) async {
    if (userId.isEmpty) return <String, dynamic>{};

    // Farklı users tablo şemalarına uyumlu çalışması için birkaç güvenli select deneniyor.
    // Var olmayan kolon seçilirse Supabase hata döndürür; bir sonraki seçime geçilir.
    final selectAttempts = <String>[
      // Senin mevcut users şeman: ad, soyad, email, telefon, sehir, rol
      'id, username, email, ad, soyad, telefon, sehir, rol, created_at, avatar_url',
      // Projedeki yaygın users şeması
      'id, first_name, last_name, email, phone, avatar_url, city, specialty, role, created_at, last_seen, is_online',
      // Specialty / online kolonları yoksa iletişim alanlarını yine çekebilmek için
      'id, first_name, last_name, email, phone, avatar_url, city, role, created_at',
      // Türkçe kolon isimleri kullanan şema
      'id, ad, soyad, email, phone, avatar_url, city, uzmanlik, rol, created_at, last_seen, is_online',
      // Türkçe şemada uzmanlık / durum kolonları yoksa
      'id, ad, soyad, email, phone, avatar_url, city, rol, created_at',
      // Alternatif iletişim kolonları
      'id, first_name, last_name, email, phone_number, avatar_url, city, role',
      'id, first_name, last_name, mail, telefon, avatar_url, sehir, role',
      // Daha sade İngilizce şema
      'id, first_name, last_name, avatar_url, role',
      // Alternatif profil fotoğrafı / isim kolonları olan şema
      'id, full_name, display_name, name, profile_image_url, role',
      // Daha sade Türkçe şema
      'id, ad, soyad, avatar_url, rol',
    ];

    for (final columns in selectAttempts) {
      try {
        final res = await SupabaseService()
            .client
            .from('users')
            .select(columns)
            .eq('id', userId)
            .maybeSingle();
        if (res != null) return Map<String, dynamic>.from(res);
      } catch (_) {
        // Bir sonraki kolon setini dene.
      }
    }

    debugPrint('User fetch error: users tablosunda uygun kolon seti bulunamadı.');
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> _fetchMessagesByChatId(
    String chatId, {
    required bool ascending,
    int? limit,
  }) async {
    if (chatId.isEmpty) return <Map<String, dynamic>>[];

    try {
      if (limit == null) {
        final data = await SupabaseService()
            .client
            .from('messages')
            .select('id, chat_id, content, sender_id, created_at, is_edited, is_deleted, deleted_at')
            .eq('chat_id', chatId)
            .order('created_at', ascending: ascending);
        return List<Map<String, dynamic>>.from(data);
      }

      final data = await SupabaseService()
          .client
          .from('messages')
          .select('id, chat_id, content, sender_id, created_at, is_edited, is_deleted, deleted_at')
          .eq('chat_id', chatId)
          .order('created_at', ascending: ascending)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    } catch (_) {
      // is_edited kolonu yoksa bu fallback eski messages şemasını da destekler.
      if (limit == null) {
        final data = await SupabaseService()
            .client
            .from('messages')
            .select('id, chat_id, content, sender_id, created_at')
            .eq('chat_id', chatId)
            .order('created_at', ascending: ascending);
        return List<Map<String, dynamic>>.from(data);
      }

      final data = await SupabaseService()
          .client
          .from('messages')
          .select('id, chat_id, content, sender_id, created_at')
          .eq('chat_id', chatId)
          .order('created_at', ascending: ascending)
          .limit(limit);
      return List<Map<String, dynamic>>.from(data);
    }
  }


  Future<void> _openInitialChatIfNeeded() async {
    if (_initialChatHandled) return;
    final targetUserId = (widget.initialChatUserId ?? '').trim();
    if (targetUserId.isEmpty || targetUserId == _userId) return;
    _initialChatHandled = true;

    Map<String, dynamic>? chat;
    for (final item in _chats) {
      if ((item['other_user_id'] ?? '').toString() == targetUserId) {
        chat = item;
        break;
      }
    }

    chat ??= await _createOrFetchChatWith(targetUserId);
    if (!mounted || chat == null) return;
    await _openChat(chat);
  }

  Future<Map<String, dynamic>?> _createOrFetchChatWith(String otherUserId) async {
    final currentUserId = _userId;
    if (currentUserId.isEmpty || otherUserId.isEmpty || currentUserId == otherUserId) return null;

    try {
      final id1 = currentUserId.compareTo(otherUserId) <= 0 ? currentUserId : otherUserId;
      final id2 = currentUserId.compareTo(otherUserId) <= 0 ? otherUserId : currentUserId;

      var chat = await SupabaseService()
          .client
          .from('chats')
          .select('id, created_at, user1_id, user2_id')
          .eq('user1_id', id1)
          .eq('user2_id', id2)
          .maybeSingle();

      chat ??= await SupabaseService()
          .client
          .from('chats')
          .insert({'user1_id': id1, 'user2_id': id2})
          .select('id, created_at, user1_id, user2_id')
          .single();

      final chatMap = Map<String, dynamic>.from(chat);
      final user1Id = (chatMap['user1_id'] ?? '').toString();
      final user2Id = (chatMap['user2_id'] ?? '').toString();
      final resolvedOtherId = user1Id == currentUserId ? user2Id : user1Id;
      final otherUser = await _fetchUserById(resolvedOtherId);
      final lastMessages = await _fetchMessagesByChatId((chatMap['id'] ?? '').toString(), ascending: false, limit: 1);
      final enriched = <String, dynamic>{
        ...chatMap,
        'other_user_id': resolvedOtherId,
        'other_user': otherUser,
        'last_message': lastMessages.isNotEmpty ? lastMessages.first : null,
        'unread_count': 0,
      };

      if (mounted) {
        setState(() {
          final index = _chats.indexWhere((c) => c['id'] == enriched['id']);
          if (index >= 0) {
            _chats[index] = enriched;
          } else {
            _chats.insert(0, enriched);
          }
        });
      }
      return enriched;
    } catch (e) {
      debugPrint('Initial chat open error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sohbet açılamadı: $e'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ));
      }
      return null;
    }
  }

  Future<void> _openChat(Map<String, dynamic> chat) async {
    setState(() {
      _selectedChat = chat;
      _loadingMessages = true;
    });
    _slideCtrl.forward(from: 0);

    try {
      final chatId = (chat['id'] ?? '').toString();
      final data = await _fetchMessagesByChatId(chatId, ascending: true);

      if (mounted) setState(() => _messages = data);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Message load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mesajlar açılırken hata oluştu: $e'),
            backgroundColor: Colors.red.shade500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }

    _subscribeToMessages((chat['id'] ?? '').toString());
  }

  void _subscribeToMessages(String chatId) {
    _messagesChannel?.unsubscribe();
    if (chatId.isEmpty) return;

    _messagesChannel = SupabaseService()
        .client
        .channel('messages:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            final newMsg = Map<String, dynamic>.from(payload.newRecord);
            if (mounted) {
              final exists = _messages.any((m) => m['id'] == newMsg['id']);
              if (!exists) {
                setState(() => _messages.add(newMsg));
                _scrollToBottom();
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            final updated = Map<String, dynamic>.from(payload.newRecord);
            if (!mounted) return;
            setState(() {
              final index = _messages.indexWhere((m) => m['id'] == updated['id']);
              if (index >= 0) {
                _messages[index] = {
                  ..._messages[index],
                  ...updated,
                };
              }
            });
            unawaited(_loadChats());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            final oldRecord = Map<String, dynamic>.from(payload.oldRecord);
            if (!mounted) return;
            setState(() {
              _messages.removeWhere((m) => m['id'] == oldRecord['id']);
            });
            unawaited(_loadChats());
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage() async {
    final content = _msgCtrl.text.trim();
    final currentUserId = _userId;

    if (content.isEmpty ||
        _selectedChat == null ||
        _sendingMessage ||
        currentUserId.isEmpty) {
      return;
    }

    setState(() => _sendingMessage = true);
    _msgCtrl.clear();

    try {
      await SupabaseService().client.from('messages').insert({
        'chat_id': _selectedChat!['id'],
        'sender_id': currentUserId,
        'content': content,
        'is_edited': false,
      });
    } catch (_) {
      // is_edited kolonu yoksa sade insert dene.
      try {
        await SupabaseService().client.from('messages').insert({
          'chat_id': _selectedChat!['id'],
          'sender_id': currentUserId,
          'content': content,
        });
      } catch (e) {
        debugPrint('Send error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Mesaj gönderilemedi: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ));
        }
      }
    } finally {
      if (mounted) setState(() => _sendingMessage = false);
    }
  }

  Future<void> _editMessage(Map<String, dynamic> msg) async {
    if (!_isMyMsg(msg) || _messageIsDeleted(msg)) return;

    final messageId = (msg['id'] ?? '').toString();
    final oldContent = (msg['content'] ?? '').toString();
    if (messageId.isEmpty) return;

    final controller = TextEditingController(text: oldContent);
    final newContent = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: cardWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text(
            'Mesajı düzenle',
            style: TextStyle(
              color: darkGreen,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            minLines: 1,
            decoration: InputDecoration(
              hintText: 'Mesajını güncelle...',
              filled: true,
              fillColor: lightBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: softGreen.withOpacity(0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: primaryGreen, width: 1.4),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (newContent == null || newContent.isEmpty || newContent == oldContent) return;

    setState(() => _updatingMessageIds.add(messageId));
    try {
      try {
        await SupabaseService().client.from('messages').update({
          'content': newContent,
          'is_edited': true,
        }).eq('id', messageId).eq('sender_id', _userId);
      } catch (_) {
        await SupabaseService().client.from('messages').update({
          'content': newContent,
        }).eq('id', messageId).eq('sender_id', _userId);
      }

      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m['id'].toString() == messageId);
        if (index >= 0) {
          _messages[index] = {
            ..._messages[index],
            'content': newContent,
            'is_edited': true,
          };
        }
      });
      unawaited(_loadChats());
    } catch (e) {
      debugPrint('edit message error: $e');
      if (mounted) _showSnack('Mesaj düzenlenemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingMessageIds.remove(messageId));
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> msg) async {
    if (!_isMyMsg(msg) || _messageIsDeleted(msg)) return;

    final messageId = (msg['id'] ?? '').toString();
    if (messageId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: cardWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Mesaj silinsin mi?',
          style: TextStyle(
            color: darkGreen,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Mesaj tamamen kaldırılmayacak. Sohbette “Bu mesaj silinmiştir” olarak görünecek.',
          style: TextStyle(height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _updatingMessageIds.add(messageId));
    try {
      final deletedContent = 'Bu mesaj silinmiştir';
      try {
        await SupabaseService().client.from('messages').update({
          'content': deletedContent,
          'is_deleted': true,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'is_edited': false,
        }).eq('id', messageId).eq('sender_id', _userId);
      } catch (_) {
        // is_deleted/deleted_at kolonu yoksa da ekranda aynı deneyimi ver.
        await SupabaseService().client.from('messages').update({
          'content': deletedContent,
        }).eq('id', messageId).eq('sender_id', _userId);
      }

      if (!mounted) return;
      setState(() {
        final index = _messages.indexWhere((m) => m['id'].toString() == messageId);
        if (index >= 0) {
          _messages[index] = {
            ..._messages[index],
            'content': deletedContent,
            'is_deleted': true,
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'is_edited': false,
          };
        }
      });
      unawaited(_loadChats());
    } catch (e) {
      debugPrint('delete message error: $e');
      if (mounted) _showSnack('Mesaj silinemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _updatingMessageIds.remove(messageId));
    }
  }

  Future<void> _showMessageActions(Map<String, dynamic> msg) async {
    final isMe = _isMyMsg(msg);
    final isDeleted = _messageIsDeleted(msg);

    if (!isMe && isDeleted) return;

    HapticFeedback.mediumImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDeleted)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: primaryGreen),
                    title: const Text('Mesajı kopyala'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      Clipboard.setData(ClipboardData(text: msg['content']?.toString() ?? ''));
                      _showSnack('Mesaj kopyalandı');
                    },
                  ),
                if (isMe && !isDeleted) ...[
                  ListTile(
                    leading: const Icon(Icons.edit_rounded, color: primaryGreen),
                    title: const Text('Mesajı düzenle'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editMessage(msg);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600),
                    title: Text('Mesajı sil', style: TextStyle(color: Colors.red.shade700)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _deleteMessage(msg);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade500 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_msgScrollCtrl.hasClients) {
        _msgScrollCtrl.animateTo(
          _msgScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _closeChat() {
    _messagesChannel?.unsubscribe();
    _messagesChannel = null;
    setState(() {
      _selectedChat = null;
      _messages = [];
    });
    unawaited(_loadChats());
  }

  // ════════════════════════════════════════════
  //  YARDIMCI METODlar
  // ════════════════════════════════════════════

  String _userField(Map<String, dynamic> user, List<String> keys) {
    for (final key in keys) {
      final value = user[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  String _otherName(Map<String, dynamic> chat) {
    final u = Map<String, dynamic>.from(chat['other_user'] ?? {});
    final direct = _userField(u, ['full_name', 'display_name']);
    if (direct.isNotEmpty) return direct;

    final first = _userField(u, ['ad', 'first_name', 'name']);
    final last = _userField(u, ['soyad', 'last_name', 'surname']);
    final name = '$first $last'.trim();
    return name.isEmpty ? 'Kullanıcı' : name;
  }

  String _otherAvatar(Map<String, dynamic> chat) {
    final u = Map<String, dynamic>.from(chat['other_user'] ?? {});
    return _userField(u, ['avatar_url', 'profile_image_url']);
  }

  String _formatRoleLabel(String rawRole) {
    final raw = rawRole.trim();
    if (raw.isEmpty) return 'Normal Kullanıcı';

    final normalized = raw
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u')
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    if (normalized.contains('veter')) return 'Veteriner';
    if (normalized.contains('doktor') || normalized.contains('doctor')) {
      return 'Veteriner';
    }
    if (normalized.contains('ciftci') || normalized.contains('farmer')) {
      return 'Çiftçi';
    }
    if (normalized.contains('normal') ||
        normalized == 'user' ||
        normalized == 'kullanici' ||
        normalized == 'kullanıcı') {
      return 'Normal Kullanıcı';
    }

    return raw;
  }

  String _roleFromUser(Map<String, dynamic> user) {
    return _formatRoleLabel(_userField(user, ['rol', 'role', 'user_role']));
  }

  String _otherRole(Map<String, dynamic> chat) {
    final u = Map<String, dynamic>.from(chat['other_user'] ?? {});
    return _roleFromUser(u);
  }

  String _lastMsgPreview(Map<String, dynamic> chat) {
    final last = chat['last_message'] as Map<String, dynamic>?;
    if (last == null) return 'Henüz mesaj yok';
    if (_messageIsDeleted(last)) return 'Bu mesaj silinmiştir';
    final content = last['content']?.toString() ?? '';
    return content.length > 42 ? '${content.substring(0, 42)}…' : content;
  }

  String _relativeTime(dynamic ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts.toString())?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}d';
    if (diff.inHours < 24) return '${diff.inHours}s';
    if (diff.inDays == 1) return 'Dün';
    if (diff.inDays < 7) return '${diff.inDays} gün';
    return '${dt.day}/${dt.month}';
  }

  String _msgTime(dynamic ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts.toString())?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _isMyMsg(Map<String, dynamic> msg) =>
      msg['sender_id']?.toString() == _userId;

  bool _messageIsDeleted(Map<String, dynamic> msg) {
    final content = (msg['content'] ?? '').toString().trim().toLowerCase();
    return msg['is_deleted'] == true || content == 'bu mesaj silinmiştir';
  }

  List<Map<String, dynamic>> get _filteredChats {
    if (_searchQuery.isEmpty) return _chats;
    final q = _searchQuery.toLowerCase();
    return _chats.where((c) => _otherName(c).toLowerCase().contains(q)).toList();
  }

  Future<void> _showOtherUserProfile() async {
    final chat = _selectedChat;
    if (chat == null) return;

    final cachedUser = Map<String, dynamic>.from(chat['other_user'] ?? {});
    final otherId = (chat['other_user_id'] ?? cachedUser['id'] ?? '').toString();

    Map<String, dynamic> user = cachedUser;
    if (otherId.isNotEmpty) {
      final freshUser = await _fetchUserById(otherId);
      if (freshUser.isNotEmpty) {
        user = {
          ...cachedUser,
          ...freshUser,
        };
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _buildUserProfilePage(user),
      ),
    );
  }

  Widget _buildUserProfilePage(Map<String, dynamic> user) {
    final name = _displayNameFromUser(user);
    final avatar = _userField(user, ['avatar_url', 'profile_image_url']);
    final role = _roleFromUser(user);

    // users tablonun gerçek kolonları:
    // email, telefon, sehir, rol, avatar_url, ad, soyad
    final email = _userField(user, ['email', 'mail']);
    final phone = _userField(user, ['telefon', 'phone', 'phone_number', 'tel', 'mobile']);
    final city = _userField(user, ['sehir', 'şehir', 'city', 'province', 'location']);

    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        backgroundColor: lightBackground,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
            color: darkGreen,
            style: IconButton.styleFrom(
              backgroundColor: cardWhite,
              shadowColor: Colors.black.withOpacity(0.06),
              elevation: 2,
            ),
          ),
        ),
        title: const Text(
          'İletişim Bilgileri',
          style: TextStyle(
            color: darkGreen,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardWhite,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: softGreen.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.045),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _miniAvatar(avatar, name, radius: 38),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: darkGreen,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: primaryGreen.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: primaryGreen.withOpacity(0.14),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified_user_rounded,
                                size: 13,
                                color: primaryGreen,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                role,
                                style: const TextStyle(
                                  color: primaryGreen,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
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
            const SizedBox(height: 16),
            _profileSectionCard(
              title: 'İletişim',
              children: [
                _profileDetailRow(
                  icon: Icons.mail_outline_rounded,
                  title: 'E-posta',
                  value: email.isEmpty ? 'E-posta bilgisi eklenmemiş' : email,
                ),
                _profileDetailRow(
                  icon: Icons.phone_outlined,
                  title: 'Telefon',
                  value: phone.isEmpty ? 'Telefon numarası eklenmemiş' : phone,
                ),
                _profileDetailRow(
                  icon: Icons.location_on_outlined,
                  title: 'Yaşadığı şehir',
                  value: city.isEmpty ? 'Şehir bilgisi eklenmemiş' : city,
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: primaryGreen.withOpacity(0.12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 19,
                    color: primaryGreen,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bu sayfadaki bilgiler users tablosundaki email, telefon ve sehir kolonlarından çekilir.',
                      style: TextStyle(
                        color: darkGreen,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primaryGreen.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: primaryGreen),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: primaryGreen,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: softGreen.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                color: darkGreen,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _profileDetailRow({
    required IconData icon,
    required String title,
    required String value,
    bool isLast = false,
  }) {
    return Container(
      padding: EdgeInsets.only(top: 12, bottom: isLast ? 10 : 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: softGreen.withOpacity(0.22)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryGreen, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: mutedText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _roleDescription(String role) {
    final normalized = role
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ç', 'c')
        .replaceAll('ğ', 'g')
        .replaceAll('ö', 'o')
        .replaceAll('ş', 's')
        .replaceAll('ü', 'u');

    if (normalized.contains('veteriner')) {
      return 'Hayvan sağlığı ve çiftlik danışmanlığı için iletişime geçilebilecek kullanıcı.';
    }
    if (normalized.contains('ciftci')) {
      return 'Tarım, üretim ve çiftlik süreçlerinde platformu kullanan çiftçi profili.';
    }
    return 'AgriSynth platformunda mesajlaşabilen normal kullanıcı profili.';
  }

  String _formatShortDate(String rawDate) {
    final dt = DateTime.tryParse(rawDate)?.toLocal();
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _displayNameFromUser(Map<String, dynamic> user) {
    final direct = _userField(user, ['full_name', 'display_name']);
    if (direct.isNotEmpty) return direct;

    final first = _userField(user, ['ad', 'first_name', 'name']);
    final last = _userField(user, ['soyad', 'last_name', 'surname']);
    final full = '$first $last'.trim();
    return full.isEmpty ? 'Kullanıcı' : full;
  }

  String _onlineStatusText(Map<String, dynamic> user) {
    final value = user['is_online'];
    if (value == true || value?.toString().toLowerCase() == 'true') {
      return 'Çevrimiçi';
    }
    return '';
  }

  String _formatLastSeen(String raw) {
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;

    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
    if (diff.inHours < 24) return '${diff.inHours} saat önce';
    if (diff.inDays == 1) return 'Dün';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';

    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year.toString();
    return '$day/$month/$year';
  }

  // ════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: lightBackground,
      drawer: FarmerAppDrawer(
        userData: widget.userData,
        currentPage: FarmerDrawerPage.messages,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _selectedChat == null ? _buildChatList() : _buildChatView(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              // Geri / menü butonu
              InkWell(
                onTap: _selectedChat != null
                    ? _closeChat
                    : () => _scaffoldKey.currentState?.openDrawer(),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cardWhite,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _selectedChat != null
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.menu_rounded,
                    color: darkText,
                    size: 18,
                  ),
                ),
              ),
              const Spacer(),
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                    color: primaryGreen.withOpacity(0.18),
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(19),
                  child: _avatarUrl.startsWith('http')
                      ? Image.network(
                          _avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _avatarFallback(_userName),
                        )
                      : _avatarFallback(_userName),
                ),
              ),
            ],
          ),
          // Başlık / seçili sohbette profil alanı
          _selectedChat == null
              ? const IgnorePointer(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.eco_rounded, color: primaryGreen, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'AgriSynth',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: darkGreen,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _showOtherUserProfile,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _miniAvatar(_otherAvatar(_selectedChat!),
                          _otherName(_selectedChat!)),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          _otherName(_selectedChat!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: darkGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: mutedText,
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  // ── Sohbet Listesi ───────────────────────────────────────────────
  Widget _buildChatList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          // Başlık
          const Text(
            'Mesajlarım',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: darkGreen,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          // Arama
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(
                fontSize: 14,
                color: darkText,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Kişi ara...',
                hintStyle: TextStyle(color: mutedText, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: mutedText, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: mutedText, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Liste
          Expanded(child: _buildChatListBody()),
        ],
      ),
    );
  }

  Widget _buildChatListBody() {
    if (_loadingChats) {
      return Center(
        child: CircularProgressIndicator(
          color: primaryGreen,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_filteredChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: primaryGreen,
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Henüz mesajınız yok',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: darkText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'İlan pazarından veya iş portalından\nbirine mesaj göndererek başlayabilirsin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: mutedText,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: primaryGreen,
      onRefresh: _loadChats,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        itemCount: _filteredChats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildChatTile(_filteredChats[i]),
      ),
    );
  }

  Widget _buildChatTile(Map<String, dynamic> chat) {
    final isSelected = _selectedChat?['id'] == chat['id'];
    final lastTs = (chat['last_message'] as Map<String, dynamic>?)?['created_at'];

    return GestureDetector(
      onTap: () => _openChat(chat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? primaryGreen.withOpacity(0.06) : cardWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? primaryGreen.withOpacity(0.3)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            _miniAvatar(_otherAvatar(chat), _otherName(chat), radius: 26),
            const SizedBox(width: 14),
            // Bilgi
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _otherName(chat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: darkText,
                          ),
                        ),
                      ),
                      Text(
                        _relativeTime(lastTs),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: mutedText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Rol badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: primaryGreen.withOpacity(0.09),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _otherRole(chat),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _lastMsgPreview(chat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: mutedText,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat Görünümü ────────────────────────────────────────────────
  Widget _buildChatView() {
    return SlideTransition(
      position: _slideAnim,
      child: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_loadingMessages) {
      return Center(
        child: CircularProgressIndicator(color: primaryGreen, strokeWidth: 2.5),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: softGreen.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waving_hand_rounded,
                  color: primaryGreen, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              'Merhaba de! İlk mesajı sen gönder 👋',
              style: TextStyle(
                fontSize: 14,
                color: mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _msgScrollCtrl,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final msg = _messages[i];
        final isMe = _isMyMsg(msg);

        // Tarih ayırıcısı
        bool showDate = false;
        if (i == 0) {
          showDate = true;
        } else {
          final prevDt = DateTime.tryParse(
              _messages[i - 1]['created_at']?.toString() ?? '');
          final curDt =
              DateTime.tryParse(msg['created_at']?.toString() ?? '');
          if (prevDt != null && curDt != null) {
            showDate = prevDt.day != curDt.day ||
                prevDt.month != curDt.month ||
                prevDt.year != curDt.year;
          }
        }

        return Column(
          children: [
            if (showDate) _buildDateDivider(msg['created_at']),
            _buildMessageBubble(msg, isMe),
          ],
        );
      },
    );
  }

  Widget _buildDateDivider(dynamic ts) {
    final dt = DateTime.tryParse(ts?.toString() ?? '')?.toLocal();
    if (dt == null) return const SizedBox.shrink();

    final now = DateTime.now();
    String label;
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      label = 'Bugün';
    } else if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day - 1) {
      label = 'Dün';
    } else {
      label = '${dt.day}/${dt.month}/${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: softGreen.withOpacity(0.4))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: mutedText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(color: softGreen.withOpacity(0.4))),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final isDeleted = _messageIsDeleted(msg);
    final messageId = (msg['id'] ?? '').toString();
    final isUpdating = _updatingMessageIds.contains(messageId);
    final bubbleText = isDeleted ? 'Bu mesaj silinmiştir' : (msg['content']?.toString() ?? '');

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageActions(msg),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isUpdating ? 0.55 : 1,
          child: Container(
            margin: EdgeInsets.only(
              top: 3,
              bottom: 3,
              left: isMe ? 60 : 0,
              right: isMe ? 0 : 60,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: isMe && !isDeleted
                  ? const LinearGradient(
                      colors: [Color(0xFF1F6E43), Color(0xFF2B8A57)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isDeleted
                  ? const Color(0xFFE5E7EB)
                  : (isMe ? null : cardWhite),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isMe ? 18 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 18),
              ),
              border: isDeleted ? Border.all(color: Colors.grey.shade300) : null,
              boxShadow: [
                BoxShadow(
                  color: isMe && !isDeleted
                      ? primaryGreen.withOpacity(0.18)
                      : Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isDeleted) ...[
                      Icon(
                        Icons.block_rounded,
                        size: 15,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        bubbleText,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDeleted
                              ? Colors.grey.shade700
                              : (isMe ? Colors.white : darkText),
                          height: 1.45,
                          fontWeight: isDeleted ? FontWeight.w600 : FontWeight.w500,
                          fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (msg['is_edited'] == true && !isDeleted)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'düzenlendi',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isMe ? Colors.white.withOpacity(0.65) : mutedText,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Text(
                      _msgTime(msg['created_at']),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDeleted
                            ? Colors.grey.shade600
                            : (isMe ? Colors.white.withOpacity(0.7) : mutedText),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isUpdating) ...[
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: isDeleted || !isMe ? primaryGreen : Colors.white,
                        ),
                      ),
                    ] else if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.done_all_rounded,
                        size: 13,
                        color: isDeleted ? Colors.grey.shade600 : Colors.white.withOpacity(0.7),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Mesaj Giriş Alanı ────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: lightBackground,
        border: Border(
          top: BorderSide(color: softGreen.withOpacity(0.3), width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cardWhite,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: TextField(
                controller: _msgCtrl,
                focusNode: _msgFocus,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  fontSize: 14,
                  color: darkText,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: 'Mesaj yaz...',
                  hintStyle: TextStyle(color: mutedText, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Gönder butonu
          GestureDetector(
            onTap: _sendingMessage ? null : _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1F6E43), Color(0xFF2B8A57)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryGreen.withOpacity(0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: _sendingMessage
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Yardımcı Widget'lar ─────────────────────────────────────────
  Widget _miniAvatar(String url, String name, {double radius = 22}) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: softGreen.withOpacity(0.5), width: 1.5),
      ),
      child: ClipOval(
        child: url.startsWith('http')
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarFallback(name),
              )
            : _avatarFallback(name),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: const Color(0xFFE6F2E8),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: primaryGreen,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}