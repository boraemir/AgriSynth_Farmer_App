
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'farmer_app_drawer.dart';
import 'messages.dart';

enum _JobsTab { jobs, employer, myApplications }

class JobsScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const JobsScreen({super.key, required this.userData});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  static const Color primaryGreen = Color(0xFF10B981);
  static const Color darkGreen = Color(0xFF065F46);
  static const Color deepGreen = Color(0xFF064E3B);
  static const Color pageBg = Color(0xFFF8FAFC);
  static const Color cardBg = Colors.white;
  static const Color surfaceHover = Color(0xFFF1F5F9);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textMuted = Color(0xFF64748B);
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isApplying = false;
  bool _isEmployerLoading = false;
  bool _isMyAppsLoading = false;

  _JobsTab _activeTab = _JobsTab.jobs;
  String _selectedFilter = 'all';

  List<Map<String, dynamic>> _jobs = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _myApplications = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _employerApplications = <Map<String, dynamic>>[];

  String get _userId {
    final fromData = (widget.userData['id'] ?? '').toString();
    if (fromData.isNotEmpty) return fromData;
    return _client.auth.currentUser?.id ?? '';
  }

  String get _userName => (widget.userData['ad'] ?? '').toString();
  String get _userSurname => (widget.userData['soyad'] ?? '').toString();
  String get _avatarUrl => (widget.userData['avatar_url'] ?? '').toString();
  String get _roleValue => (widget.userData['rol'] ?? '').toString().toLowerCase().trim();

  bool get _isEmployer => _roleValue == 'ciftci' || _roleValue == 'çiftçi';

  String get _fullName {
    final full = '$_userName $_userSurname'.trim();
    return full.isEmpty ? 'Kullanıcı' : full;
  }

  String get _roleLabel {
    switch (_roleValue) {
      case 'ciftci':
      case 'çiftçi':
        return 'Çiftçi';
      case 'doktor':
        return 'Veteriner';
      case 'user':
        return 'Normal Kullanıcı';
      default:
        return 'Kullanıcı';
    }
  }

  List<Map<String, dynamic>> get _myJobs =>
      _jobs.where((job) => (job['user_id'] ?? '').toString() == _userId).toList();

  int get _pendingApplicationCount =>
      _employerApplications.where((app) => (app['status'] ?? '') == 'pending').length;

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  List<_FilterOption> get _filterOptions => const <_FilterOption>[
        _FilterOption(key: 'all', label: 'Tümü'),
        _FilterOption(key: 'fulltime', label: 'Tam Zamanlı'),
        _FilterOption(key: 'parttime', label: 'Yarı Zamanlı'),
        _FilterOption(key: 'seasonal', label: 'Mevsimlik'),
      ];

  List<Map<String, dynamic>> get _filteredJobs {
    Iterable<Map<String, dynamic>> items = _jobs;

    if (_selectedFilter != 'all') {
      items = items.where(
        (job) => (job['job_type'] ?? '').toString().toLowerCase() == _selectedFilter,
      );
    }

    if (_searchQuery.isNotEmpty) {
      items = items.where((job) {
        final haystack = <Object?>[
          job['title'],
          job['company_name'],
          job['location'],
          job['description'],
          job['salary_range'],
          job['instructions'],
          job['contact_info'],
          job['owner_name'],
          ...(job['skills'] as List<String>? ?? const <String>[]),
        ].join(' ').toLowerCase();
        return haystack.contains(_searchQuery);
      });
    }

    return items.toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await _loadJobs();
    await Future.wait(<Future<void>>[
      if (_isEmployer) _loadEmployerDashboard(),
      if (!_isEmployer) _loadMyApplications(),
    ]);
  }

  Future<void> _refreshCurrentTab() async {
    if (_activeTab == _JobsTab.jobs) {
      await _loadJobs();
    } else if (_activeTab == _JobsTab.employer) {
      await _loadJobs();
      await _loadEmployerDashboard();
    } else {
      await _loadJobs();
      await _loadMyApplications();
    }
  }

  Future<void> _loadJobs() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      List<Map<String, dynamic>> rawJobs;

      try {
        final rows = await _client
            .from('jobs')
            .select(
              'id,user_id,title,company_name,job_type,location,salary_range,description,company_logo,created_at,deadline,skills,contact_info,instructions',
            )
            .order('created_at', ascending: false);

        rawJobs = List<Map<String, dynamic>>.from(rows);
      } catch (_) {
        final rows = await _client
            .from('jobs')
            .select(
              'id,user_id,title,company_name,job_type,location,salary_range,description,company_logo,created_at,deadline,skills,instructions',
            )
            .order('created_at', ascending: false);

        rawJobs = List<Map<String, dynamic>>.from(rows);
      }

      final userIds = rawJobs
          .map((job) => (job['user_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usersById = <String, Map<String, dynamic>>{};
      if (userIds.isNotEmpty) {
        try {
          final rows = await _client
              .from('users')
              .select('id, ad, soyad, email, telefon, sehir, avatar_url, rol')
              .inFilter('id', userIds);

          for (final user in List<Map<String, dynamic>>.from(rows)) {
            final id = (user['id'] ?? '').toString();
            if (id.isNotEmpty) usersById[id] = user;
          }
        } catch (_) {
          // Kullanıcı relation/permission sorunu ilanların yüklenmesini engellemesin.
        }
      }

      final jobs = rawJobs.map((job) {
        final ownerId = (job['user_id'] ?? '').toString();
        final owner = usersById[ownerId] ?? <String, dynamic>{};
        final createdAt =
            DateTime.tryParse((job['created_at'] ?? '').toString()) ?? DateTime.now();

        return <String, dynamic>{
          'id': (job['id'] ?? '').toString(),
          'user_id': ownerId,
          'title': (job['title'] ?? '').toString(),
          'company_name': (job['company_name'] ?? '').toString(),
          'job_type': (job['job_type'] ?? '').toString().toLowerCase(),
          'job_type_label': _jobTypeLabel((job['job_type'] ?? '').toString()),
          'location': (job['location'] ?? '').toString(),
          'salary_range': (job['salary_range'] ?? '').toString(),
          'description': (job['description'] ?? '').toString(),
          'company_logo': (job['company_logo'] ?? '').toString(),
          'created_at': createdAt,
          'deadline': _parseDate(job['deadline']),
          'skills': _normalizeSkills(job['skills']),
          'contact_info': (job['contact_info'] ?? '').toString(),
          'instructions': (job['instructions'] ?? '').toString(),
          'owner_name': _buildOwnerName(owner),
          'owner_avatar': (owner['avatar_url'] ?? '').toString(),
          'owner_email': (owner['email'] ?? '').toString(),
          'owner_phone': (owner['telefon'] ?? '').toString(),
          'owner_city': (owner['sehir'] ?? '').toString(),
          'owner_role': _mapRoleLabel((owner['rol'] ?? '').toString()),
        };
      }).toList();

      if (!mounted) return;
      setState(() => _jobs = jobs);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('İlanlar yüklenirken hata oluştu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMyApplications() async {
    if (_userId.isEmpty) return;
    if (mounted) setState(() => _isMyAppsLoading = true);

    try {
      final rows = await _client
          .from('applications')
          .select('id, status, created_at, job_id, applicant_id')
          .eq('applicant_id', _userId)
          .order('created_at', ascending: false);

      final apps = List<Map<String, dynamic>>.from(rows);
      final jobIds = apps
          .map((app) => (app['job_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      final jobMap = <String, Map<String, dynamic>>{
        for (final job in _jobs) (job['id'] ?? '').toString(): job,
      };

      final missingJobIds = jobIds.where((id) => !jobMap.containsKey(id)).toList();
      if (missingJobIds.isNotEmpty) {
        try {
          final jobRows = await _client
              .from('jobs')
              .select(
                'id,user_id,title,company_name,job_type,location,salary_range,description,created_at,deadline,skills,instructions',
              )
              .inFilter('id', missingJobIds);

          for (final job in List<Map<String, dynamic>>.from(jobRows)) {
            final id = (job['id'] ?? '').toString();
            if (id.isNotEmpty) {
              jobMap[id] = <String, dynamic>{
                ...job,
                'job_type_label': _jobTypeLabel((job['job_type'] ?? '').toString()),
                'deadline': _parseDate(job['deadline']),
                'created_at':
                    DateTime.tryParse((job['created_at'] ?? '').toString()) ?? DateTime.now(),
                'skills': _normalizeSkills(job['skills']),
              };
            }
          }
        } catch (_) {}
      }

      final normalized = apps.map((app) {
        final jobId = (app['job_id'] ?? '').toString();
        return <String, dynamic>{
          ...app,
          'id': (app['id'] ?? '').toString(),
          'job_id': jobId,
          'status': (app['status'] ?? 'pending').toString(),
          'created_at':
              DateTime.tryParse((app['created_at'] ?? '').toString()) ?? DateTime.now(),
          'job': jobMap[jobId] ?? <String, dynamic>{},
        };
      }).toList();

      if (!mounted) return;
      setState(() => _myApplications = normalized);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Başvurularınız yüklenirken hata oluştu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isMyAppsLoading = false);
    }
  }

  Future<void> _loadEmployerDashboard() async {
    if (_userId.isEmpty) return;
    if (mounted) setState(() => _isEmployerLoading = true);

    try {
      final myJobIds = _myJobs
          .map((job) => (job['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();

      if (myJobIds.isEmpty) {
        if (mounted) setState(() => _employerApplications = <Map<String, dynamic>>[]);
        return;
      }

      final appRows = await _client
          .from('applications')
          .select('id, status, created_at, job_id, applicant_id')
          .inFilter('job_id', myJobIds)
          .order('created_at', ascending: false);

      final apps = List<Map<String, dynamic>>.from(appRows);

      final applicantIds = apps
          .map((app) => (app['applicant_id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final usersById = <String, Map<String, dynamic>>{};
      if (applicantIds.isNotEmpty) {
        try {
          final userRows = await _client
              .from('users')
              .select('id, ad, soyad, email, telefon, sehir, avatar_url, rol')
              .inFilter('id', applicantIds);

          for (final user in List<Map<String, dynamic>>.from(userRows)) {
            final id = (user['id'] ?? '').toString();
            if (id.isNotEmpty) usersById[id] = user;
          }
        } catch (_) {}
      }

      final jobMap = <String, Map<String, dynamic>>{
        for (final job in _jobs) (job['id'] ?? '').toString(): job,
      };

      final normalized = apps.map((app) {
        final jobId = (app['job_id'] ?? '').toString();
        final applicantId = (app['applicant_id'] ?? '').toString();
        return <String, dynamic>{
          ...app,
          'id': (app['id'] ?? '').toString(),
          'job_id': jobId,
          'applicant_id': applicantId,
          'status': (app['status'] ?? 'pending').toString(),
          'created_at':
              DateTime.tryParse((app['created_at'] ?? '').toString()) ?? DateTime.now(),
          'job': jobMap[jobId] ?? <String, dynamic>{},
          'user': usersById[applicantId] ?? <String, dynamic>{},
        };
      }).toList();

      if (!mounted) return;
      setState(() => _employerApplications = normalized);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Gelen başvurular yüklenirken hata oluştu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isEmployerLoading = false);
    }
  }

  Future<void> _openJobForm({Map<String, dynamic>? job}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _JobFormScreen(
          userId: _userId,
          client: _client,
          initialJob: job,
        ),
      ),
    );

    if (changed == true) {
      await _loadJobs();
      if (_isEmployer) await _loadEmployerDashboard();
    }
  }

  Future<void> _applyToJob(Map<String, dynamic> job) async {
    if (_isApplying) return;

    final jobId = (job['id'] ?? '').toString();
    final ownerId = (job['user_id'] ?? '').toString();

    if (_userId.isEmpty) {
      _showSnackBar('Oturum bilgisi bulunamadı.', isError: true);
      return;
    }

    if (ownerId == _userId) {
      _showSnackBar('Kendi ilanınıza başvuramazsınız.', isError: true);
      return;
    }

    final confirmed = await _confirmDialog(
      title: 'Başvuru Onayı',
      message: '"${_safeText(job['title'])}" ilanına başvurmak istiyor musunuz?',
      confirmText: 'Başvur',
    );

    if (!confirmed) return;

    setState(() => _isApplying = true);

    try {
      await _client.from('applications').insert(<String, dynamic>{
        'job_id': jobId,
        'applicant_id': _userId,
        'status': 'pending',
      });

      if (!mounted) return;
      _showSnackBar('Başvurunuz işverene iletildi.');
      if (!_isEmployer) await _loadMyApplications();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.code == '23505') {
        _showSnackBar('Bu ilana zaten başvurdunuz.', isError: true);
      } else {
        _showSnackBar('Başvuru sırasında hata oluştu: ${e.message}', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Başvuru sırasında hata oluştu: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _deleteJob(Map<String, dynamic> job) async {
    final jobId = (job['id'] ?? '').toString();
    if (jobId.isEmpty) return;

    final confirmed = await _confirmDialog(
      title: 'İlanı Sil',
      message:
          'Bu ilanı silmek istediğinize emin misiniz?\n\nBu ilana yapılan başvurular da silinebilir.',
      confirmText: 'Sil',
      isDanger: true,
    );

    if (!confirmed) return;

    try {
      try {
        await _client.from('applications').delete().eq('job_id', jobId);
      } catch (_) {
        // DB cascade varsa veya RLS izin vermiyorsa sadece job silmeyi dener.
      }

      await _client.from('jobs').delete().eq('id', jobId).eq('user_id', _userId);

      if (!mounted) return;
      _showSnackBar('İlan silindi.');
      await _loadJobs();
      if (_isEmployer) await _loadEmployerDashboard();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('İlan silinirken hata oluştu: $e', isError: true);
    }
  }

  Future<void> _updateApplicationStatus(String appId, String status) async {
    final isAccepted = status == 'accepted';

    final confirmed = await _confirmDialog(
      title: isAccepted ? 'Adayı Kabul Et' : 'Adayı Reddet',
      message: isAccepted
          ? 'Bu adayı kabul etmek istediğinize emin misiniz?'
          : 'Bu adayı reddetmek istediğinize emin misiniz?',
      confirmText: isAccepted ? 'Kabul Et' : 'Reddet',
      isDanger: !isAccepted,
    );

    if (!confirmed) return;

    try {
      await _client.from('applications').update({'status': status}).eq('id', appId);
      if (!mounted) return;
      _showSnackBar(isAccepted ? 'Aday kabul edildi.' : 'Aday reddedildi.');
      await _loadEmployerDashboard();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Başvuru durumu güncellenemedi: $e', isError: true);
    }
  }

  Future<void> _startChatWithPoster(Map<String, dynamic> job) async {
    final otherUserId = (job['user_id'] ?? '').toString();
    if (otherUserId.isEmpty || otherUserId == _userId) return;

    try {
      final first = _userId.compareTo(otherUserId) <= 0 ? _userId : otherUserId;
      final second = _userId.compareTo(otherUserId) <= 0 ? otherUserId : _userId;

      final existing = await _client
          .from('chats')
          .select('id')
          .eq('user1_id', first)
          .eq('user2_id', second)
          .maybeSingle();

      if (existing == null) {
        await _client.from('chats').insert({'user1_id': first, 'user2_id': second});
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessagesScreen(userData: widget.userData),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Sohbet başlatılamadı: $e', isError: true);
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmText,
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(title),
          content: Text(message, style: const TextStyle(height: 1.45)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDanger ? danger : primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showJobDetail(Map<String, dynamic> job, {bool fromEmployer = false}) {
    final isOwn = (job['user_id'] ?? '').toString() == _userId;
    final skills = job['skills'] as List<String>? ?? const <String>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          maxChildSize: 0.96,
          minChildSize: 0.48,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: pageBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: EdgeInsets.zero,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [deepGreen, darkGreen],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _companyLogo(job, size: 60, dark: true),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _safeText(job['company_name'], fallback: 'Şirket'),
                                          style: const TextStyle(
                                            color: Color(0xFF6EE7B7),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          _safeText(job['title'], fallback: 'İş İlanı'),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            height: 1.12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'İlanı veren: ${_safeText(job['owner_name'], fallback: 'Kullanıcı')}',
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.62),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.pop(sheetContext),
                                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _heroPill(Icons.location_on_rounded, _safeText(job['location'])),
                                  _heroPill(Icons.work_rounded, _safeText(job['job_type_label'])),
                                  if (_safeText(job['salary_range']).isNotEmpty)
                                    _heroPill(Icons.payments_rounded, _safeText(job['salary_range'])),
                                  _heroPill(Icons.calendar_today_rounded, _formatDate(job['created_at'])),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _detailSection(
                          icon: Icons.notes_rounded,
                          title: 'İş Tanımı',
                          child: Text(
                            _safeText(job['description'], fallback: 'Açıklama eklenmemiş.'),
                            style: const TextStyle(
                              color: textMuted,
                              fontSize: 14,
                              height: 1.65,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        _detailSection(
                          icon: Icons.verified_rounded,
                          title: 'Aranan Nitelikler',
                          child: skills.isEmpty
                              ? const Text(
                                  'Özel bir yetenek belirtilmemiş.',
                                  style: TextStyle(color: textMuted, fontWeight: FontWeight.w600),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: skills
                                      .map(
                                        (skill) => Chip(
                                          label: Text(skill),
                                          backgroundColor: const Color(0xFFEAFBF3),
                                          side: const BorderSide(color: Color(0xFFD0F2E2)),
                                          labelStyle: const TextStyle(
                                            color: darkGreen,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                        _detailSection(
                          icon: Icons.info_outline_rounded,
                          title: 'Detaylar',
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _infoBox(
                                      icon: Icons.schedule_rounded,
                                      label: 'Son Başvuru',
                                      value: _formatNullableDate(job['deadline']),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _infoBox(
                                      icon: Icons.work_outline_rounded,
                                      label: 'Çalışma Tipi',
                                      value: _safeText(job['job_type_label'], fallback: '—'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _infoBox(
                                      icon: Icons.place_rounded,
                                      label: 'Konum',
                                      value: _safeText(job['location'], fallback: '—'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _infoBox(
                                      icon: Icons.message_rounded,
                                      label: 'İletişim',
                                      value: _safeText(
                                        job['instructions'],
                                        fallback: _safeText(
                                          job['contact_info'],
                                          fallback: 'Sistem üzerinden başvurun',
                                        ),
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
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                      decoration: const BoxDecoration(
                        color: surfaceHover,
                        border: Border(top: BorderSide(color: borderColor)),
                      ),
                      child: fromEmployer || isOwn
                          ? Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _openJobForm(job: job);
                                    },
                                    icon: const Icon(Icons.edit_rounded),
                                    label: const Text('Düzenle'),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(52),
                                      foregroundColor: textDark,
                                      side: const BorderSide(color: borderColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _deleteJob(job);
                                    },
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    label: const Text('Sil'),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(52),
                                      backgroundColor: danger,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.pop(sheetContext),
                                  icon: const Icon(Icons.close_rounded),
                                  label: const Text('Kapat'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(112, 52),
                                    foregroundColor: textMuted,
                                    side: const BorderSide(color: borderColor),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(sheetContext);
                                      _startChatWithPoster(job);
                                    },
                                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                                    label: const Text('Mesaj Gönder'),
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(52),
                                      backgroundColor: info,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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

  void _showApplicantDetail(Map<String, dynamic> app) {
    final user = Map<String, dynamic>.from(app['user'] as Map? ?? <String, dynamic>{});
    final fullName = _buildOwnerName(user);
    final applicationDate = _formatDate(app['created_at']);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxHeight = MediaQuery.of(sheetContext).size.height * 0.82;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 30,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _avatarOrInitial(user['avatar_url'], fullName, size: 62),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textDark,
                                  fontSize: 20,
                                  height: 1.15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Başvuru: $applicationDate',
                                style: const TextStyle(
                                  color: textMuted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            foregroundColor: textMuted,
                            backgroundColor: surfaceHover,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'İletişim Bilgileri',
                      style: TextStyle(
                        color: primaryGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _contactBox(
                      icon: Icons.mail_outline_rounded,
                      label: 'E-posta',
                      value: _safeText(user['email'], fallback: 'Eklenmemiş'),
                    ),
                    const SizedBox(height: 10),
                    _contactBox(
                      icon: Icons.phone_rounded,
                      label: 'Telefon',
                      value: _safeText(user['telefon'], fallback: 'Eklenmemiş'),
                    ),
                    const SizedBox(height: 10),
                    _contactBox(
                      icon: Icons.location_on_outlined,
                      label: 'Yaşadığı Yer',
                      value: _safeText(user['sehir'], fallback: 'Belirtilmemiş'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _changeTab(_JobsTab tab) async {
    if (!mounted) return;
    setState(() => _activeTab = tab);

    if (tab == _JobsTab.employer) {
      await _loadJobs();
      await _loadEmployerDashboard();
    } else if (tab == _JobsTab.myApplications) {
      await _loadJobs();
      await _loadMyApplications();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      drawer: FarmerAppDrawer(
        userData: widget.userData,
        currentPage: FarmerDrawerPage.jobs,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: primaryGreen,
          onRefresh: _refreshCurrentTab,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: _buildTopBar()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _buildHeader(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _buildTabs(),
                ),
              ),
              if (_activeTab == _JobsTab.jobs) ..._buildJobsSlivers()
              else if (_activeTab == _JobsTab.employer) ..._buildEmployerSlivers()
              else ..._buildMyApplicationSlivers(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildJobsSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            children: [
              _buildSearchBar(),
              const SizedBox(height: 12),
              _buildFilterChips(),
            ],
          ),
        ),
      ),
      if (_isLoading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: primaryGreen)),
        )
      else if (_filteredJobs.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: _emptyState('Uygun ilan bulunamadı.'))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 26),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index.isOdd) return const SizedBox(height: 16);
                return _buildJobCard(_filteredJobs[index ~/ 2]);
              },
              childCount: _filteredJobs.length * 2 - 1,
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildEmployerSlivers() {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      icon: Icons.work_rounded,
                      value: _myJobs.length.toString(),
                      label: 'Aktif İlanım',
                      color: primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      icon: Icons.groups_rounded,
                      value: _employerApplications.length.toString(),
                      label: 'Toplam Başvuru',
                      color: info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      icon: Icons.notifications_active_rounded,
                      value: _pendingApplicationCount.toString(),
                      label: 'Yeni Bekleyen',
                      color: warning,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _sectionHeader(
                'Aktif İlanlarım',
                actionLabel: 'Yeni İlan',
                onAction: () => _openJobForm(),
              ),
            ],
          ),
        ),
      ),
      if (_isEmployerLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator(color: primaryGreen)),
          ),
        )
      else ...[
        if (_myJobs.isEmpty)
          SliverToBoxAdapter(child: _emptyState('Aktif ilanınız bulunmuyor.'))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index.isOdd) return const SizedBox(height: 12);
                  return _buildEmployerJobCard(_myJobs[index ~/ 2]);
                },
                childCount: _myJobs.length * 2 - 1,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: _sectionHeader('Gelen Başvurular'),
          ),
        ),
        if (_employerApplications.isEmpty)
          SliverToBoxAdapter(child: _emptyState('İlanlarınıza henüz başvuru yapılmamış.'))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index.isOdd) return const SizedBox(height: 12);
                  return _buildApplicantCard(_employerApplications[index ~/ 2]);
                },
                childCount: _employerApplications.length * 2 - 1,
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _buildMyApplicationSlivers() {
    return [
      if (_isMyAppsLoading)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: primaryGreen)),
        )
      else if (_myApplications.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _emptyState('Henüz başvuru yapılmadı.'),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index.isOdd) return const SizedBox(height: 14);
                return _buildMyApplicationCard(_myApplications[index ~/ 2]);
              },
              childCount: _myApplications.length * 2 - 1,
            ),
          ),
        ),
    ];
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: SizedBox(
        height: 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (context) {
                  return IconButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    icon: const Icon(Icons.menu_rounded, color: textDark),
                  );
                },
              ),
            ),
            const IgnorePointer(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.eco_rounded, color: primaryGreen, size: 26),
                  SizedBox(width: 8),
                  Text(
                    'AgriSynth',
                    style: TextStyle(
                      color: textDark,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _avatarOrInitial(_avatarUrl, _fullName, size: 42),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    String title;
    String subtitle;
    IconData icon;

    switch (_activeTab) {
      case _JobsTab.jobs:
        title = 'İş Arama';
        subtitle = 'Tarım sektöründe uygun güncel iş fırsatlarını keşfedin.';
        icon = Icons.search_rounded;
        break;
      case _JobsTab.employer:
        title = 'İşveren Paneli';
        subtitle = 'İlanlarınızı yönetin ve gelen başvuruları inceleyin.';
        icon = Icons.business_center_rounded;
        break;
      case _JobsTab.myApplications:
        title = 'Başvurularım';
        subtitle = 'Yaptığınız iş başvurularını ve güncel durumlarını takip edin.';
        icon = Icons.assignment_turned_in_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [darkGreen, primaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3310B981),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.82),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_isEmployer && _activeTab != _JobsTab.myApplications)
            IconButton(
              onPressed: () => _openJobForm(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: primaryGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = <_TabInfo>[
      const _TabInfo(tab: _JobsTab.jobs, label: 'İş Arama', icon: Icons.work_outline_rounded),
      if (_isEmployer)
        const _TabInfo(
          tab: _JobsTab.employer,
          label: 'İşveren Paneli',
          icon: Icons.groups_rounded,
        )
      else
        const _TabInfo(
          tab: _JobsTab.myApplications,
          label: 'Başvurularım',
          icon: Icons.file_copy_rounded,
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: tabs.map((tab) {
          final selected = _activeTab == tab.tab;
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              onTap: () => _changeTab(tab.tab),
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? primaryGreen : cardBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: selected ? primaryGreen : borderColor),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: Color(0x2210B981),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      tab.icon,
                      color: selected ? Colors.white : textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tab.label,
                      style: TextStyle(
                        color: selected ? Colors.white : textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Pozisyon, şirket veya yetenek ara...',
          hintStyle: const TextStyle(color: textMuted, fontWeight: FontWeight.w500),
          prefixIcon: const Icon(Icons.search_rounded, color: primaryGreen),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: _searchController.clear,
                  icon: const Icon(Icons.close_rounded),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _filterOptions.map((filter) {
          final selected = _selectedFilter == filter.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              label: Text(filter.label),
              selectedColor: primaryGreen,
              backgroundColor: cardBg,
              side: BorderSide(color: selected ? primaryGreen : borderColor),
              labelStyle: TextStyle(
                color: selected ? Colors.white : textMuted,
                fontWeight: FontWeight.w800,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              onSelected: (_) => setState(() => _selectedFilter = filter.key),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final isOwn = (job['user_id'] ?? '').toString() == _userId;

    return InkWell(
      onTap: () => _showJobDetail(job),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 6,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryGreen, Color(0xFF34D399), Color(0xFF6EE7B7)],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _companyLogo(job),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _safeText(job['company_name'], fallback: 'Şirket'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: textDark,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.person_rounded, size: 12, color: textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _safeText(job['owner_name'], fallback: 'Kullanıcı'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _typeBadge(_safeText(job['job_type_label'], fallback: 'İş')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _safeText(job['title'], fallback: 'İş İlanı'),
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 18,
                      height: 1.28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _safeText(job['description'], fallback: 'Açıklama eklenmemiş.'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: textMuted,
                      fontSize: 13,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      _metaPill(Icons.location_on_rounded, _safeText(job['location'], fallback: '—')),
                      _metaPill(Icons.calendar_today_rounded, _formatDate(job['created_at'])),
                      if (_safeText(job['salary_range']).isNotEmpty)
                        _metaPill(Icons.payments_rounded, _safeText(job['salary_range']), accent: true),
                      if (job['deadline'] != null)
                        _metaPill(
                          Icons.schedule_rounded,
                          'Son: ${_formatNullableDate(job['deadline'])}',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: const BoxDecoration(
                color: surfaceHover,
                border: Border(top: BorderSide(color: borderColor)),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showJobDetail(job),
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('Detaylı İncele'),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployerJobCard(Map<String, dynamic> job) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 18, offset: Offset(0, 7)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [primaryGreen, Color(0xFF34D399)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _safeText(job['title'], fallback: 'İş İlanı'),
                    style: const TextStyle(
                      color: textDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _safeText(job['company_name'], fallback: 'Şirket'),
                    style: const TextStyle(
                      color: primaryGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _smallMeta(Icons.location_on_rounded, _safeText(job['location'], fallback: '—')),
                      _smallMeta(Icons.work_rounded, _safeText(job['job_type_label'], fallback: '—')),
                      if (_safeText(job['salary_range']).isNotEmpty)
                        _smallMeta(Icons.payments_rounded, _safeText(job['salary_range'])),
                      if (job['deadline'] != null)
                        _smallMeta(Icons.schedule_rounded, _formatNullableDate(job['deadline'])),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showJobDetail(job, fromEmployer: true),
                          icon: const Icon(Icons.visibility_rounded, size: 17),
                          label: const Text('Detay'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: info,
                            side: const BorderSide(color: info),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _deleteJob(job),
                        icon: const Icon(Icons.delete_outline_rounded),
                        style: IconButton.styleFrom(
                          foregroundColor: danger,
                          side: const BorderSide(color: danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    );
  }

  Widget _buildApplicantCard(Map<String, dynamic> app) {
    final user = Map<String, dynamic>.from(app['user'] as Map? ?? <String, dynamic>{});
    final job = Map<String, dynamic>.from(app['job'] as Map? ?? <String, dynamic>{});
    final fullName = _buildOwnerName(user);
    final status = (app['status'] ?? 'pending').toString();
    final pending = status == 'pending';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatarOrInitial(user['avatar_url'], fullName, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 17,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Başvuru: ${_safeText(job['title'], fallback: 'İlan')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _statusBadge(status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showApplicantDetail(app),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Detay'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: info,
                    side: BorderSide(color: info.withOpacity(0.65)),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              if (pending) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 50,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => _updateApplicationStatus((app['id'] ?? '').toString(), 'accepted'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryGreen,
                      side: BorderSide(color: primaryGreen.withOpacity(0.65)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Icon(Icons.check_rounded, size: 22),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 50,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => _updateApplicationStatus((app['id'] ?? '').toString(), 'rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: danger,
                      side: BorderSide(color: danger.withOpacity(0.65)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Icon(Icons.close_rounded, size: 22),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyApplicationCard(Map<String, dynamic> app) {
    final job = Map<String, dynamic>.from(app['job'] as Map? ?? <String, dynamic>{});
    final status = (app['status'] ?? 'pending').toString();
    final statusInfo = _statusInfo(status);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 18, offset: Offset(0, 7)),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                _companyLogo(job, size: 50),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _safeText(job['title'], fallback: 'Bilinmeyen İlan'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _safeText(job['company_name'], fallback: 'Bilinmeyen Şirket'),
                        style: const TextStyle(
                          color: primaryGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _statusBadge(status),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: borderColor),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            color: surfaceHover,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _myAppMeta(
                        icon: Icons.location_on_rounded,
                        label: 'Konum',
                        value: _safeText(job['location'], fallback: '—'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _myAppMeta(
                        icon: Icons.work_rounded,
                        label: 'Çalışma',
                        value: _safeText(
                          job['job_type_label'],
                          fallback: _jobTypeLabel((job['job_type'] ?? '').toString()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _myAppMeta(
                        icon: Icons.payments_rounded,
                        label: 'Maaş',
                        value: _safeText(job['salary_range'], fallback: 'Belirtilmemiş'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _myAppMeta(
                        icon: Icons.schedule_rounded,
                        label: 'Son Başvuru',
                        value: _formatNullableDate(job['deadline']),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              children: [
                Row(
                  children: List.generate(3, (index) {
                    final done = index < statusInfo.steps;
                    return Expanded(
                      child: Container(
                        height: 5,
                        margin: EdgeInsets.only(right: index == 2 ? 0 : 5),
                        decoration: BoxDecoration(
                          color: done ? statusInfo.color : borderColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Başvuruldu',
                      style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                    const Text(
                      'İnceleniyor',
                      style: TextStyle(color: textMuted, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      statusInfo.shortLabel,
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatDateTime(app['created_at']),
                    style: const TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

  Widget _sectionHeader(String title, {String? actionLabel, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(actionLabel),
            style: TextButton.styleFrom(foregroundColor: primaryGreen),
          ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      height: 142,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: textDark,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: Center(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: 10.5,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 32, 26, 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFFEAFBF3),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.inbox_rounded, color: primaryGreen, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textDark,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      decoration: const BoxDecoration(
        color: cardBg,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryGreen, size: 16),
              const SizedBox(width: 7),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  color: primaryGreen,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: primaryGreen, size: 14),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: textDark,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contactBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primaryGreen.withOpacity(0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: primaryGreen, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(
                    color: textDark,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _myAppMeta({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Icon(icon, color: primaryGreen, size: 16),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: textMuted, fontSize: 10)),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: textDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _companyLogo(Map<String, dynamic> job, {double size = 50, bool dark = false}) {
    final company = _safeText(job['company_name'], fallback: 'Ş');
    final letter = company.isEmpty ? 'Ş' : company.substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: dark
            ? LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.20),
                  Colors.white.withOpacity(0.10),
                ],
              )
            : const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: dark ? Colors.white24 : const Color(0xFFD0F2E2),
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: dark ? Colors.white : primaryGreen,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _avatarOrInitial(Object? image, String name, {double size = 44}) {
    final url = (image ?? '').toString().trim();

    if (url.startsWith('http')) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialCircle(name, size: size),
        ),
      );
    }

    return _initialCircle(name, size: size);
  }

  Widget _initialCircle(String name, {double size = 44}) {
    final initial = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: primaryGreen,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.40,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _typeBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEAFBF3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD0F2E2)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: primaryGreen,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _metaPill(IconData icon, String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFFEAFBF3) : surfaceHover,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent ? const Color(0xFFD0F2E2) : borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent ? primaryGreen : textMuted),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: accent ? primaryGreen : textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallMeta(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: surfaceHover,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textMuted, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.82), size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.86),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final info = _statusInfo(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: info.color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            info.label,
            style: TextStyle(
              color: info.color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        fixedSize: const Size(40, 40),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? danger : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String _safeText(Object? value, {String fallback = ''}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _buildOwnerName(Map<String, dynamic> user) {
    final full = '${user['ad'] ?? ''} ${user['soyad'] ?? ''}'.trim();
    return full.isEmpty ? 'Kullanıcı' : full;
  }

  String _mapRoleLabel(String value) {
    switch (value.toLowerCase().trim()) {
      case 'ciftci':
      case 'çiftçi':
        return 'Çiftçi';
      case 'doktor':
        return 'Veteriner';
      case 'user':
        return 'Normal Kullanıcı';
      default:
        return 'Kullanıcı';
    }
  }

  List<String> _normalizeSkills(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return <String>[];

    if (text.startsWith('[') && text.endsWith(']')) {
      final cleaned = text
          .replaceAll('[', '')
          .replaceAll(']', '')
          .replaceAll('"', '')
          .replaceAll("'", '');
      return cleaned.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }

    return text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  DateTime? _parseDate(Object? value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _formatDate(Object? value) {
    DateTime? date;
    if (value is DateTime) {
      date = value;
    } else {
      date = DateTime.tryParse((value ?? '').toString());
    }

    if (date == null) return '—';

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  String _formatDateTime(Object? value) {
    DateTime? date;
    if (value is DateTime) {
      date = value;
    } else {
      date = DateTime.tryParse((value ?? '').toString());
    }

    if (date == null) return '—';

    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_formatDate(date)} $hour:$minute';
  }

  String _formatNullableDate(Object? value) {
    if (value == null) return 'Belirtilmemiş';
    return _formatDate(value);
  }

  String _jobTypeLabel(String value) {
    switch (value.toLowerCase().trim()) {
      case 'fulltime':
        return 'Tam Zamanlı';
      case 'parttime':
        return 'Yarı Zamanlı';
      case 'seasonal':
        return 'Mevsimlik';
      case 'intern':
        return 'Staj';
      default:
        return value.trim().isEmpty ? 'İş' : value;
    }
  }

  _StatusInfo _statusInfo(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
        return const _StatusInfo(
          label: 'Kabul Edildi',
          shortLabel: 'Sonuç',
          color: Color(0xFF22C55E),
          steps: 3,
        );
      case 'rejected':
        return const _StatusInfo(
          label: 'Reddedildi',
          shortLabel: 'Sonuç',
          color: danger,
          steps: 3,
        );
      default:
        return const _StatusInfo(
          label: 'Değerlendiriliyor',
          shortLabel: 'Sonuç',
          color: warning,
          steps: 1,
        );
    }
  }
}

class _JobFormScreen extends StatefulWidget {
  final SupabaseClient client;
  final String userId;
  final Map<String, dynamic>? initialJob;

  const _JobFormScreen({
    required this.client,
    required this.userId,
    this.initialJob,
  });

  @override
  State<_JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<_JobFormScreen> {
  static const Color primaryGreen = _JobsScreenState.primaryGreen;
  static const Color pageBg = _JobsScreenState.pageBg;
  static const Color cardBg = _JobsScreenState.cardBg;
  static const Color textDark = _JobsScreenState.textDark;
  static const Color textMuted = _JobsScreenState.textMuted;
  static const Color borderColor = _JobsScreenState.borderColor;
  static const Color danger = _JobsScreenState.danger;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _companyController;
  late final TextEditingController _locationController;
  late final TextEditingController _salaryController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _skillsController;
  late final TextEditingController _instructionsController;

  bool _isSaving = false;
  String _selectedType = 'fulltime';
  DateTime? _deadline;

  bool get _isEdit => widget.initialJob != null;

  @override
  void initState() {
    super.initState();
    final job = widget.initialJob;

    _titleController = TextEditingController(text: (job?['title'] ?? '').toString());
    _companyController = TextEditingController(text: (job?['company_name'] ?? '').toString());
    _locationController = TextEditingController(text: (job?['location'] ?? '').toString());
    _salaryController = TextEditingController(text: (job?['salary_range'] ?? '').toString());
    _descriptionController = TextEditingController(text: (job?['description'] ?? '').toString());
    _skillsController = TextEditingController(
      text: ((job?['skills'] as List<String>?) ?? const <String>[]).join(', '),
    );
    _instructionsController = TextEditingController(
      text: (job?['instructions'] ?? job?['contact_info'] ?? '').toString(),
    );

    final type = (job?['job_type'] ?? 'fulltime').toString();
    _selectedType = ['fulltime', 'parttime', 'seasonal'].contains(type) ? type : 'fulltime';

    final deadline = job?['deadline'];
    _deadline = deadline is DateTime ? deadline : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
    _locationController.dispose();
    _salaryController.dispose();
    _descriptionController.dispose();
    _skillsController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline != null && !_deadline!.isBefore(today) ? _deadline! : today,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryGreen,
              onPrimary: Colors.white,
              onSurface: textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _deadline = picked);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    if (_deadline == null) {
      _snack('Lütfen son başvuru tarihi seçin.', isError: true);
      return;
    }

    if (widget.userId.isEmpty) {
      _snack('Kullanıcı oturumu bulunamadı.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    final skills = _skillsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final payload = <String, dynamic>{
      'user_id': widget.userId,
      'title': _titleController.text.trim(),
      'company_name': _companyController.text.trim(),
      'job_type': _selectedType,
      'location': _locationController.text.trim(),
      'salary_range': _emptyToNull(_salaryController.text),
      'description': _descriptionController.text.trim(),
      'deadline': _toIsoDate(_deadline!),
      'skills': skills,
      'instructions': _emptyToNull(_instructionsController.text),
    };

    try {
      try {
        payload['contact_info'] = _emptyToNull(_instructionsController.text);

        if (_isEdit) {
          await widget.client
              .from('jobs')
              .update(payload)
              .eq('id', widget.initialJob!['id'])
              .eq('user_id', widget.userId);
        } else {
          await widget.client.from('jobs').insert(payload);
        }
      } catch (_) {
        payload.remove('contact_info');

        if (_isEdit) {
          await widget.client
              .from('jobs')
              .update(payload)
              .eq('id', widget.initialJob!['id'])
              .eq('user_id', widget.userId);
        } else {
          await widget.client.from('jobs').insert(payload);
        }
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _snack('İlan kaydedilemedi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? _required(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Bu alan zorunludur';
    return null;
  }

  String? _emptyToNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String _toIsoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? danger : primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cardBg,
      labelStyle: const TextStyle(color: textMuted, fontWeight: FontWeight.w700),
      hintStyle: const TextStyle(color: Colors.black38),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: primaryGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: danger),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_isSaving,
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: cardBg,
          elevation: 0,
          surfaceTintColor: cardBg,
          foregroundColor: textDark,
          title: Text(_isEdit ? 'İlanı Düzenle' : 'Yeni İş İlanı'),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              children: [
                const Text(
                  'İlan Bilgileri',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  validator: _required,
                  decoration: _inputDecoration(
                    label: 'Pozisyon Unvanı',
                    hint: 'Örn: Ziraat Mühendisi',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _companyController,
                  validator: _required,
                  decoration: _inputDecoration(
                    label: 'Şirket / Çiftlik Adı',
                    hint: 'Örn: Tarım A.Ş.',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: _inputDecoration(label: 'Çalışma Tipi'),
                  borderRadius: BorderRadius.circular(16),
                  items: const [
                    DropdownMenuItem(value: 'fulltime', child: Text('Tam Zamanlı')),
                    DropdownMenuItem(value: 'parttime', child: Text('Yarı Zamanlı')),
                    DropdownMenuItem(value: 'seasonal', child: Text('Mevsimlik')),
                  ],
                  onChanged: _isSaving ? null : (value) => setState(() => _selectedType = value!),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _isSaving ? null : _pickDeadline,
                  borderRadius: BorderRadius.circular(17),
                  child: InputDecorator(
                    decoration: _inputDecoration(
                      label: 'Son Başvuru Tarihi',
                      hint: 'Tarih seçiniz',
                      suffixIcon: const Icon(Icons.calendar_month_rounded),
                    ),
                    child: Text(
                      _deadline == null ? 'Tarih seçiniz' : _formatDate(_deadline!),
                      style: TextStyle(
                        color: _deadline == null ? Colors.black45 : textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationController,
                  validator: _required,
                  decoration: _inputDecoration(
                    label: 'Konum',
                    hint: 'Örn: Tekirdağ',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _salaryController,
                  decoration: _inputDecoration(
                    label: 'Maaş',
                    hint: 'Örn: 20.000 TL',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Açıklama ve Başvuru',
                  style: TextStyle(
                    color: textDark,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _skillsController,
                  maxLines: 2,
                  decoration: _inputDecoration(
                    label: 'İstenen Yetenekler',
                    hint: 'Örn: Traktör Ehliyeti, İlaçlama',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  validator: _required,
                  maxLines: 5,
                  decoration: _inputDecoration(
                    label: 'İş Açıklaması',
                    hint: 'İşin detaylarını açıklayın...',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instructionsController,
                  maxLines: 3,
                  decoration: _inputDecoration(
                    label: 'İletişim & Başvuru Talimatları',
                    hint: 'Nasıl başvurulacağını belirtin...',
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(_isSaving ? 'Kaydediliyor...' : 'İlanı Yayınla'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterOption {
  final String key;
  final String label;

  const _FilterOption({required this.key, required this.label});
}

class _TabInfo {
  final _JobsTab tab;
  final String label;
  final IconData icon;

  const _TabInfo({
    required this.tab,
    required this.label,
    required this.icon,
  });
}

class _StatusInfo {
  final String label;
  final String shortLabel;
  final Color color;
  final int steps;

  const _StatusInfo({
    required this.label,
    required this.shortLabel,
    required this.color,
    required this.steps,
  });
}
