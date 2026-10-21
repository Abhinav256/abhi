import 'package:flutter/material.dart';

import '../services/api_service.dart';

class ProvideRatingScreen extends StatefulWidget {
  final String? rideId;
  final Map<String, dynamic>? pendingData;

  const ProvideRatingScreen({
    super.key,
    this.rideId,
    this.pendingData,
  });

  @override
  State<ProvideRatingScreen> createState() => _ProvideRatingScreenState();
}

class _ProvideRatingScreenState extends State<ProvideRatingScreen> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  String? _rideId;
  String? _fromLocation;
  String? _toLocation;
  String? _journeyDate;
  bool _isDriver = false;

  List<Map<String, dynamic>> _participants = [];
  final Map<String, int> _ratings = {};
  final Map<String, TextEditingController> _feedbackControllers = {};

  static const Color _navy = Color(0xFF0B1B4D);
  static const Color _blue = Color(0xFF0B5FD1);
  static const Color _gold = Color(0xFFFFB800);
  static const Color _bg = Color(0xFFF6F8FC);
  static const Color _border = Color(0xFFDDE3EE);

  @override
  void initState() {
    super.initState();
    if (widget.pendingData != null) {
      _loadFromPending(widget.pendingData!);
    } else if (widget.rideId != null) {
      _loadParticipants(widget.rideId!);
    } else {
      _fetchPending();
    }
  }

  @override
  void dispose() {
    for (final controller in _feedbackControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _loadFromPending(Map<String, dynamic> data) {
    _rideId = data['ride_id']?.toString();
    _fromLocation = data['from_location']?.toString() ?? 'Origin';
    _toLocation = data['to_location']?.toString() ?? 'Destination';
    _journeyDate = data['journey_date']?.toString();
    _isDriver = data['is_driver'] == true;

    final rawList = data['participants'] as List<dynamic>? ?? [];
    _participants = rawList
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    _initControllers();
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchPending() async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getPendingRating();
      if (!mounted) return;
      if (data['has_pending_rating'] == true) {
        _loadFromPending(data);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No pending ratings found.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load rating details: $e';
      });
    }
  }

  Future<void> _loadParticipants(String rideId) async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getRideRatingParticipants(rideId: rideId);
      if (!mounted) return;
      _loadFromPending(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load participants: $e';
      });
    }
  }

  void _initControllers() {
    for (final p in _participants) {
      final id = p['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        // Default rating to 5 stars for a quick delightful experience
        _ratings[id] = 5;
        _feedbackControllers[id] = TextEditingController();
      }
    }
  }

  String _ratingLabel(int stars) {
    switch (stars) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent!';
      default:
        return '';
    }
  }

  Future<void> _submit() async {
    if (_rideId == null || _participants.isEmpty) return;

    // Check that every unrated participant has received a rating
    for (final p in _participants) {
      final id = p['id']?.toString() ?? '';
      final rating = _ratings[id] ?? 0;
      if (rating < 1) {
        final name = p['full_name'] ?? 'everyone';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please select a star rating for $name')),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final payload = _participants.map((p) {
        final id = p['id']?.toString() ?? '';
        return {
          'ratee_id': id,
          'rating_value': _ratings[id] ?? 5,
          'feedback': _feedbackControllers[id]?.text.trim() ?? '',
        };
      }).toList();

      await _apiService.submitRatings(
        rideId: _rideId!,
        ratings: payload,
      );

      if (!mounted) return;

      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(
      //     content: Text('Thank you! Your ratings have been submitted.'),
      //     backgroundColor: Colors.green,
      //   ),
      // );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit ratings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isDriver ? 'Rate Passengers' : 'Rate Your Trip',
          style: const TextStyle(
            color: _navy,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: _navy),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: _participants.isNotEmpty && !_isLoading
          ? _buildBottomBar()
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 54, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: _navy),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (_participants.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'All caught up!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _navy),
              ),
              const SizedBox(height: 8),
              const Text(
                'No pending ratings for this trip.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    }

    final driverParticipants = _participants.where((p) => p['role'] == 'driver').toList();
    final passengerParticipants = _participants.where((p) => p['role'] == 'passenger').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        _buildTripSummaryCard(),
        const SizedBox(height: 20),

        if (driverParticipants.isNotEmpty) ...[
          _buildSectionHeader('Driver Rating', 'Rate the person who drove the vehicle'),
          const SizedBox(height: 10),
          ...driverParticipants.map((p) => _buildRatingCard(p, isDriverCard: true)),
          const SizedBox(height: 24),
        ],

        if (passengerParticipants.isNotEmpty) ...[
          _buildSectionHeader(
            _isDriver ? 'Passengers Rating' : 'Co-Passengers',
            _isDriver
                ? 'Rate the passengers who rode with you'
                : 'Rate your fellow travelers on this trip',
          ),
          const SizedBox(height: 10),
          ...passengerParticipants.map((p) => _buildRatingCard(p, isDriverCard: false)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _navy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTripSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.route, color: _blue, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fromLocation ?? "Origin"} → ${_toLocation ?? "Destination"}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _navy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _journeyDate != null ? 'Journey Date: $_journeyDate' : 'Ride Completed',
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
    );
  }

  Widget _buildRatingCard(Map<String, dynamic> participant, {required bool isDriverCard}) {
    final id = participant['id']?.toString() ?? '';
    final name = participant['full_name']?.toString() ?? (isDriverCard ? 'Driver' : 'Passenger');
    final role = isDriverCard ? 'Driver' : 'Passenger';
    final currentRating = _ratings[id] ?? 5;
    final controller = _feedbackControllers[id];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, Role badge
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: isDriverCard ? const Color(0xFFDCE9FB) : const Color(0xFFE6F4EA),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDriverCard ? _blue : Colors.green.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDriverCard
                            ? const Color(0xFFE8F1FE)
                            : const Color(0xFFE8F8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        role,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDriverCard ? _blue : Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Star label
              Text(
                _ratingLabel(currentRating),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _gold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 5-Star Input Widget
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starNumber = index + 1;
                final isSelected = starNumber <= currentRating;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _ratings[id] = starNumber;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedScale(
                      scale: isSelected ? 1.15 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isSelected ? _gold : Colors.grey.shade400,
                        size: 38,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 14),

          // Optional Feedback Input
          TextField(
            controller: controller,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Add an optional note (e.g. polite, on-time, friendly)...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              filled: true,
              fillColor: const Color(0xFFF9FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _blue, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(26),
            ),
            elevation: 2,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Submit Ratings',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
