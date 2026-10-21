import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/notification_state.dart';
import '../widgets/swipe_to_confirm.dart';
import 'ride_payment_screen.dart';

/// Design tokens for the Book Ride screen (AbhiShare theme).
class _T {
  static const blue = Color(0xFF1260D6);
  static const green = Color(0xFF159B72);
  static const red = Color(0xFFE53935);
  static const bg = Color(0xFFF5F8FF);
  static const navy = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFD5E0F2);
  static const tint = Color(0xFFEAF2FF);
  static const pink = Color(0xFFD81B60);
  static const pinkBg = Color(0xFFFCE4EC);
  static const pinkBorder = Color(0xFFF48FB1);

  static List<BoxShadow> get shadow => [
    BoxShadow(
      color: blue.withOpacity(0.08),
      blurRadius: 14,
      offset: const Offset(0, 5),
    ),
  ];
}

class _PassengerFormFieldState {
  final TextEditingController nameController;
  final TextEditingController ageController;
  String gender;

  _PassengerFormFieldState({
    String initialName = '',
    String initialAge = '',
    this.gender = 'male',
  }) : nameController = TextEditingController(text: initialName),
       ageController = TextEditingController(text: initialAge);

  void dispose() {
    nameController.dispose();
    ageController.dispose();
  }
}

class BookRideScreen extends StatefulWidget {
  final Map<String, dynamic> ride;

  const BookRideScreen({super.key, required this.ride});

  @override
  State<BookRideScreen> createState() => _BookRideScreenState();
}

