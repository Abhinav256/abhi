import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import 'login_screen.dart';
import 'vehicles_screen.dart';
import 'saved_locations_screen.dart';
import 'safety_and_privacy_screen.dart';
import 'recurring_schedules_screen.dart';
import 'wallet_screen.dart';
import 'refer_and_earn_screen.dart';
import '../widgets/app_bottom_nav_bar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _blue = Color(0xFF0B6FE0);
  static const Color _navy = Color(0xFF0F1B4D);
  static const Color _bg = Color(0xFFF3F7FD);

  final ApiService _apiService = ApiService();
  final NotificationState _notifState = NotificationState.instance;

  Map<String, dynamic>? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _notifState.refresh();
    _notifState.addListener(_onNotifChanged);
  }

  @override
  void dispose() {
    _notifState.removeListener(_onNotifChanged);
    super.dispose();
  }

  void _onNotifChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _apiService.getCurrentUser();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _apiService.logout();
      _notifState.clearUnread();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign out failed: $e')),
      );
    }
  }

  void _openVehicles() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VehiclesScreen()),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }

  String _formatGender(String? gender) {
    if (gender == null) return '-';
    switch (gender) {
      case 'male':
        return 'Male';
      case 'female':
        return 'Female';
      case 'other':
        return 'Other';
      default:
        return gender;
    }
  }

  IconData _genderIcon(String? gender) {
    switch (gender) {
      case 'male':
        return Icons.male;
      case 'female':
        return Icons.female;
      default:
        return Icons.person_outline;
    }
  }

  Future<void> _editProfile() async {
    if (_user == null) return;
    
    final fullNameController = TextEditingController(text: _user!['full_name']?.toString() ?? '');
    final nicknameController = TextEditingController(text: _user!['nickname']?.toString() ?? '');
    
    String rawDob = _user!['date_of_birth']?.toString() ?? '';
    String initialDob = rawDob.length >= 10 ? rawDob.substring(0, 10) : rawDob;
    if (initialDob.length == 10 && initialDob.contains('-')) {
      final p = initialDob.split('-');
      if (p.length == 3) initialDob = '${p[2]}/${p[1]}/${p[0]}';
    }
    final dobController = TextEditingController(text: initialDob);
    
    String selectedGender = _user!['gender']?.toString().toLowerCase() ?? 'other';
    if (!['male', 'female', 'other'].contains(selectedGender)) {
      selectedGender = 'other';
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Profile'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: dobController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Date of Birth (DD/MM/YYYY)',
                        suffixIcon: Icon(Icons.calendar_month_outlined, color: Colors.grey),
                      ),
                      onTap: () async {
                        final now = DateTime.now();
                        DateTime initialDate = DateTime(now.year - 18, now.month, now.day);
                        final dobText = dobController.text.trim();
                        if (dobText.length == 10 && dobText.contains('/')) {
                          final p = dobText.split('/');
                          if (p.length == 3) {
                            final parsed = DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
                            if (parsed != null) initialDate = parsed;
                          }
                        }
                        
                        DateTime tempDate = initialDate;
                        await showModalBottomSheet(
                          context: context,
                          backgroundColor: Colors.white,
                          builder: (BuildContext builder) {
                            return SizedBox(
                              height: 300,
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          dobController.text = '${tempDate.day.toString().padLeft(2, '0')}/${tempDate.month.toString().padLeft(2, '0')}/${tempDate.year}';
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                  Expanded(
                                    child: CupertinoDatePicker(
                                      mode: CupertinoDatePickerMode.date,
                                      initialDateTime: initialDate,
                                      minimumDate: DateTime(1900),
                                      maximumDate: now,
                                      onDateTimeChanged: (DateTime newDate) {
                                        tempDate = newDate;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nicknameController,
                      decoration: const InputDecoration(labelText: 'Nickname (Optional)'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: const InputDecoration(labelText: 'Gender'),
                      items: const [
                        DropdownMenuItem(value: 'male', child: Text('Male')),
                        DropdownMenuItem(value: 'female', child: Text('Female')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedGender = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    if (!mounted) return;
                    setState(() => _isLoading = true);
                    try {
                      String dobToSave = dobController.text.trim();
                      if (dobToSave.length == 10 && dobToSave.contains('/')) {
                        final p = dobToSave.split('/');
                        if (p.length == 3) dobToSave = '${p[2]}-${p[1]}-${p[0]}';
                      }
                      
                      await _apiService.updateProfile(
                        fullNameController.text.trim(),
                        nicknameController.text.trim().isEmpty ? null : nicknameController.text.trim(),
                        dobToSave,
                        selectedGender,
                      );
                      await _loadProfile();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
                      setState(() => _isLoading = false);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double w = math.min(media.size.width, 520);
    final double sc = w / 935;
    double f(double px) => px * sc * 1.1;

    return Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: SizedBox(
          width: w,
          child: Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _user == null
                          ? const Center(child: Text('Unable to load profile'))
                          : _buildProfileContent(),
                ),
              ),
              _buildBottomNav(sc, f, media.padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContent() {
    final fullName = _user?['full_name']?.toString() ?? '-';
    final nickname = _user?['nickname']?.toString() ?? '';
    final email = _user?['email']?.toString() ?? '-';
    final phone = _user?['phone']?.toString() ?? '-';
    final rawGender = _user?['gender']?.toString();
    final gender = _formatGender(rawGender);
    final dob = _user?['date_of_birth']?.toString() ?? '-';
    String displayDob = dob.length >= 10 ? dob.substring(0, 10) : dob;
    if (displayDob.length == 10 && displayDob.contains('-')) {
      final p = displayDob.split('-');
      if (p.length == 3) displayDob = '${p[2]}/${p[1]}/${p[0]}';
    }

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      TextSpan(text: 'My ', style: TextStyle(color: Colors.black)),
                      TextSpan(text: 'Profile', style: TextStyle(color: _blue)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage your account & preferences',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Profile summary card
          _SectionCard(
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFFDCE9FB),
                      child: Text(
                        fullName.isNotEmpty && fullName != '-'
                            ? fullName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: _blue,
                        ),
                      ),
                    ),
                    
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      if (nickname.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '($nickname)',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            _genderIcon(rawGender),
                            size: 18,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            gender,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade700,
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

          const SizedBox(height: 14),

          // My Rating Card
          _buildMyRatingCard(),

          const SizedBox(height: 14),

          // Edit profile button (placeholder for now)
          Material(
            color: _blue,
            borderRadius: BorderRadius.circular(30),
            elevation: 3,
            shadowColor: _blue.withAlpha(90),
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: _editProfile,
              child: const SizedBox(
                height: 54,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Spacer(),
                      Icon(Icons.edit, color: Colors.white, size: 22),
                      SizedBox(width: 12),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Spacer(),
                      Icon(Icons.chevron_right, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Personal details
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Personal Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 12),
                _DetailRow(icon: Icons.phone, label: 'Mobile', value: phone),
                const _RowDivider(indent: 56),
                _DetailRow(icon: Icons.email_outlined, label: 'Email', value: email),
                const _RowDivider(indent: 56),
                _DetailRow(
                  icon: Icons.calendar_today,
                  label: 'Date of Birth',
                  value: displayDob,
                ),
                const _RowDivider(indent: 56),
                _DetailRow(
                  icon: _genderIcon(rawGender),
                  label: 'Gender',
                  value: gender,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Account
          _SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 8),
                _AccountTile(
                  icon: Icons.account_balance_wallet_rounded,
                  color: _blue,
                  title: 'AbhiShare Wallet',
                  subtitle: 'Balance, add money & withdrawals',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WalletScreen()),
                    );
                  },
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.card_giftcard_rounded,
                  color: const Color(0xFFE91E63),
                  title: 'Refer & Earn ₹50',
                  subtitle: 'Invite friends & earn ₹50 in your wallet',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReferAndEarnScreen()),
                    );
                  },
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.directions_car,
                  color: _blue,
                  title: 'My Vehicles',
                  subtitle: 'Add and manage your vehicles',
                  onTap: _openVehicles,
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.repeat_rounded,
                  color: const Color(0xFF673AB7),
                  title: 'Recurring Schedules',
                  subtitle: 'Manage recurring ride series',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RecurringSchedulesScreen()),
                    );
                  },
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.location_on_outlined,
                  color: const Color(0xFF12B58A),
                  title: 'Saved Locations',
                  subtitle: 'Home, Work & more',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SavedLocationsScreen()),
                    );
                  },
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.shield_outlined,
                  color: const Color(0xFFFF9800),
                  title: 'Safety & Privacy',
                  subtitle: 'Manage your safety settings',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SafetyAndPrivacyScreen()),
                    );
                  },
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.star_border,
                  color: const Color(0xFFE91E8C),
                  title: 'Reviews & Ratings',
                  subtitle: 'See your reviews',
                  onTap: () => _comingSoon('Reviews & Ratings'),
                ),
                const _RowDivider(indent: 72),
                _AccountTile(
                  icon: Icons.settings_outlined,
                  color: const Color(0xFF5B3FE0),
                  title: 'App Settings',
                  subtitle: 'Notifications, language, and more',
                  onTap: () => _comingSoon('App Settings'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Sign out
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text(
                'Sign Out',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE5173F),
                backgroundColor: const Color(0xFFFDECF0),
                side: const BorderSide(color: Color(0xFFF3B5C3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyRatingCard() {
    final rawAvg = _user?['average_rating'];
    final totalRatings = int.tryParse(_user?['total_ratings']?.toString() ?? '0') ?? 0;
    final double? avgRating = rawAvg != null ? double.tryParse(rawAvg.toString()) : null;

    final hasRatings = totalRatings > 0 && avgRating != null && avgRating > 0;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'My Rating',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                ],
              ),
              if (hasRatings)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFE08A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '${avgRating.toStringAsFixed(1)} ★',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB47D00),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasRatings) ...[
            Row(
              children: [
                Text(
                  avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(5, (index) {
                          final starNum = index + 1;
                          final isFull = avgRating >= starNum;
                          final isHalf = !isFull && (avgRating >= starNum - 0.5);

                          return Icon(
                            isFull
                                ? Icons.star_rounded
                                : isHalf
                                    ? Icons.star_half_rounded
                                    : Icons.star_outline_rounded,
                            color: const Color(0xFFFFB800),
                            size: 24,
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Based on $totalRatings ${totalRatings == 1 ? "rating" : "ratings"}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.star_outline_rounded, color: Colors.grey.shade500, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No ratings yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Complete your first trip to receive 5-star ratings!',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Bottom Navigation
  // ------------------------------------------------------------------

  Widget _buildBottomNav(
    double sc,
    double Function(double) f,
    double bottomInset,
  ) {
    return const AppBottomNavBar(currentTab: AppNavTab.profile);
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RowDivider extends StatelessWidget {
  final double indent;

  const _RowDivider({required this.indent});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: indent,
      color: Colors.grey.shade200,
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFFE6F0FC),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF0B6FE0)),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0F1B4D),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AccountTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F1B4D),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// Alerts placeholder (notifications will be built later)
// =========================================================================

class _AlertsPlaceholderScreen extends StatelessWidget {
  const _AlertsPlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        title: const Text('Alerts'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF0B1B3B),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 64,
              color: Color(0xFF8A94A6),
            ),
            SizedBox(height: 12),
            Text(
              'No alerts yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B1B3B),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Notifications will appear here.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}