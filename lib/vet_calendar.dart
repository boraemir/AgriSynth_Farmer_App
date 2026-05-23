import 'package:flutter/material.dart';
import 'supabase_service.dart';
import 'vet_app_drawer.dart';
import 'vet_listings_requests.dart';
import 'vet_appointments.dart';
import 'vet_messages.dart';
import 'vet_profile_edit_screen.dart';
import 'vet_notes.dart';


class VetCalendarScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const VetCalendarScreen({super.key, required this.userData});

  @override
  State<VetCalendarScreen> createState() => _VetCalendarScreenState();
}

class _VetCalendarScreenState extends State<VetCalendarScreen> {
  static const Color primaryBlue = Color(0xFF1D4ED8);
  static const Color darkBlue = Color(0xFF13244A);
  static const Color lightBackground = Color(0xFFFAFBFF);
  static const Color darkText = Color(0xFF1E293B);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  late DateTime _focusedMonth;
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = true;
  bool _isSavingEvent = false;

  List<Map<String, dynamic>> _allMonthNotes = [];
  List<Map<String, dynamic>> _selectedDayNotes = [];
  List<Map<String, dynamic>> _upcomingTodayNotes = [];

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

  @override
  void initState() {
    super.initState();
    _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    _selectedDate = DateTime.now();
    _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([_fetchMonthNotes(), _fetchTodayUpcomingNotes()]);
      _filterSelectedDayNotes();
    } catch (e) {
      debugPrint('Calendar load error: $e');
      if (mounted) {
        _showSnackBar(
          'Takvim verileri yüklenirken hata oluştu.',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchMonthNotes() async {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);

    final data = await SupabaseService().client
        .from('notes')
        .select(
          'id,title,content,note_date,note_time,end_time,color,created_at',
        )
        .eq('user_id', _userId)
        .not('note_date', 'is', null)
        .gte('note_date', _dateOnly(firstDay))
        .lte('note_date', _dateOnly(lastDay))
        .order('note_date', ascending: true)
        .order('note_time', ascending: true);

    _allMonthNotes = List<Map<String, dynamic>>.from(data);
  }

  Future<void> _fetchTodayUpcomingNotes() async {
    final today = _dateOnly(DateTime.now());

    final data = await SupabaseService().client
        .from('notes')
        .select(
          'id,title,content,note_date,note_time,end_time,color,created_at',
        )
        .eq('user_id', _userId)
        .eq('note_date', today)
        .order('note_time', ascending: true);

    _upcomingTodayNotes = List<Map<String, dynamic>>.from(data);
  }

  void _filterSelectedDayNotes() {
    final selectedKey = _dateOnly(_selectedDate);

    _selectedDayNotes = _allMonthNotes.where((note) {
      return (note['note_date'] ?? '').toString() == selectedKey;
    }).toList();
  }

  String _dateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isPastDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.isBefore(today);
  }

  String _formatTime(dynamic value) {
    if (value == null) return 'Saat belirtilmedi';
    final text = value.toString();
    if (text.length >= 5) return text.substring(0, 5);
    return text;
  }

  String _monthLabel(DateTime dt) {
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
    return '${months[dt.month]} ${dt.year}';
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
        return primaryBlue;
    }
  }

  bool _hasEventOnDay(DateTime day) {
    final key = _dateOnly(day);
    return _allMonthNotes.any(
      (note) => (note['note_date'] ?? '').toString() == key,
    );
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    final key = _dateOnly(day);
    return _allMonthNotes.where((note) {
      return (note['note_date'] ?? '').toString() == key;
    }).toList();
  }