class _BookRideScreenState extends State<BookRideScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();

  bool get _isWomenOnly => widget.ride['is_women_only'] == true;

  int _availableSeats = 1;
  int _selectedSeats = 1;
  double _pricePerSeat = 0.0;
  String _paymentMode = 'upi';

  final List<_PassengerFormFieldState> _passengers = [];

  bool _isLoading = false;
  bool _isLoadingUser = true;
  String? _currentUserGender;

  @override
  void initState() {
    super.initState();
    final bool isMatched = widget.ride['is_route_matched'] == true;
    final segSeats = widget.ride['available_segment_seats'];
    final rawSeats = (isMatched && segSeats != null)
        ? segSeats
        : widget.ride['available_seats'];
    _availableSeats = int.tryParse(rawSeats?.toString() ?? '1') ?? 1;
    if (_availableSeats < 1) _availableSeats = 1;

    final segPrice = double.tryParse(
      widget.ride['segment_price_per_seat']?.toString() ?? '',
    );
    final totalAmount = double.tryParse(
      widget.ride['total_amount']?.toString() ?? '',
    );
    final rawPrice = widget.ride['price_per_seat'];
    if (isMatched && segPrice != null && segPrice > 0) {
      _pricePerSeat = segPrice;
    } else if (totalAmount != null && totalAmount > 0) {
      _pricePerSeat = totalAmount;
    } else {
      _pricePerSeat = double.tryParse(rawPrice?.toString() ?? '0') ?? 0.0;
    }

    _passengers.add(
      _PassengerFormFieldState(gender: _isWomenOnly ? 'female' : 'male'),
    );
    _prefillUserData();
  }

  @override
  void dispose() {
    for (final p in _passengers) {
      p.dispose();
    }
    super.dispose();
  }

  // ───────────────────────── Business logic (unchanged) ─────────────────────────

  void _updatePassengerCount(int newCount) {
    if (newCount == _selectedSeats) return;
    setState(() {
      if (newCount > _passengers.length) {
        for (int i = _passengers.length; i < newCount; i++) {
          _passengers.add(
            _PassengerFormFieldState(gender: _isWomenOnly ? 'female' : 'male'),
          );
        }
      } else if (newCount < _passengers.length) {
        while (_passengers.length > newCount) {
          final removed = _passengers.removeLast();
          removed.dispose();
        }
      }
      _selectedSeats = newCount;
    });
  }

  Future<void> _prefillUserData() async {
    try {
      final user = await _apiService.getCurrentUser();
      final rideId = widget.ride['id']?.toString();
      final userGender = user['gender']?.toString().toLowerCase();
      final bool isMatched = widget.ride['is_route_matched'] == true;

      int latestAvailable = _availableSeats;
      if (rideId != null && rideId.isNotEmpty) {
        try {
          final rideDetail = await _apiService.getRideDetail(rideId: rideId);
          if (!isMatched) {
            latestAvailable =
                int.tryParse(
                  rideDetail['available_seats']?.toString() ??
                      '$_availableSeats',
                ) ??
                _availableSeats;
            final detailTotal = double.tryParse(
              rideDetail['total_amount']?.toString() ?? '',
            );
            if (detailTotal != null && detailTotal > 0) {
              _pricePerSeat = detailTotal;
            } else {
              final latestPrice = double.tryParse(
                rideDetail['price_per_seat']?.toString() ?? '$_pricePerSeat',
              );
              if (latestPrice != null) _pricePerSeat = latestPrice;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _currentUserGender = userGender;

        if (latestAvailable > 0) {
          _availableSeats = latestAvailable;
          if (_selectedSeats > _availableSeats) {
            _updatePassengerCount(_availableSeats);
          }
        }
        if (_passengers.isNotEmpty) {
          if (_isWomenOnly && userGender != 'female') {
            // A male account is booking for a female passenger.
            // Do NOT prefill Passenger 1 with the male booker's name.
            _passengers[0].nameController.text = '';
            _passengers[0].gender = 'female';
          } else {
            _passengers[0].nameController.text =
                user['full_name']?.toString() ?? '';
            if (_isWomenOnly) {
              _passengers[0].gender = 'female';
            } else {
              _passengers[0].gender = userGender ?? 'male';
            }
          }
        }
        _isLoadingUser = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingUser = false;
      });
    }
  }

  Future<void> _bookRide() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final rideId = widget.ride['id']?.toString();
      if (rideId == null || rideId.isEmpty) {
        throw Exception('Ride ID is missing.');
      }

      // 1. Fetch latest ride availability from backend as source of truth
      final latestRide = await _apiService.getRideDetail(rideId: rideId);
      final latestAvailable =
          int.tryParse(latestRide['available_seats']?.toString() ?? '0') ?? 0;

      if (latestAvailable < _selectedSeats) {
        setState(() {
          _availableSeats = latestAvailable > 0 ? latestAvailable : 1;
          _isLoading = false;
        });

        if (latestAvailable <= 0) {
          throw Exception('No seats available for this ride anymore.');
        } else {
          throw Exception(
            'Only $latestAvailable seat(s) currently available. Please adjust your seat count.',
          );
        }
      }

      // 2. Prepare dynamic passenger details
      final passengerPayload = _passengers
          .map(
            (p) => {
              'name': p.nameController.text.trim(),
              'age': int.parse(p.ageController.text.trim()),
              'gender': p.gender,
            },
          )
          .toList();

      // 3. UPI Flow: Navigate to dedicated RidePaymentScreen with dynamic amount
      if (_paymentMode == 'upi') {
        if (!mounted) return;
        final totalPayable = _pricePerSeat * _selectedSeats;
        final booked = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => RidePaymentScreen(
              ride: widget.ride,
              seatsBooked: _selectedSeats,
              pricePerSeat: _pricePerSeat,
              totalAmount: totalPayable,
              passengers: passengerPayload,
              apiService: _apiService,
            ),
          ),
        );

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        if (booked == true) {
          Navigator.of(context).pop(true);
        }
        return;
      }

      // 4. Cash Flow: Preserve existing cash-booking flow directly with route segment.
      final r = widget.ride;
      await _apiService.createBooking(
        rideId: rideId,
        seatsBooked: _selectedSeats,
        paymentMode: _paymentMode,
        passengers: passengerPayload,
        fromLocation:
            r['passenger_pickup_name']?.toString() ??
            r['from_location']?.toString(),
        toLocation:
            r['passenger_drop_name']?.toString() ??
            r['to_location']?.toString(),
        pickupLatitude: double.tryParse(r['pickup_latitude']?.toString() ?? ''),
        pickupLongitude: double.tryParse(
          r['pickup_longitude']?.toString() ?? '',
        ),
        destinationLatitude: double.tryParse(
          r['destination_latitude']?.toString() ?? '',
        ),
        destinationLongitude: double.tryParse(
          r['destination_longitude']?.toString() ?? '',
        ),
        pickupDistanceAlongRoute: double.tryParse(
          r['pickup_distance_along_route']?.toString() ?? '',
        ),
        dropDistanceAlongRoute: double.tryParse(
          r['drop_distance_along_route']?.toString() ?? '',
        ),
      );

      NotificationState.instance.refresh();

      if (!mounted) return;

      await _showSuccessDialog();

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Booking failed: ${e.toString().replaceFirst("Exception: ", "")}',
          ),
        ),
      );
    }
  }

  Future<void> _showSuccessDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.0),
          ),
          elevation: 8,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24.0),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24.0),
                  ),
                  child: SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: CustomPaint(painter: _WavePainter()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x3310B981),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 24),
                      RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Inter',
                          ),
                          children: [
                            TextSpan(
                              text: 'Booking ',
                              style: TextStyle(color: Color(0xFF0F172A)),
                            ),
                            TextSpan(
                              text: 'Confirmed!',
                              style: TextStyle(color: Color(0xFF0057FF)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF4B5563),
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Inter',
                          ),
                          children: [
                            const TextSpan(text: 'Your '),
                            TextSpan(
                              text: _selectedSeats == 1
                                  ? '1 seat'
                                  : '$_selectedSeats seats',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF374151),
                              ),
                            ),
                            TextSpan(
                              text: _selectedSeats == 1
                                  ? ' has been booked\nsuccessfully!'
                                  : ' have been booked\nsuccessfully!',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0057FF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(27),
                            ),
                          ),
                          child: const Text(
                            'OK',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
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
      },
    );
  }

  // ───────────────────────────── UI helpers ─────────────────────────────

  InputDecoration _fieldDecoration(
    String label,
    IconData icon, {
    required double vPad,
    String? hint,
  }) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Icon(icon, size: 20, color: _T.navy),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: vPad),
      labelStyle: const TextStyle(color: _T.muted, fontSize: 14),
      hintStyle: TextStyle(color: _T.muted.withOpacity(0.6)),
      enabledBorder: b(_T.border),
      disabledBorder: b(_T.border),
      focusedBorder: b(_T.blue, 1.6),
      errorBorder: b(_T.red),
      focusedErrorBorder: b(_T.red, 1.6),
      errorStyle: const TextStyle(fontSize: 11, height: 1),
    );
  }

  Widget _sectionHeader(
    IconData icon,
    String title, {
    Widget? trailing,
    required double fs,
  }) {
    return Row(
      children: [
        Icon(icon, color: _T.blue, size: 22 * fs),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17 * fs,
              fontWeight: FontWeight.w700,
              color: _T.navy,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  String? get _vehicleLabel {
    final raw =
        widget.ride['vehicle_type'] ??
        widget.ride['vehicle_category'] ??
        widget.ride['ride_type'];
    final s = raw?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  Widget _buildHeader(double fs) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE6EDF8))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Material(
            color: _T.tint,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: Padding(
                padding: EdgeInsets.all(9 * fs),
                child: Icon(Icons.arrow_back, color: _T.blue, size: 22 * fs),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Book Ride',
            style: TextStyle(
              fontSize: 22 * fs,
              fontWeight: FontWeight.w800,
              color: _T.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJourneyCard(double fs, double s) {
    final bool isMatched = widget.ride['is_route_matched'] == true;
    final driverFrom = widget.ride['from_location']?.toString() ?? '-';
    final driverTo = widget.ride['to_location']?.toString() ?? '-';
    final from = (isMatched && widget.ride['passenger_pickup_name'] != null)
        ? widget.ride['passenger_pickup_name'].toString()
        : driverFrom;
    final to = (isMatched && widget.ride['passenger_drop_name'] != null)
        ? widget.ride['passenger_drop_name'].toString()
        : driverTo;
    final priceStr = _pricePerSeat.toStringAsFixed(0);
    final totalAmount = (_pricePerSeat * _selectedSeats).toStringAsFixed(0);
    final vehicle = _vehicleLabel;
    final isBike = (vehicle ?? '').toLowerCase().contains('bike');

    Widget stat(
      IconData icon,
      String label,
      String value,
      Color color, {
      CrossAxisAlignment align = CrossAxisAlignment.start,
    }) {
      return Expanded(
        child: Row(
          children: [
            Icon(icon, size: 20 * fs, color: _T.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12 * fs, color: _T.muted),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 20 * fs,
                        fontWeight: FontWeight.w800,
                        color: color,
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

    Widget vDivider() => Container(
      width: 1,
      height: 34 * s,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: _T.border,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(16, 14 * s, 16, 12 * s),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xFFEFF5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1EAF8)),
        boxShadow: _T.shadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Route indicator
                Column(
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16C060),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: _T.border,
                      ),
                    ),
                    Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        from,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17 * fs,
                          fontWeight: FontWeight.w700,
                          color: _T.navy,
                        ),
                      ),
                      SizedBox(height: 10 * s),
                      Text(
                        to,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17 * fs,
                          fontWeight: FontWeight.w700,
                          color: _T.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                if (vehicle != null) ...[
                  const SizedBox(width: 8),
                  Align(
                    alignment: Alignment.topRight,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 120 * fs),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _T.tint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isBike ? Icons.two_wheeler : Icons.directions_car,
                              size: 14 * fs,
                              color: _T.blue,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                vehicle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12 * fs,
                                  fontWeight: FontWeight.w700,
                                  color: _T.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isMatched) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF93C5FD)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.alt_route_rounded,
                    size: 14,
                    color: Color(0xFF1D4ED8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Segment along driver\'s route ($driverFrom → $driverTo)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11 * fs,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.only(top: 10 * s),
            child: Row(
              children: [
                stat(Icons.sell, 'Price per seat', '₹$priceStr', _T.blue),
                vDivider(),
                stat(Icons.event_seat, 'Seats', '$_selectedSeats', _T.navy),
                vDivider(),
                stat(
                  Icons.account_balance_wallet,
                  'Total Amount',
                  '₹$totalAmount',
                  _T.green,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeatSelector(double fs, double s, double vPad) {
    final value = _selectedSeats > _availableSeats
        ? _availableSeats
        : _selectedSeats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          Icons.event_seat,
          'Select Number of Seats',
          fs: fs,
          trailing: Text(
            '$_availableSeats available',
            style: TextStyle(
              fontSize: 13 * fs,
              color: _T.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(height: 8 * s),
        DropdownButtonFormField<int>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _T.navy),
          borderRadius: BorderRadius.circular(14),
          decoration: _fieldDecoration(
            '',
            Icons.airline_seat_recline_normal,
            vPad: vPad,
          ).copyWith(labelText: null),
          style: TextStyle(
            fontSize: 16 * fs,
            color: _T.navy,
            fontWeight: FontWeight.w500,
          ),
          items: List.generate(_availableSeats, (index) => index + 1).map((
            seatCount,
          ) {
            return DropdownMenuItem<int>(
              value: seatCount,
              child: Text(
                '$seatCount seat${seatCount > 1 ? 's' : ''} (₹${(_pricePerSeat * seatCount).toStringAsFixed(0)})',
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) _updatePassengerCount(v);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 4),
          child: Text(
            'Max $_availableSeats seats available on this ride',
            style: TextStyle(fontSize: 12 * fs, color: _T.muted),
          ),
        ),
      ],
    );
  }

  Widget _buildWomenOnlyBanner(double fs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _T.pinkBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.pinkBorder, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: _T.pink,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.female, color: Colors.white, size: 18 * fs),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Women Only Ride',
                  style: TextStyle(
                    color: _T.pink,
                    fontWeight: FontWeight.bold,
                    fontSize: 14 * fs,
                  ),
                ),
                Text(
                  'This ride is reserved exclusively for women passengers.',
                  style: TextStyle(
                    color: Colors.pink.shade900,
                    fontSize: 12 * fs,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPassengerCard(int i, double fs, double s, double vPad) {
    final p = _passengers[i];
    final accent = _isWomenOnly ? _T.pink : _T.blue;
    final title = i == 0
        ? (_isWomenOnly && _currentUserGender != 'female'
              ? 'Passenger 1 (Travelling Passenger)'
              : 'Passenger 1 (Primary / You)')
        : 'Passenger ${i + 1}';

    final nameField = TextFormField(
      controller: p.nameController,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      style: TextStyle(fontSize: 16 * fs, color: _T.navy),
      decoration: _fieldDecoration(
        'Passenger ${i + 1} Name',
        Icons.person_outline,
        vPad: vPad,
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter passenger ${i + 1} name';
        }
        return null;
      },
    );

    final ageField = TextFormField(
      controller: p.ageController,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      style: TextStyle(fontSize: 16 * fs, color: _T.navy),
      decoration: _fieldDecoration(
        'Passenger ${i + 1} Age',
        Icons.cake_outlined,
        vPad: vPad,
        hint: 'Enter age',
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter age for passenger ${i + 1}';
        }
        final age = int.tryParse(value.trim());
        if (age == null || age < 18) {
          return 'Passenger ${i + 1} must be at least 18';
        }
        return null;
      },
    );

    final genderField = DropdownButtonFormField<String>(
      value: _isWomenOnly ? 'female' : p.gender,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _T.navy),
      borderRadius: BorderRadius.circular(14),
      style: TextStyle(fontSize: 16 * fs, color: _T.navy),
      decoration: _fieldDecoration(
        'Passenger ${i + 1} Gender',
        Icons.wc,
        vPad: vPad,
      ),
      items: _isWomenOnly
          ? const [
              DropdownMenuItem(
                value: 'female',
                child: Text('Female (Required)'),
              ),
            ]
          : const [
              DropdownMenuItem(value: 'male', child: Text('Male')),
              DropdownMenuItem(value: 'female', child: Text('Female')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
      onChanged: _isWomenOnly
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                p.gender = value;
              });
            },
    );

    return Container(
      margin: EdgeInsets.only(bottom: 10 * s),
      padding: EdgeInsets.fromLTRB(14, 12 * s, 14, 14 * s),
      decoration: BoxDecoration(
        color: _isWomenOnly ? const Color(0xFFFFF8FB) : const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isWomenOnly ? _T.pinkBorder : const Color(0xFFE1EAF8),
        ),
        boxShadow: _T.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13 * fs,
                backgroundColor: accent,
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 12 * fs,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16 * fs,
                    fontWeight: FontWeight.w700,
                    color: _T.navy,
                  ),
                ),
              ),
              if (_isWomenOnly)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _T.pinkBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _T.pinkBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.female, size: 14, color: _T.pink),
                      const SizedBox(width: 2),
                      Text(
                        'Female',
                        style: TextStyle(
                          color: _T.pink,
                          fontWeight: FontWeight.bold,
                          fontSize: 11 * fs,
                        ),
                      ),
                    ],
                  ),
                )
              else if (i == 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _T.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Primary',
                    style: TextStyle(
                      color: _T.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 12 * fs,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 12 * s),
          nameField,
          SizedBox(height: 10 * s),
          ageField,
          SizedBox(height: 10 * s),
          genderField,
        ],
      ),
    );
  }

  Widget _buildPaymentSelector(double fs, double s) {
    const options = <String, List<dynamic>>{
      'upi': ['UPI', 'Pay using any UPI app', Icons.credit_card],
      'cash': ['Cash', 'Pay the driver in cash', Icons.payments_outlined],
    };

    Widget tile(String key) {
      final o = options[key]!;
      return Row(
        children: [
          Icon(o[2] as IconData, color: _T.blue, size: 26 * fs),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  o[0] as String,
                  style: TextStyle(
                    fontSize: 16 * fs,
                    color: _T.navy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  o[1] as String,
                  style: TextStyle(fontSize: 12 * fs, color: _T.muted),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.credit_card, 'Payment Mode', fs: fs),
        SizedBox(height: 8 * s),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _T.blue, width: 1.4),
            boxShadow: _T.shadow,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _paymentMode,
              isExpanded: true,
              itemHeight: null,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _T.navy,
              ),
              selectedItemBuilder: (_) => options.keys
                  .map(
                    (k) => Padding(
                      padding: EdgeInsets.symmetric(vertical: 8 * s),
                      child: tile(k),
                    ),
                  )
                  .toList(),
              items: options.keys
                  .map(
                    (k) => DropdownMenuItem<String>(
                      value: k,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: tile(k),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _paymentMode = value;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // Viewport-driven scale factors (reference design ≈ 392 x 820 dp).
    final fs = (mq.size.width / 392).clamp(0.85, 1.15).toDouble();
    final s = (mq.size.height / 820).clamp(0.75, 1.15).toDouble();
    final vPad = 13.0 * s;
    final hPad = (mq.size.width * 0.046).clamp(14.0, 22.0).toDouble();
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final totalAmount = (_pricePerSeat * _selectedSeats).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: _T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(fs),
            Expanded(
              child: _isLoadingUser
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.fromLTRB(
                                hPad,
                                12 * s,
                                hPad,
                                12 * s,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildJourneyCard(fs, s),
                                  SizedBox(height: 14 * s),
                                  _buildSeatSelector(fs, s, vPad),
                                  SizedBox(height: 14 * s),
                                  if (_isWomenOnly) ...[
                                    _buildWomenOnlyBanner(fs),
                                    SizedBox(height: 12 * s),
                                  ],
                                  _sectionHeader(
                                    Icons.groups_2,
                                    'Passenger Details ($_selectedSeats)',
                                    fs: fs,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      bottom: 10,
                                    ),
                                    child: Text(
                                      'Enter required details for all passengers.',
                                      style: TextStyle(
                                        fontSize: 13 * fs,
                                        color: _T.muted,
                                      ),
                                    ),
                                  ),
                                  for (int i = 0; i < _selectedSeats; i++)
                                    _buildPassengerCard(i, fs, s, vPad),
                                  SizedBox(height: 4 * s),
                                  _buildPaymentSelector(fs, s),
                                ],
                              ),
                            ),
                          ),
                          // Pinned action area – never overlaps scrolling content.
                          if (!keyboardOpen)
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: _T.bg,
                                boxShadow: [
                                  BoxShadow(
                                    color: _T.blue.withOpacity(0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, -4),
                                  ),
                                ],
                              ),
                              padding: EdgeInsets.fromLTRB(
                                hPad,
                                10 * s,
                                hPad,
                                (mq.padding.bottom > 0
                                        ? mq.padding.bottom
                                        : 0) +
                                    10 * s,
                              ),
                              child: SwipeToConfirm(
                                text: _paymentMode == 'upi'
                                    ? 'Swipe to Pay & Confirm (₹$totalAmount)'
                                    : 'Swipe to Confirm (₹$totalAmount)',
                                isLoading: _isLoading,
                                onConfirm: _bookRide,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE0F2FE).withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.lineTo(0, size.height * 0.5);
    path1.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.7,
      size.width * 0.5,
      size.height * 0.5,
    );
    path1.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.5,
    );
    path1.lineTo(size.width, 0);
    path1.close();

    canvas.drawPath(path1, paint);

    final paint2 = Paint()
      ..color = const Color(0xFFF0F9FF).withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.lineTo(0, size.height * 0.6);
    path2.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.8,
      size.width * 0.6,
      size.height * 0.4,
    );
    path2.quadraticBezierTo(
      size.width * 0.8,
      size.height * 0.2,
      size.width,
      size.height * 0.3,
    );
    path2.lineTo(size.width, 0);
    path2.close();

    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
