import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/location_result.dart';
import '../services/location_search_service.dart';
import '../services/recent_locations_service.dart';

/// Shows the Rapido/Uber-style slide-up location search bottom sheet.
Future<LocationResult?> showLocationSearchSheet({
  required BuildContext context,
  required String title,
  required bool isPickup,
  String initialQuery = '',
}) {
  return showModalBottomSheet<LocationResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useSafeArea: true,
    builder: (context) => LocationSearchBottomSheet(
      title: title,
      isPickup: isPickup,
      initialQuery: initialQuery,
    ),
  );
}

class LocationSearchBottomSheet extends StatefulWidget {
  final String title;
  final bool isPickup;
  final String initialQuery;

  const LocationSearchBottomSheet({
    super.key,
    required this.title,
    required this.isPickup,
    this.initialQuery = '',
  });

  @override
  State<LocationSearchBottomSheet> createState() =>
      _LocationSearchBottomSheetState();
}

class _LocationSearchBottomSheetState extends State<LocationSearchBottomSheet> {
  final LocationSearchService _searchService = LocationSearchService();
  final RecentLocationsService _recentService = RecentLocationsService();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounceTimer;

  bool _isLoading = false;
  bool _isLocatingCurrent = false;
  String? _errorMessage;
  String? _currentLocError;
  LocationPermissionState? _currentLocErrorState;

  List<LocationResult> _suggestions = [];
  List<LocationResult> _recentLocations = [];

  // Theme colors
  static const Color _navy = Color(0xFF0E1E38);
  static const Color _brandBlue = Color(0xFF0066FF);
  static const Color _pickupGreen = Color(0xFF00B074);
  static const Color _dropRed = Color(0xFFF43F5E);
  static const Color _grey = Color(0xFF718096);
  static const Color _border = Color(0xFFE2EDFB);
  static const Color _bgSoft = Color(0xFFF8FAFD);

  @override
  void initState() {
    super.initState();
    _loadRecentLocations();

    if (widget.initialQuery.isNotEmpty) {
      _searchController.text = widget.initialQuery;
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialQuery.length,
      );
    }

    _searchController.addListener(_onSearchChanged);