  void _goToPreviousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
      if (_selectedDate.month != _focusedMonth.month ||
          _selectedDate.year != _focusedMonth.year) {
        _selectedDate = _focusedMonth;
      }
    });
    _loadCalendarData();
  }

  void _goToNextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
      if (_selectedDate.month != _focusedMonth.month ||
          _selectedDate.year != _focusedMonth.year) {
        _selectedDate = _focusedMonth;
      }
    });
    _loadCalendarData();
  }

  Future<void> _openAddEventDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final timeController = TextEditingController();
    final endTimeController = TextEditingController();

    DateTime selectedDate = _selectedDate;
    int selectedColor = 0;

    if (_isPastDate(selectedDate)) {
      selectedDate = DateTime.now();
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDate.isBefore(today)
                    ? today
                    : selectedDate,
                firstDate: today,
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: primaryBlue,
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
                        primary: primaryBlue,
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

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Etkinlik Ekle',
                style: TextStyle(fontWeight: FontWeight.w800, color: darkText),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogField(
                      controller: titleController,
                      label: 'Başlık',
                      hint: 'Etkinlik başlığı',
                      icon: Icons.title_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: contentController,
                      label: 'Açıklama',
                      hint: 'Etkinlik açıklaması',
                      icon: Icons.notes_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
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
                            ? 'Saat seç'
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        final color = _noteAccent(index);
                        final selected = selectedColor == index;

                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedColor = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? darkText : Colors.transparent,
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isSavingEvent
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: _isSavingEvent
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final content = contentController.text.trim();

                          if (title.isEmpty || content.isEmpty) {
                            _showSnackBar(
                              'Başlık ve açıklama zorunludur.',
                              isError: true,
                            );
                            return;
                          }

                          if (timeController.text.trim().isEmpty) {
                            _showSnackBar(
                              'Lütfen başlangıç saati seç.',
                              isError: true,
                            );
                            return;
                          }

                          if (_isPastDate(selectedDate)) {
                            _showSnackBar(
                              'Geçmiş tarihe yeni etkinlik ekleyemezsin.',
                              isError: true,
                            );
                            return;
                          }

                          setState(() => _isSavingEvent = true);

                          try {
                            await SupabaseService().client
                                .from('notes')
                                .insert({
                                  'user_id': _userId,
                                  'title': title,
                                  'content': content,
                                  'note_date': _dateOnly(selectedDate),
                                  'note_time': timeController.text.trim(),
                                  'end_time':
                                      endTimeController.text.trim().isEmpty
                                      ? null
                                      : endTimeController.text.trim(),
                                  'color': selectedColor,
                                  'images': <String>[],
                                  'tags': <String>[],
                                });

                            if (!mounted) return;

                            Navigator.pop(dialogContext);

                            setState(() {
                              _selectedDate = selectedDate;
                            });

                            await _loadCalendarData();
                            _showSnackBar('Etkinlik başarıyla eklendi.');
                          } catch (e) {
                            _showSnackBar(
                              'Etkinlik eklenirken hata oluştu: $e',
                              isError: true,
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _isSavingEvent = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Ekle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openEditEventDialog(Map<String, dynamic> event) async {
    final titleController = TextEditingController(
      text: (event['title'] ?? '').toString(),
    );
    final contentController = TextEditingController(
      text: (event['content'] ?? '').toString(),
    );
    final timeController = TextEditingController(
      text: event['note_time'] == null ? '' : _formatTime(event['note_time']),
    );
    final endTimeController = TextEditingController(
      text: event['end_time'] == null ? '' : _formatTime(event['end_time']),
    );

    DateTime selectedDate =
        DateTime.tryParse((event['note_date'] ?? '').toString()) ??
        DateTime.now();

    int selectedColor = (event['color'] ?? 0) as int;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final initial = selectedDate.isBefore(today)
                  ? today
                  : selectedDate;

              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: today,
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: primaryBlue,
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
                        primary: primaryBlue,
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

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Etkinliği Düzenle',
                style: TextStyle(fontWeight: FontWeight.w800, color: darkText),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDialogField(
                      controller: titleController,
                      label: 'Başlık',
                      hint: 'Etkinlik başlığı',
                      icon: Icons.title_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildDialogField(
                      controller: contentController,
                      label: 'Açıklama',
                      hint: 'Etkinlik açıklaması',
                      icon: Icons.notes_rounded,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
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
                            ? 'Saat seç'
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        final color = _noteAccent(index);
                        final selected = selectedColor == index;

                        return GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedColor = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected ? darkText : Colors.transparent,
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
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isSavingEvent
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: _isSavingEvent
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final content = contentController.text.trim();

                          if (title.isEmpty || content.isEmpty) {
                            _showSnackBar(
                              'Başlık ve açıklama zorunludur.',
                              isError: true,
                            );
                            return;
                          }

                          if (timeController.text.trim().isEmpty) {
                            _showSnackBar(
                              'Lütfen başlangıç saati seç.',
                              isError: true,
                            );
                            return;
                          }

                          if (_isPastDate(selectedDate)) {
                            _showSnackBar(
                              'Etkinliği geçmiş tarihe taşıyamazsın.',
                              isError: true,
                            );
                            return;
                          }

                          setState(() => _isSavingEvent = true);

                          try {
                            await SupabaseService().client
                                .from('notes')
                                .update({
                                  'title': title,
                                  'content': content,
                                  'note_date': _dateOnly(selectedDate),
                                  'note_time': timeController.text.trim(),
                                  'end_time':
                                      endTimeController.text.trim().isEmpty
                                      ? null
                                      : endTimeController.text.trim(),
                                  'color': selectedColor,
                                })
                                .eq('id', event['id']);

                            if (!mounted) return;

                            Navigator.pop(dialogContext);
                            await _loadCalendarData();
                            _showSnackBar('Etkinlik güncellendi.');
                          } catch (e) {
                            _showSnackBar(
                              'Etkinlik güncellenirken hata oluştu: $e',
                              isError: true,
                            );
                          } finally {
                            if (mounted) {
                              setState(() => _isSavingEvent = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: const Text(
                'Etkinliği Sil',
                style: TextStyle(fontWeight: FontWeight.w800, color: darkText),
              ),
              content: Text(
                '"${(event['title'] ?? 'Etkinlik').toString()}" etkinliğini silmek istiyor musun?',
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
          .eq('id', event['id']);
      await _loadCalendarData();

      if (!mounted) return;
      _showSnackBar('Etkinlik silindi.');
    } catch (e) {
      _showSnackBar('Etkinlik silinirken hata oluştu: $e', isError: true);
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
        prefixIcon: Icon(icon, color: primaryBlue),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryBlue),
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

  void _onDayTap(DateTime date) {
    setState(() {
      _selectedDate = date;
      _filterSelectedDayNotes();
    });

    final events = _eventsForDay(date);
    if (events.isNotEmpty) {
      _showDayEventsDialog(date, events);
    }
  }

  Future<void> _showDayEventsDialog(
    DateTime date,
    List<Map<String, dynamic>> events,
  ) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            '${date.day}.${date.month}.${date.year} Etkinlikleri',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: darkText,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: events.isEmpty
                ? const Text('Bu gün için etkinlik yok.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      final color = _noteAccent(event['color'] as int?);

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: color.withOpacity(0.18)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (event['title'] ?? 'Başlıksız Etkinlik')
                                  .toString(),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: darkText,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              (event['content'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 13,
                                color: mutedText,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: primaryBlue,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${_formatTime(event['note_time'])}${event['end_time'] != null ? ' - ${_formatTime(event['end_time'])}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: primaryBlue,
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    Navigator.pop(context);

                                    if (value == 'edit') {
                                      await _openEditEventDialog(event);
                                    } else if (value == 'delete') {
                                      await _deleteEvent(event);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Düzenle'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Sil'),
                                    ),
                                  ],
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
  }

  List<DateTime> _buildCalendarDays() {
    final firstDayOfMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _focusedMonth.year,
      _focusedMonth.month + 1,
      0,
    );

    final int firstWeekday = firstDayOfMonth.weekday % 7;
    final int totalDays = lastDayOfMonth.day;

    final List<DateTime> days = [];

    for (int i = 0; i < firstWeekday; i++) {
      days.add(firstDayOfMonth.subtract(Duration(days: firstWeekday - i)));
    }

    for (int day = 1; day <= totalDays; day++) {
      days.add(DateTime(_focusedMonth.year, _focusedMonth.month, day));
    }

    while (days.length % 7 != 0) {
      days.add(days.last.add(const Duration(days: 1)));
    }

    return days;
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildCalendarGrid() {
    final days = _buildCalendarDays();
    const weekDays = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: weekDays
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          day,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: mutedText,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.90,
            ),
            itemBuilder: (context, index) {
              final day = days[index];
              final inCurrentMonth = day.month == _focusedMonth.month;
              final isSelected = _isSameDate(day, _selectedDate);
              final isToday = _isSameDate(day, DateTime.now());
              final hasEvent = _hasEventOnDay(day);

              return InkWell(
                onTap: () => _onDayTap(day),
                borderRadius: BorderRadius.circular(20),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryBlue
                              : isToday
                              ? primaryBlue.withOpacity(0.10)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: !inCurrentMonth
                                  ? Colors.grey.shade400
                                  : isSelected
                                  ? Colors.white
                                  : darkText,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (hasEvent)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : primaryBlue,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const SizedBox(height: 5),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
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
                    color: primaryBlue.withOpacity(0.18),
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
          IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.agriculture_rounded, color: primaryBlue, size: 22),
                SizedBox(width: 8),
                Text(
                  'AgriSynth',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: darkBlue,
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
      color: const Color(0xFFDBEAFE),
      child: Center(
        child: Text(
          _userName.isNotEmpty ? _userName[0].toUpperCase() : 'Ç',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: primaryBlue,
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingEventsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Yaklaşan Etkinlikler',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: darkText,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_upcomingTodayNotes.length} ETKİNLİK',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: primaryBlue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_upcomingTodayNotes.isEmpty)
          _buildEmptyCard(
            title: 'Bugün için etkinlik yok',
            subtitle: 'Tarihli not eklediğinde burada görünecek.',
            icon: Icons.event_available_rounded,
          )
        else
          Column(
            children: _upcomingTodayNotes.map((event) {
              final accent = _noteAccent(event['color'] as int?);

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardWhite,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: accent.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.event_note_rounded, color: accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatTime(event['note_time']),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (event['title'] ?? 'Etkinlik').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: darkText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (event['content'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.2,
                              color: mutedText,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'detail') {
                          await _showDayEventsDialog(_selectedDate, [event]);
                        } else if (value == 'edit') {
                          await _openEditEventDialog(event);
                        } else if (value == 'delete') {
                          await _deleteEvent(event);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'detail',
                          child: Text('Detayı Gör'),
                        ),
                        PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                        PopupMenuItem(value: 'delete', child: Text('Sil')),
                      ],
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: primaryBlue,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildEmptyCard({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primaryBlue.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: primaryBlue),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
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

  Drawer _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFFFAFBFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withOpacity(0.18),
                    backgroundImage: _avatarUrl.startsWith('http')
                        ? NetworkImage(_avatarUrl)
                        : null,
                    child: !_avatarUrl.startsWith('http')
                        ? Text(
                            _userName.isNotEmpty
                                ? _userName[0].toUpperCase()
                                : 'Ç',
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
            ),
            _drawerItem(
              icon: Icons.home_rounded,
              label: 'Ana Sayfa',
              onTap: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
            _drawerItem(
              icon: Icons.calendar_month_rounded,
              label: 'Takvim',
              selected: true,
              onTap: () => Navigator.pop(context),
            ),
            _drawerItem(
              icon: Icons.note_alt_rounded,
              label: 'Notlarım',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        VetNotesScreen(userData: widget.userData),
                  ),
                );
              },
            ),
            _drawerItem(
              icon: Icons.storefront_rounded,
              label: 'İlanlar & Talepler',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        VetListingsRequestsScreen(userData: widget.userData),
                  ),
                );
              },
            ),
            _drawerItem(
              icon: Icons.work_outline_rounded,
              label: 'İş Portalı',
              onTap: () {
                Navigator.pop(context);
                _showSnackBar('İş Portalı sayfasını sonra bağlayacağız.');
              },
            ),
            _drawerItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Mesajlarım',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        VetMessagesScreen(userData: widget.userData),
                  ),
                );
              },
            ),
            _drawerItem(
              icon: Icons.manage_accounts_rounded,
              label: 'Profil Ayarları',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        VetProfileEditScreen(userData: widget.userData),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: selected ? primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected ? Colors.white : darkBlue.withOpacity(0.78),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : darkText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthNavButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, color: primaryBlue),
      ),
    );
  }

  Widget _buildCalendarLoading() {
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(30),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      drawer: VetAppDrawer(
        userData: widget.userData,
        currentPage: VetDrawerPage.calendar,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primaryBlue,
          onRefresh: _loadCalendarData,
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
                              'Takvim',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: darkBlue,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _openAddEventDialog,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: primaryBlue,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryBlue.withOpacity(0.20),
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
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _monthLabel(_focusedMonth),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: darkText,
                              ),
                            ),
                          ),
                          _monthNavButton(
                            icon: Icons.chevron_left_rounded,
                            onTap: _goToPreviousMonth,
                          ),
                          const SizedBox(width: 8),
                          _monthNavButton(
                            icon: Icons.chevron_right_rounded,
                            onTap: _goToNextMonth,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_isLoading)
                        _buildCalendarLoading()
                      else
                        _buildCalendarGrid(),
                      const SizedBox(height: 28),
                      _buildUpcomingEventsSection(),
                      const SizedBox(height: 20),
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
