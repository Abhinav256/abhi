import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';

class ReferAndEarnScreen extends StatefulWidget {
  const ReferAndEarnScreen({super.key});

  @override
  State<ReferAndEarnScreen> createState() => _ReferAndEarnScreenState();
}

class _ReferAndEarnScreenState extends State<ReferAndEarnScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _summary;

  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF0B4FD8);
  static const Color _green = Color(0xFF0E8A6A);
  static const Color _amber = Color(0xFFD97706);
  static const Color _purple = Color(0xFF673AB7);
  static const Color _bg = Color(0xFFF6F9FF);

  @override
  void initState() {
    super.initState();
    _loadReferralData();
  }

  Future<void> _loadReferralData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _apiService.getReferralSummary();
      if (!mounted) return;
      setState(() {
        _summary = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showShareDialog(String code, String link) {
    final shareMessage =
        'Join me on AbhiShare! Use my referral code $code to register, complete your first ride as driver, and we both get rewarded! Download: $link';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Share Referral Invite',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  shareMessage,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _navy,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _copyToClipboard(code, 'Referral code copied!');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy Code'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _copyToClipboard(shareMessage, 'Invitation message copied to clipboard!');
                      },
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Copy Invite'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Refer & Earn',
          style: TextStyle(
            color: _navy,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _navy),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _navy),
            onPressed: _loadReferralData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _navy, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadReferralData,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _summary ?? {};
    final referralCode = summary['referral_code']?.toString() ?? '------';
    final referralLink = summary['referral_link']?.toString() ?? 'https://abhishare.app/ref/$referralCode';
    final isEligible = summary['is_eligible'] == true;
    final eligibilityReason = summary['eligibility_reason']?.toString() ?? '';
    final completedRides = summary['completed_rides_as_driver'] as int? ?? 0;
    final dailyUsed = summary['daily_referrals_used'] as int? ?? 0;
    final dailyLimit = summary['daily_referrals_limit'] as int? ?? 5;
    final dailyRemaining = summary['daily_referrals_remaining'] as int? ?? (dailyLimit - dailyUsed);
    final totalSuccessful = summary['total_successful_referrals'] as int? ?? 0;
    final totalEarned = (summary['total_rewards_earned'] as num?)?.toDouble() ?? 0.0;
    final referralsList = (summary['referrals'] as List<dynamic>?) ?? [];

    return RefreshIndicator(
      onRefresh: _loadReferralData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero Banner ──────────────────────────────────────────
            _buildHeroBanner(),
            const SizedBox(height: 16),

            // ── Eligibility Status Card ──────────────────────────────
            _buildEligibilityCard(isEligible, completedRides, eligibilityReason),
            const SizedBox(height: 16),

            // ── Referral Code & Link Card ────────────────────────────
            _buildCodeAndLinkCard(referralCode, referralLink, isEligible),
            const SizedBox(height: 16),

            // ── Daily Usage & Stats Card ─────────────────────────────
            _buildDailyLimitAndStatsCard(
              dailyUsed: dailyUsed,
              dailyLimit: dailyLimit,
              dailyRemaining: dailyRemaining,
              totalSuccessful: totalSuccessful,
              totalEarned: totalEarned,
            ),
            const SizedBox(height: 16),

            // ── How It Works ─────────────────────────────────────────
            _buildHowItWorksCard(),
            const SizedBox(height: 20),

            // ── Referral History List ────────────────────────────────
            _buildReferralHistorySection(referralsList),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A40C4), Color(0xFF1B6BF3), Color(0xFF5B3DE6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B4FD8),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'REWARD PROGRAM',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Refer & Earn ₹50',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Earn ₹50 directly in your AbhiShare Wallet for each friend who completes their first ride as a driver!',
                  style: TextStyle(
                    color: Color(0xFFE0E7FF),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(45),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.card_giftcard_rounded,
              size: 38,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEligibilityCard(bool isEligible, int completedRides, String reason) {
    if (isEligible) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _green.withAlpha(50), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _green.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: _green, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Referral Privileges Active',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'You have completed $completedRides ride(s) as driver. All referral rewards will credit to your wallet.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _amber.withAlpha(80), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _amber.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded, color: _amber, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Referral Privileges Locked',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            reason.isNotEmpty
                ? reason
                : 'To refer friends and earn rewards, you must first create, publish, and complete at least 1 ride as driver.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF78350F),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (completedRides / 1.0).clamp(0.0, 1.0),
            backgroundColor: Colors.amber.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(_amber),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 6),
          Text(
            'Driver Rides Completed: $completedRides / 1 required',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF92400E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeAndLinkCard(String code, String link, bool isEligible) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Unique Referral Code',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.5,
                    color: _navy,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _copyToClipboard(code, 'Referral code copied!'),
                  icon: const Icon(Icons.copy_rounded, size: 18, color: _blue),
                  label: const Text(
                    'Copy',
                    style: TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _copyToClipboard(link, 'Referral link copied!'),
                  icon: const Icon(Icons.link_rounded, size: 18, color: _navy),
                  label: const Text(
                    'Copy Link',
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _showShareDialog(code, link),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text(
                    'Share Invite',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDailyLimitAndStatsCard({
    required int dailyUsed,
    required int dailyLimit,
    required int dailyRemaining,
    required int totalSuccessful,
    required double totalEarned,
  }) {
    final progress = (dailyUsed / dailyLimit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Daily limit progress
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Today\'s Referral Limit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _navy,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: dailyRemaining > 0 ? _green.withAlpha(25) : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  dailyRemaining > 0
                      ? '$dailyRemaining left today'
                      : 'Limit reached',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: dailyRemaining > 0 ? _green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                dailyRemaining > 0 ? _blue : Colors.red,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$dailyUsed of $dailyLimit referrals used today (IST)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Text(
                'Max 5 / day',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 28, thickness: 1, color: Color(0xFFF1F5F9)),

          // Overall statistics
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.people_alt_rounded,
                  color: _purple,
                  title: 'Successful',
                  value: '$totalSuccessful',
                  subtitle: 'Friends rewarded',
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: const Color(0xFFE2E8F0),
              ),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.account_balance_wallet_rounded,
                  color: _green,
                  title: 'Total Earned',
                  value: '₹${totalEarned.toStringAsFixed(0)}',
                  subtitle: 'Credited to wallet',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _blue, size: 20),
              SizedBox(width: 8),
              Text(
                'How It Works',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStepRow(
            stepNumber: '1',
            title: 'Share your referral code',
            description: 'Send your code or link to friends (maximum 5 referrals per calendar day).',
          ),
          _buildStepRow(
            stepNumber: '2',
            title: 'Friend signs up',
            description: 'Your friend registers on AbhiShare using your unique referral code.',
          ),
          _buildStepRow(
            stepNumber: '3',
            title: 'Complete a ride as driver',
            description: 'Both you and your friend create, publish, and successfully complete at least 1 ride as the ride driver.',
          ),
          _buildStepRow(
            stepNumber: '4',
            title: 'Instant ₹50 wallet credit',
            description: 'Once both driver ride conditions are met, ₹50 is atomically credited to your AbhiShare wallet.',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required String stepNumber,
    required String title,
    required String description,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  stepNumber,
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReferralHistorySection(List<dynamic> referrals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Referral History',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            Text(
              '${referrals.length} Total',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (referrals.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.group_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  const Text(
                    'No referrals yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Invite friends to join AbhiShare and complete driver rides to earn rewards.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: referrals.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, index) {
              final ref = referrals[index] as Map<String, dynamic>;
              return _buildReferralItemCard(ref);
            },
          ),
      ],
    );
  }

  Widget _buildReferralItemCard(Map<String, dynamic> ref) {
    final name = ref['referee_name']?.toString() ?? 'Friend';
    final phone = ref['referee_phone']?.toString() ?? '';
    final status = ref['status']?.toString() ?? 'registered';
    final statusDisplay = ref['status_display']?.toString() ?? 'Registered';
    final rewardAmount = (ref['reward_amount'] as num?)?.toDouble() ?? 50.0;
    final referrerRideCompleted = ref['referrer_ride_completed'] == true;
    final refereeRideCompleted = ref['referee_ride_completed'] == true;
    final createdAtStr = ref['created_at']?.toString() ?? '';

    Color badgeBg;
    Color badgeText;
    IconData badgeIcon;

    switch (status) {
      case 'reward_credited':
        badgeBg = const Color(0xFFDCFCE7);
        badgeText = const Color(0xFF166534);
        badgeIcon = Icons.check_circle_rounded;
        break;
      case 'eligible':
        badgeBg = const Color(0xFFF3E8FF);
        badgeText = const Color(0xFF6B21A8);
        badgeIcon = Icons.stars_rounded;
        break;
      case 'ride_pending':
        badgeBg = const Color(0xFFFEF3C7);
        badgeText = const Color(0xFF92400E);
        badgeIcon = Icons.pending_rounded;
        break;
      case 'registered':
      default:
        badgeBg = const Color(0xFFE0F2FE);
        badgeText = const Color(0xFF0369A1);
        badgeIcon = Icons.person_add_rounded;
        break;
    }

    String formattedDate = '';
    if (createdAtStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAtStr).toLocal();
        formattedDate = '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        formattedDate = createdAtStr;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFFE2E8F0),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 14, color: badgeText),
                    const SizedBox(width: 4),
                    Text(
                      statusDisplay,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        refereeRideCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        size: 15,
                        color: refereeRideCompleted ? _green : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Friend Driver Ride: ${refereeRideCompleted ? "Completed" : "Pending"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: refereeRideCompleted ? _green : Colors.grey.shade700,
                          fontWeight: refereeRideCompleted ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        referrerRideCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        size: 15,
                        color: referrerRideCompleted ? _green : Colors.grey.shade400,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your Driver Ride: ${referrerRideCompleted ? "Completed" : "Pending"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: referrerRideCompleted ? _green : Colors.grey.shade700,
                          fontWeight: referrerRideCompleted ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status == 'reward_credited'
                        ? '+₹${rewardAmount.toStringAsFixed(0)}'
                        : '₹${rewardAmount.toStringAsFixed(0)} Reward',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: status == 'reward_credited' ? _green : _blue,
                    ),
                  ),
                  if (formattedDate.isNotEmpty)
                    Text(
                      formattedDate,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