    // Auto-focus the search field after initial build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecentLocations() async {
    final list = await _recentService.getRecentLocations();
    if (!mounted) return;
    setState(() {
      _recentLocations = list;
    });
  }

  void _onSearchChanged() {
    final text = _searchController.text.trim();

    _debounceTimer?.cancel();

    if (text.length < 3) {
      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _suggestions = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _executeSearch(text);
    });
  }

  Future<void> _executeSearch(String query) async {
    final queryId = _searchService.getNextQueryId();

    try {
      final results = await _searchService.searchPlaces(
        query,
        queryId: queryId,
      );
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = null;
        _suggestions = results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _suggestions = [];
      });
    }
  }

  Future<void> _onSelectLocation(LocationResult location) async {
    HapticFeedback.lightImpact();
    await _recentService.saveRecentLocation(location);
    if (!mounted) return;
    Navigator.of(context).pop(location);
  }

  Future<void> _handleUseCurrentLocation() async {
    if (_isLocatingCurrent) return;

    HapticFeedback.selectionClick();
    setState(() {
      _isLocatingCurrent = true;
      _currentLocError = null;
      _currentLocErrorState = null;
    });

    try {
      final loc = await _searchService.getCurrentLocation();
      if (!mounted) return;
      setState(() => _isLocatingCurrent = false);
      await _onSelectLocation(loc);
    } on LocationDetectionException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLocatingCurrent = false;
        _currentLocError = e.message;
        _currentLocErrorState = e.state;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLocatingCurrent = false;
        _currentLocError =
            'Unable to detect location: ${e.toString().replaceFirst("Exception: ", "")}';
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _suggestions = [];
      _errorMessage = null;
      _isLoading = false;
    });
    _focusNode.requestFocus();
  }

  void _useCustomEnteredText() {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    _onSelectLocation(LocationResult(name: text, formattedAddress: text));
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final query = _searchController.text.trim();
    final isSearching = query.length >= 3;

    final themePinColor = widget.isPickup ? _pickupGreen : _dropRed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: screenHeight * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),

          // Drag Handle Pill
          Center(
            child: Container(
              width: 44,
              height: 4.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2.25),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Header: Back/Close Button + Contextual Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Material(
                  color: const Color(0xFFEEF4FC),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: _navy,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  TextButton(
                    onPressed: _clearSearch,
                    style: TextButton.styleFrom(
                      foregroundColor: _brandBlue,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Prominent Search Input Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: _bgSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focusNode.hasFocus ? _brandBlue : _border,
                  width: _focusNode.hasFocus ? 1.8 : 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: Icon(
                      Icons.location_on_rounded,
                      color: themePinColor,
                      size: 22,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search for a place or address',
                        hintStyle: TextStyle(
                          color: _grey.withValues(alpha: 0.8),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.cancel, color: _grey, size: 20),
                      onPressed: _clearSearch,
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Divider
          const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),

          // Body: Current Location, Recent Searches, or Dynamic Suggestions
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(top: 8, bottom: viewInsetsBottom + 20),
              physics: const BouncingScrollPhysics(),
              children: [
                // "Use Current Location" Option
                _buildCurrentLocationTile(),

                // Error prompt for Current Location if needed
                if (_currentLocError != null)
                  _buildCurrentLocationErrorBanner(),

                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF1F5F9),
                ),

                // If user is searching (>= 3 chars)
                if (isSearching) ...[
                  if (_isLoading)
                    _buildSearchingIndicator()
                  else if (_errorMessage != null)
                    _buildErrorState()
                  else if (_suggestions.isEmpty)
                    _buildEmptySuggestionsState()
                  else
                    ..._suggestions.map(_buildSuggestionTile),
                ] else ...[
                  // If query < 3 chars, show Recent Locations
                  _buildRecentLocationsSection(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentLocationTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isLocatingCurrent ? null : _handleUseCurrentLocation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FC),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD6E6FB), width: 1),
                ),
                child: Center(
                  child: _isLocatingCurrent
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: _brandBlue,
                          ),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          color: _brandBlue,
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Use Current Location',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isLocatingCurrent
                          ? 'Acquiring GPS coordinates & resolving address...'
                          : 'Tap to locate your current spot with GPS',
                      style: const TextStyle(
                        fontSize: 13,
                        color: _grey,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentLocationErrorBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFDC2626),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentLocError ?? '',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                if (_currentLocErrorState ==
                    LocationPermissionState.serviceDisabled)
                  GestureDetector(
                    onTap: () => Geolocator.openLocationSettings(),
                    child: const Text(
                      'Open Location Settings →',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                  )
                else if (_currentLocErrorState ==
                    LocationPermissionState.permanentlyDenied)
                  GestureDetector(
                    onTap: () => Geolocator.openAppSettings(),
                    child: const Text(
                      'Open App Settings →',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
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

  Widget _buildSearchingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _brandBlue,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Searching locations across India...',
            style: TextStyle(
              fontSize: 14,
              color: _grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionTile(LocationResult loc) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onSelectLocation(loc),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.location_on_outlined,
                    color: _brandBlue,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.primaryText,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (loc.secondaryText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        loc.secondaryText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _grey,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySuggestionsState() {
    final query = _searchController.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.search_off_rounded, size: 28, color: _grey),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No places found for "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try searching for a different city, locality, or landmark.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _grey),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _useCustomEnteredText,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
            label: Text('Use "$query" as location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brandBlue,
              side: const BorderSide(color: _brandBlue),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 36,
            color: Color(0xFFDC2626),
          ),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Network error while searching places',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _navy,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _executeSearch(_searchController.text.trim()),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _useCustomEnteredText,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Use Entered Text'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentLocationsSection() {
    if (_recentLocations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFD),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.history_rounded,
                  color: Color(0xFF94A3B8),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No recent locations yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Search for any city, landmark, or street above\nto quickly select your ride stop.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, color: _grey, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Recent Locations',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _grey,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () async {
                  await _recentService.clearRecentLocations();
                  setState(() => _recentLocations = []);
                },
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _brandBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
        ..._recentLocations.map((loc) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _onSelectLocation(loc),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.schedule_rounded,
                          color: Color(0xFF64748B),
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.primaryText,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (loc.secondaryText.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              loc.secondaryText,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _grey,
                                height: 1.25,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.north_west_rounded,
                      size: 16,
                      color: Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
