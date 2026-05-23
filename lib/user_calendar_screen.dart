import 'package:flutter/material.dart';

import 'supabase_service.dart';
import 'user_app_drawer.dart';

class UserCalendarScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const UserCalendarScreen({super.key, required this.userData});

  @override
  State<UserCalendarScreen> createState() => _UserCalendarScreenState();
}

class _UserCalendarScreenState extends State<UserCalendarScreen> {
  static const Color primaryGreen = Color(0xFF1F6E43);
  static const Color darkGreen = Color(0xFF14452F);
  static const Color lightBackground = Color(0xFFF6FAF5);
  static const Color darkText = Color(0xFF101828);
  static const Color mutedText = Color(0xFF64748B);
  static const Color cardWhite = Colors.white;

  late DateTime _focusedMonth;
  late DateTime _selectedDate;

  bool _isLoading = true;
  bool _isSaving = false;

  List<Map<String, dynamic>> _monthEvents = [];
  List<Map<String, dynamic>> _selectedDayEvents = [];
  List<Map<String, dynamic>> _todayEvents = [];

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString().trim();
    if (fromData.isNotEmpty) return fromData;
    return SupabaseService().client.auth.currentUser?.id ?? '';
  }

  String get _firstName => (widget.userData['ad'] ?? widget.userData['first_name'] ?? '').toString().trim();
  String get _lastName => (widget.userData['soyad'] ?? widget.userData['last_name'] ?? '').toString().trim();
  String get _avatarUrl => (widget.userData['avatar_url'] ?? '').toString().trim();

  String get _fullName {
    final value = '$_firstName $_lastName'.trim();
    if (value.isNotEmpty) return value;
    final username = (widget.userData['username'] ?? '').toString().trim();
    return username.isNotEmpty ? username : 'Kullanıcı';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadCalendarData();
  }

  Future<void> _loadCalendarData() async {
    if (_userId.isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Kullanıcı bilgisi bulunamadı.', isError: true);
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      await Future.wait([
        _fetchMonthEvents(),
        _fetchTodayEvents(),
      ]);
      _filterSelectedDayEvents();
    } catch (e) {
      debugPrint('User calendar load error: $e');
      if (mounted) {
        _showSnackBar('Takvim verileri yüklenirken hata oluştu: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMonthEvents() async {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);

    final data = await SupabaseService().client
        .from('notes')
        .select('id,title,content,note_date,note_time,end_time,color,created_at')
        .eq('user_id', _userId)
        .not('note_date', 'is', null)
        .gte('note_date', _dateOnly(firstDay))
        .lte('note_date', _dateOnly(lastDay))
        .order('note_date', ascending: true)
        .order('note_time', ascending: true);

    _monthEvents = List<Map<String, dynamic>>.from(data);
  }

  Future<void> _fetchTodayEvents() async {
    final data = await SupabaseService().client
        .from('notes')
        .select('id,title,content,note_date,note_time,end_time,color,created_at')
        .eq('user_id', _userId)
        .eq('note_date', _dateOnly(DateTime.now()))
        .order('note_time', ascending: true);

    _todayEvents = List<Map<String, dynamic>>.from(data);
  }

  void _filterSelectedDayEvents() {
    final key = _dateOnly(_selectedDate);
    _selectedDayEvents = _monthEvents.where((event) {
      return (event['note_date'] ?? '').toString() == key;
    }).toList();
  }

  String _dateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isPastDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    return target.isBefore(today);
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  String _formatTime(dynamic value) {
    if (value == null) return 'Saat belirtilmedi';
    final text = value.toString();
    if (text.isEmpty) return 'Saat belirtilmedi';
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

  Color _eventColor(dynamic value) {
    switch (_asInt(value)) {
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

  bool _hasEventOnDay(DateTime day) {
    final key = _dateOnly(day);
    return _monthEvents.any((event) => (event['note_date'] ?? '').toString() == key);
  }

  List<Map<String, dynamic>> _eventsForDay(DateTime day) {
    final key = _dateOnly(day);
    return _monthEvents.where((event) => (event['note_date'] ?? '').toString() == key).toList();
  }

  void _goToPreviousMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
      if (_selectedDate.month != _focusedMonth.month || _selectedDate.year != _focusedMonth.year) {
        _selectedDate = _focusedMonth;
      }
    });
    _loadCalendarData();
  }

  void _goToNextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
      if (_selectedDate.month != _focusedMonth.month || _selectedDate.year != _focusedMonth.year) {
        _selectedDate = _focusedMonth;
      }
    });
    _loadCalendarData();
  }

  Future<void> _openAddEventDialog() async {
    final today = DateTime.now();
    final safeSelectedDate = _isPastDate(_selectedDate)
        ? DateTime(today.year, today.month, today.day)
        : _selectedDate;

    await _openEventDialog(
      mode: _EventDialogMode.add,
      initialDate: safeSelectedDate,
    );
  }

  Future<void> _openEditEventDialog(Map<String, dynamic> event) async {
    final initialDate = DateTime.tryParse((event['note_date'] ?? '').toString()) ?? DateTime.now();

    await _openEventDialog(
      mode: _EventDialogMode.edit,
      event: event,
      initialDate: initialDate,
    );
  }

  Future<void> _openEventDialog({
    required _EventDialogMode mode,
    required DateTime initialDate,
    Map<String, dynamic>? event,
  }) async {
    final titleController = TextEditingController(text: (event?['title'] ?? '').toString());
    final contentController = TextEditingController(text: (event?['content'] ?? '').toString());
    final timeController = TextEditingController(
      text: event == null || event['note_time'] == null ? '' : _formatTime(event['note_time']),
    );
    final endTimeController = TextEditingController(
      text: event == null || event['end_time'] == null ? '' : _formatTime(event['end_time']),
    );

    DateTime selectedDate = initialDate;
    int selectedColor = _asInt(event?['color']);

    await showDialog<void>(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final initial = selectedDate.isBefore(today) ? today : selectedDate;

              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: today,
                lastDate: DateTime(2100),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(primary: primaryGreen),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              );

              if (picked != null) setModalState(() => selectedDate = picked);
            }

            Future<void> pickTime({required bool isEnd}) async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(primary: primaryGreen),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              );

              if (picked != null) {
                final formatted = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                mode == _EventDialogMode.add ? 'Etkinlik Ekle' : 'Etkinliği Düzenle',
                style: const TextStyle(fontWeight: FontWeight.w900, color: darkText),
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
                        value: '${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => pickTime(isEnd: false),
                      borderRadius: BorderRadius.circular(16),
                      child: _buildPickerBox(
                        icon: Icons.access_time_rounded,
                        title: 'Başlangıç Saati',
                        value: timeController.text.trim().isEmpty ? 'Saat seç' : timeController.text.trim(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => pickTime(isEnd: true),
                      borderRadius: BorderRadius.circular(16),
                      child: _buildPickerBox(
                        icon: Icons.timelapse_rounded,
                        title: 'Bitiş Saati',
                        value: endTimeController.text.trim().isEmpty ? 'İsteğe bağlı' : endTimeController.text.trim(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Renk',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(6, (index) {
                        final color = _eventColor(index);
                        final selected = selectedColor == index;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedColor = index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
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
                                ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
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
                  onPressed: _isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          await _saveEvent(
                            mode: mode,
                            event: event,
                            selectedDate: selectedDate,
                            title: titleController.text.trim(),
                            content: contentController.text.trim(),
                            noteTime: timeController.text.trim(),
                            endTime: endTimeController.text.trim(),
                            color: selectedColor,
                            dialogContext: dialogContext,
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(mode == _EventDialogMode.add ? 'Ekle' : 'Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    contentController.dispose();
    timeController.dispose();
    endTimeController.dispose();
  }

  Future<void> _saveEvent({
    required _EventDialogMode mode,
    required DateTime selectedDate,
    required String title,
    required String content,
    required String noteTime,
    required String endTime,
    required int color,
    required BuildContext dialogContext,
    Map<String, dynamic>? event,
  }) async {
    if (title.isEmpty || content.isEmpty) {
      _showSnackBar('Başlık ve açıklama zorunludur.', isError: true);
      return;
    }

    if (noteTime.isEmpty) {
      _showSnackBar('Lütfen başlangıç saati seç.', isError: true);
      return;
    }

    if (_isPastDate(selectedDate)) {
      _showSnackBar('Geçmiş tarihe etkinlik eklenemez.', isError: true);
      return;
    }

    if (mounted) setState(() => _isSaving = true);

    try {
      final payload = <String, dynamic>{
        'title': title,
        'content': content,
        'note_date': _dateOnly(selectedDate),
        'note_time': noteTime,
        'end_time': endTime.isEmpty ? null : endTime,
        'color': color,
      };

      if (mode == _EventDialogMode.add) {
        payload['user_id'] = _userId;
        await SupabaseService().client.from('notes').insert(payload);
      } else {
        await SupabaseService().client.from('notes').update(payload).eq('id', event?['id']);
      }

      if (!mounted) return;
      Navigator.pop(dialogContext);
      setState(() => _selectedDate = selectedDate);
      await _loadCalendarData();
      _showSnackBar(mode == _EventDialogMode.add ? 'Etkinlik başarıyla eklendi.' : 'Etkinlik güncellendi.');
    } catch (e) {
      if (mounted) {
        _showSnackBar('Etkinlik kaydedilemedi: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
              title: const Text(
                'Etkinliği Sil',
                style: TextStyle(fontWeight: FontWeight.w900, color: darkText),
              ),
              content: Text('"${(event['title'] ?? 'Etkinlik').toString()}" etkinliğini silmek istiyor musun?'),
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
      await SupabaseService().client.from('notes').delete().eq('id', event['id']);
      await _loadCalendarData();
      if (mounted) _showSnackBar('Etkinlik silindi.');
    } catch (e) {
      if (mounted) _showSnackBar('Etkinlik silinirken hata oluştu: $e', isError: true);
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

  void _onDayTap(DateTime date) {
    setState(() {
      _selectedDate = date;
      _filterSelectedDayEvents();
    });

    final events = _eventsForDay(date);
    if (events.isNotEmpty) _showDayEventsDialog(date, events);
  }

  Future<void> _showDayEventsDialog(DateTime date, List<Map<String, dynamic>> events) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            '${date.day}.${date.month}.${date.year} Etkinlikleri',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: darkText),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: events.isEmpty
                ? const Text('Bu gün için etkinlik yok.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: events.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _dayEventTile(context, events[index]),
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

  Widget _dayEventTile(BuildContext dialogContext, Map<String, dynamic> event) {
    final color = _eventColor(event['color']);
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
            (event['title'] ?? 'Başlıksız Etkinlik').toString(),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: darkText),
          ),
          const SizedBox(height: 6),
          Text(
            (event['content'] ?? '').toString(),
            style: const TextStyle(fontSize: 13, color: mutedText, height: 1.35),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_formatTime(event['note_time'])}${event['end_time'] != null ? ' - ${_formatTime(event['end_time'])}' : ''}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  Navigator.pop(dialogContext);
                  if (value == 'edit') {
                    await _openEditEventDialog(event);
                  } else if (value == 'delete') {
                    await _deleteEvent(event);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
                icon: const Icon(Icons.more_vert_rounded, color: primaryGreen),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<DateTime> _buildCalendarDays() {
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final firstWeekday = firstDayOfMonth.weekday % 7;
    final totalDays = lastDayOfMonth.day;
    final days = <DateTime>[];

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

  Widget _buildCalendarGrid() {
    final days = _buildCalendarDays();
    const weekDays = ['PAZ', 'PZT', 'SAL', 'ÇAR', 'PER', 'CUM', 'CTS'];

    return Container(
      padding: const EdgeInsets.all(16),
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
            children: weekDays.map((day) {
              return Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      day,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: mutedText,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: days.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.88,
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
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryGreen
                              : isToday
                                  ? primaryGreen.withOpacity(0.10)
                                  : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected || isToday ? FontWeight.w900 : FontWeight.w600,
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
                            color: isSelected ? Colors.white : primaryGreen,
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
      height: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Builder(
                builder: (context) {
                  return InkWell(
                    onTap: () => Scaffold.of(context).openDrawer(),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 46,
                      height: 46,
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
                  border: Border.all(color: primaryGreen.withOpacity(0.18), width: 2),
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
          _firstName.isNotEmpty ? _firstName[0].toUpperCase() : 'N',
          style: const TextStyle(fontWeight: FontWeight.w900, color: primaryGreen),
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
                'Bugünkü Etkinlikler',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: darkText),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_todayEvents.length} ETKİNLİK',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: primaryGreen),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_todayEvents.isEmpty)
          _buildEmptyCard(
            title: 'Bugün için etkinlik yok',
            subtitle: 'Tarihli not eklediğinde burada görünecek.',
            icon: Icons.event_available_rounded,
          )
        else
          Column(
            children: _todayEvents.map((event) => _upcomingEventTile(event)).toList(),
          ),
      ],
    );
  }

  Widget _upcomingEventTile(Map<String, dynamic> event) {
    final accent = _eventColor(event['color']);
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
            decoration: BoxDecoration(color: accent.withOpacity(0.10), shape: BoxShape.circle),
            child: Icon(Icons.event_note_rounded, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(event['note_time']),
                  style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  (event['title'] ?? 'Etkinlik').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: darkText),
                ),
                const SizedBox(height: 4),
                Text(
                  (event['content'] ?? '').toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.2, color: mutedText, height: 1.35),
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
              PopupMenuItem(value: 'detail', child: Text('Detayı Gör')),
              PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              PopupMenuItem(value: 'delete', child: Text('Sil')),
            ],
            icon: const Icon(Icons.more_vert_rounded, color: primaryGreen),
          ),
        ],
      ),
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
            decoration: BoxDecoration(color: primaryGreen.withOpacity(0.08), shape: BoxShape.circle),
            child: Icon(icon, color: primaryGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: darkText),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: mutedText, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarLoading() {
    return Container(
      height: 330,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.circular(30),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: primaryGreen),
      ),
    );
  }

  Widget _monthNavButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Icon(icon, color: primaryGreen),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      drawer: UserAppDrawer(
        userData: widget.userData,
        currentPage: UserDrawerPage.calendar,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: primaryGreen,
          onRefresh: _loadCalendarData,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
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
                                color: darkGreen,
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
                              child: const Icon(Icons.add_rounded, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$_fullName için not ve etkinlik takibi',
                        style: const TextStyle(fontSize: 13, color: mutedText, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _monthLabel(_focusedMonth),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: darkText),
                            ),
                          ),
                          _monthNavButton(icon: Icons.chevron_left_rounded, onTap: _goToPreviousMonth),
                          const SizedBox(width: 8),
                          _monthNavButton(icon: Icons.chevron_right_rounded, onTap: _goToNextMonth),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_isLoading) _buildCalendarLoading() else _buildCalendarGrid(),
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

enum _EventDialogMode { add, edit }
