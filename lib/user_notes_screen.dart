import 'dart:io';

import 'package:flutter/material.dart';
import 'user_app_drawer.dart';
import 'package:image_picker/image_picker.dart';

import 'user_calendar_screen.dart';
import 'user_marketplace_screen.dart';
import 'supabase_service.dart';

class UserNotesScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserNotesScreen({super.key, required this.userData});

  @override
  State<UserNotesScreen> createState() => _UserNotesScreenState();
}

class _UserNotesScreenState extends State<UserNotesScreen> {
  static const Color primaryGreen = Color(0xFF1F6E43);
  static const Color darkGreen = Color(0xFF14452F);
  static const Color lightBackground = Color(0xFFF6FAF5);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  String _searchQuery = '';

  List<Map<String, dynamic>> _notes = [];

  String get _userId => (widget.userData['id'] ?? '').toString();
  String get _userName => (widget.userData['ad'] ?? '').toString();
  String get _userSurname => (widget.userData['soyad'] ?? '').toString();
  String get _avatarUrl => (widget.userData['avatar_url'] ?? '').toString();
  String get _userRole => (widget.userData['rol'] ?? '').toString();

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

  List<Map<String, dynamic>> get _filteredNotes {
    if (_searchQuery.trim().isEmpty) return _notes;

    final q = _searchQuery.toLowerCase().trim();

    return _notes.where((note) {
      final title = (note['title'] ?? '').toString().toLowerCase();
      final content = (note['content'] ?? '').toString().toLowerCase();
      final tags = _parseTags(note['tags']).join(' ').toLowerCase();
      return title.contains(q) || content.contains(q) || tags.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);

    try {
      final data = await SupabaseService().client
          .from('notes')
          .select(
            'id,title,content,images,tags,created_at,note_date,note_time,end_time,color',
          )
          .eq('user_id', _userId)
          .order('created_at', ascending: false);

      _notes = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Notes load error: $e');
      if (mounted) {
        _showSnackBar('Notlar yüklenirken hata oluştu: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isPastDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.isBefore(today);
  }

  String _dateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDate(DateTime dt) {
    const months = [
      '',
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }

  String _formatFooterDate(Map<String, dynamic> note) {
    final noteDate = note['note_date'];
    if (noteDate != null) {
      final parsed = DateTime.tryParse(noteDate.toString());
      if (parsed != null) {
        return _formatDate(parsed);
      }
    }

    final createdAt = note['created_at'];
    final created = createdAt == null
        ? null
        : DateTime.tryParse(createdAt.toString());
    if (created != null) {
      return _formatDate(created);
    }

    return 'Tarih yok';
  }

  String _formatTime(dynamic value) {
    if (value == null) return '';
    final raw = value.toString();
    if (raw.length >= 5) return raw.substring(0, 5);
    return raw;
  }

  List<String> _parseTags(dynamic tags) {
    if (tags == null) return [];

    if (tags is List) {
      return tags
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    final raw = tags.toString().trim();
    if (raw.isEmpty) return [];

    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  List<String> _parseImages(dynamic images) {
    if (images == null) return [];

    if (images is List) {
      return images
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }

    final raw = images.toString().trim();
    if (raw.isEmpty) return [];

    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Color _noteAccent(int? colorIndex) {
    switch (colorIndex ?? 0) {
      case 1:
        return const Color(0xFF16A34A);
      case 2:
        return const Color(0xFF0284C7);
      case 3:
        return const Color(0xFFF59E0B);
      case 4:
        return const Color(0xFF8B5CF6);
      case 5:
        return const Color(0xFFEF4444);
      default:
        return primaryGreen;
    }
  }

  Future<void> _pickImage({
    required List<String> selectedImages,
    required void Function(void Function()) setModalState,
  }) async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (picked != null) {
        setModalState(() {
          selectedImages.add(picked.path);
        });
      }
    } catch (e) {
      _showSnackBar('Fotoğraf seçilirken hata oluştu: $e', isError: true);
    }
  }

  Future<void> _showNoteDialog({Map<String, dynamic>? note}) async {
    final isEdit = note != null;

    final titleController = TextEditingController(
      text: (note?['title'] ?? '').toString(),
    );
    final contentController = TextEditingController(
      text: (note?['content'] ?? '').toString(),
    );
    final tagController = TextEditingController(
      text: _parseTags(note?['tags']).join(', '),
    );
    final timeController = TextEditingController(
      text: note?['note_time'] == null ? '' : _formatTime(note!['note_time']),
    );
    final endTimeController = TextEditingController(
      text: note?['end_time'] == null ? '' : _formatTime(note!['end_time']),
    );

    final originalDate = note?['note_date'] == null
        ? null
        : DateTime.tryParse(note!['note_date'].toString());

    DateTime selectedDate = originalDate ?? DateTime.now();
    bool addToCalendar = note?['note_date'] != null;
    int selectedColor = (note?['color'] ?? 0) as int;
    List<String> selectedImages = List<String>.from(
      _parseImages(note?['images']),
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              final initialDate = selectedDate.isBefore(today)
                  ? today
                  : selectedDate;

              final picked = await showDatePicker(
                context: context,
                initialDate: initialDate,
                firstDate:
                    isEdit && originalDate != null && _isPastDate(originalDate)
                    ? originalDate
                    : today,
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: primaryGreen,
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                setModalState(() => selectedDate = picked);
              }
            }

            Future<void> pickTime({required bool isEnd}) async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: primaryGreen,
                      ),
                    ),
                    child: child!,
                  );
                },
              );

              if (picked != null) {
                final hour = picked.hour.toString().padLeft(2, '0');
                final minute = picked.minute.toString().padLeft(2, '0');
                final formatted = '$hour:$minute';

                setModalState(() {
                  if (isEnd) {
                    endTimeController.text = formatted;
                  } else {
                    timeController.text = formatted;
                  }
                });
              }
            }

            final media = MediaQuery.of(context);
            final dialogMaxHeight = media.size.height * 0.82;
            final dialogMaxWidth = media.size.width > 640
                ? 560.0
                : media.size.width - 24;
            final previewBoxSize = media.size.width < 380 ? 88.0 : 102.0;

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogMaxWidth,
                  maxHeight: dialogMaxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEdit ? 'Notu Düzenle' : 'Not Ekle',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: darkText,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildDialogField(
                                controller: titleController,
                                label: 'Not Başlığı',
                                hint: 'Başlık girin',
                                icon: Icons.title_rounded,
                              ),
                              const SizedBox(height: 12),
                              _buildDialogField(
                                controller: contentController,
                                label: 'Not İçeriği',
                                hint: 'Not içeriğini yazın',
                                icon: Icons.notes_rounded,
                                maxLines: 4,
                              ),
                              const SizedBox(height: 12),
                              _buildDialogField(
                                controller: tagController,
                                label: 'Etiket',
                                hint: 'Örn: Sulama, Tarla, Ekipman',
                                icon: Icons.sell_rounded,
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F7F5),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.event_note_rounded,
                                          color: primaryGreen,
                                        ),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text(
                                            'Takvime Ekle (Opsiyonel)',
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: darkText,
                                            ),
                                          ),
                                        ),
                                        Switch(
                                          value: addToCalendar,
                                          activeColor: primaryGreen,
                                          onChanged: (value) {
                                            setModalState(() {
                                              addToCalendar = value;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    if (addToCalendar) ...[
                                      const SizedBox(height: 10),
                                      InkWell(
                                        onTap: pickDate,
                                        borderRadius: BorderRadius.circular(16),
                                        child: _buildPickerBox(
                                          icon: Icons.calendar_month_rounded,
                                          title: 'Tarih',
                                          value:
                                              '${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      InkWell(
                                        onTap: () => pickTime(isEnd: false),
                                        borderRadius: BorderRadius.circular(16),
                                        child: _buildPickerBox(
                                          icon: Icons.access_time_rounded,
                                          title: 'Başlangıç Saati',
                                          value: timeController.text.isEmpty
                                              ? 'İsteğe bağlı'
                                              : timeController.text,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      InkWell(
                                        onTap: () => pickTime(isEnd: true),
                                        borderRadius: BorderRadius.circular(16),
                                        child: _buildPickerBox(
                                          icon: Icons.timelapse_rounded,
                                          title: 'Bitiş Saati',
                                          value: endTimeController.text.isEmpty
                                              ? 'İsteğe bağlı'
                                              : endTimeController.text,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Renk',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(6, (index) {
                                  final color = _noteAccent(index);
                                  final selected = selectedColor == index;

                                  return GestureDetector(
                                    onTap: () => setModalState(
                                      () => selectedColor = index,
                                    ),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: selected
                                              ? darkText
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: selected
                                          ? const Icon(
                                              Icons.check_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            )
                                          : null,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Fotoğraf Ekle',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: darkText,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _pickImage(
                                      selectedImages: selectedImages,
                                      setModalState: setModalState,
                                    ),
                                    icon: const Icon(
                                      Icons.photo_library_rounded,
                                    ),
                                    label: const Text('Seç'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: primaryGreen,
                                    ),
                                  ),
                                ],
                              ),
                              if (selectedImages.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: List.generate(
                                    selectedImages.length,
                                    (index) {
                                      final imagePath = selectedImages[index];

                                      return SizedBox(
                                        width: previewBoxSize,
                                        height: previewBoxSize,
                                        child: Stack(
                                          children: [
                                            Container(
                                              width: double.infinity,
                                              height: double.infinity,
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5F7F5),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: _buildDialogImagePreview(
                                                  imagePath,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: GestureDetector(
                                                onTap: () {
                                                  setModalState(() {
                                                    selectedImages.removeAt(
                                                      index,
                                                    );
                                                  });
                                                },
                                                child: Container(
                                                  width: 24,
                                                  height: 24,
                                                  decoration: BoxDecoration(
                                                    color: Colors.black
                                                        .withOpacity(0.55),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(
                                                    Icons.close_rounded,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isSaving
                                ? null
                                : () => Navigator.pop(dialogContext),
                            child: const Text('İptal'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isSaving
                                ? null
                                : () async {
                                    final title = titleController.text.trim();
                                    final content = contentController.text
                                        .trim();
                                    final tags = tagController.text
                                        .split(',')
                                        .map((e) => e.trim())
                                        .where((e) => e.isNotEmpty)
                                        .toList();

                                    if (title.isEmpty || content.isEmpty) {
                                      _showSnackBar(
                                        'Not başlığı ve içeriği zorunludur.',
                                        isError: true,
                                      );
                                      return;
                                    }

                                    if (addToCalendar) {
                                      if (!isEdit &&
                                          _isPastDate(selectedDate)) {
                                        _showSnackBar(
                                          'Geçmiş tarihe yeni etkinlik ekleyemezsin.',
                                          isError: true,
                                        );
                                        return;
                                      }

                                      if (isEdit &&
                                          _isPastDate(selectedDate) &&
                                          (originalDate == null ||
                                              !_isSameDate(
                                                selectedDate,
                                                originalDate,
                                              ))) {
                                        _showSnackBar(
                                          'Notu geçmiş tarihe taşıyamazsın.',
                                          isError: true,
                                        );
                                        return;
                                      }
                                    }

                                    setState(() => _isSaving = true);

                                    try {
                                      final payload = {
                                        'title': title,
                                        'content': content,
                                        'tags': tags,
                                        'images': selectedImages,
                                        'color': selectedColor,
                                        'note_date': addToCalendar
                                            ? _dateOnly(selectedDate)
                                            : null,
                                        'note_time':
                                            addToCalendar &&
                                                timeController.text
                                                    .trim()
                                                    .isNotEmpty
                                            ? timeController.text.trim()
                                            : null,
                                        'end_time':
                                            addToCalendar &&
                                                endTimeController.text
                                                    .trim()
                                                    .isNotEmpty
                                            ? endTimeController.text.trim()
                                            : null,
                                      };

                                      if (isEdit) {
                                        await SupabaseService().client
                                            .from('notes')
                                            .update(payload)
                                            .eq('id', note!['id']);
                                      } else {
                                        await SupabaseService().client
                                            .from('notes')
                                            .insert({
                                              'user_id': _userId,
                                              ...payload,
                                            });
                                      }

                                      if (!mounted) return;
                                      Navigator.pop(dialogContext);
                                      await _loadNotes();
                                      _showSnackBar(
                                        isEdit
                                            ? 'Not güncellendi.'
                                            : 'Not başarıyla eklendi.',
                                      );
                                    } catch (e) {
                                      _showSnackBar(
                                        'İşlem sırasında hata oluştu: $e',
                                        isError: true,
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => _isSaving = false);
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                            ),
                            child: Text(isEdit ? 'Kaydet' : 'Ekle'),
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

  Future<void> _deleteNote(Map<String, dynamic> note) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text(
                'Notu Sil',
                style: TextStyle(fontWeight: FontWeight.w800, color: darkText),
              ),
              content: Text(
                '"${(note['title'] ?? 'Not').toString()}" notunu silmek istiyor musun?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Sil'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) return;

    try {
      await SupabaseService().client
          .from('notes')
          .delete()
          .eq('id', note['id']);
      await _loadNotes();

      if (!mounted) return;
      _showSnackBar('Not silindi.');
    } catch (e) {
      _showSnackBar('Not silinirken hata oluştu: $e', isError: true);
    }
  }

  Widget _buildDialogField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: primaryGreen),
        filled: true,
        fillColor: const Color(0xFFF5F7F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildPickerBox({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: darkText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogImagePreview(String path) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFEAF3EC),
      alignment: Alignment.center,
      child: _buildAdaptiveImage(path),
    );
  }

  Widget _buildCardImage(String path) {
    final maxHeight = MediaQuery.of(context).size.width * 0.62;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      color: const Color(0xFFEAF3EC),
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: _buildAdaptiveImage(path),
    );
  }

  Widget _buildAdaptiveImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _imagePlaceholder(),
      );
    }

    final file = File(path);
    return Image.file(
      file,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _imagePlaceholder(),
    );
  }

  Widget _imagePlaceholder() {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: primaryGreen,
        size: 30,
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Builder(
                builder: (context) {
                  return InkWell(
                    onTap: () => Scaffold.of(context).openDrawer(),
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
                      child: const Icon(Icons.menu_rounded, color: darkText),
                    ),
                  );
                },
              ),
              const Spacer(),
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
                          errorBuilder: (_, __, ___) => _buildAvatarFallback(),
                        )
                      : _buildAvatarFallback(),
                ),
              ),
            ],
          ),
          const IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFE9F6EC),
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(Icons.eco_rounded, color: primaryGreen, size: 22),
                  ),
                ),
                SizedBox(width: 9),
                Text(
                  'AgriSynth',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: darkGreen,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: const Color(0xFFE6F2E8),
      child: Center(
        child: Text(
          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'Ç',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: primaryGreen,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5F1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Notlarda ara...',
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(Icons.search_rounded, color: mutedText),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildNoteCard(Map<String, dynamic> note) {
    final tags = _parseTags(note['tags']);
    final images = _parseImages(note['images']);
    final accent = _noteAccent(note['color'] as int?);
    final mainTag = tags.isNotEmpty ? tags.first : 'NOT';

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (images.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: _buildCardImage(images.first),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          mainTag.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _showNoteDialog(note: note),
                      icon: const Icon(Icons.edit_rounded),
                      color: Colors.grey.shade600,
                    ),
                    IconButton(
                      onPressed: () => _deleteNote(note),
                      icon: const Icon(Icons.delete_rounded),
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (note['title'] ?? 'Başlıksız Not').toString(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: darkText,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  (note['content'] ?? '').toString(),
                  maxLines: images.isNotEmpty ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: mutedText,
                    height: 1.5,
                  ),
                ),
                if (tags.length > 1) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tags.skip(1).take(4).map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F5F3),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '#$tag',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: primaryGreen,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 15,
                      color: mutedText,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _formatFooterDate(note),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: mutedText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (note['note_date'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: primaryGreen.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Takvimli',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: primaryGreen,
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
    );
  }

  Widget _buildEmptyNotes() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.note_alt_outlined, color: primaryGreen),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Henüz not yok',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: darkText,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'İlk notunu eklediğinde burada görünecek.',
                  style: TextStyle(
                    fontSize: 13,
                    color: mutedText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      width: double.infinity,
      height: 180,
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(28),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      drawer: UserAppDrawer(
        userData: widget.userData,
        currentPage: UserDrawerPage.notes,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primaryGreen,
          onRefresh: _loadNotes,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Notlarım',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: darkGreen,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _showNoteDialog(),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: primaryGreen,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryGreen.withOpacity(0.20),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Çiftliğinle ilgili notlarını ve planlarını burada takip edebilirsin.',
                        style: TextStyle(
                          fontSize: 14,
                          color: mutedText,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _buildSearchBar(),
                      const SizedBox(height: 22),
                      if (_isLoading)
                        Column(
                          children: List.generate(
                            3,
                            (_) => _buildLoadingCard(),
                          ),
                        )
                      else if (_filteredNotes.isEmpty)
                        _buildEmptyNotes()
                      else
                        Column(
                          children: _filteredNotes.map(_buildNoteCard).toList(),
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
}
