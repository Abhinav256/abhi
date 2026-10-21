import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/route_option.dart';
import '../services/api_service.dart';
import 'location_search_bottom_sheet.dart';

class RouteSelectorMap extends StatefulWidget {
  final List<RouteOption> routes;
  final RouteOption selectedRoute;
  final ValueChanged<RouteOption> onRouteSelected;
  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final String fromName;
  final String toName;
  final void Function(RouteWaypoint waypoint)? onCustomWaypointAdded;

  const RouteSelectorMap({
    super.key,
    required this.routes,
    required this.selectedRoute,
    required this.onRouteSelected,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.fromName,
    required this.toName,
    this.onCustomWaypointAdded,
  });

  @override
  State<RouteSelectorMap> createState() => _RouteSelectorMapState();
}

class _RouteSelectorMapState extends State<RouteSelectorMap> {
  bool _showAllWaypoints = false;
  final ScrollController _settlementsScrollController = ScrollController();

  @override
  void dispose() {
    _settlementsScrollController.dispose();
    super.dispose();
  }

  String get _staticMapUrl {
    return '${ApiService.baseUrl}/locations/route-map?from_lat=${widget.fromLat}&from_lon=${widget.fromLon}&to_lat=${widget.toLat}&to_lon=${widget.toLon}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── MAP VIEW CARD ───────────────────────────────────────────────────
        Container(
          height: 220,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD5DCE8), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 1. Static Map Real-World Tiles
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: _staticMapUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: const Color(0xFFF1F6FE),
                    child: const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: const Color(0xFFEBF3FF),
                    child: const Center(
                      child: Icon(
                        Icons.map_rounded,
                        size: 40,
                        color: Color(0xFF0B5FD1),
                      ),
                    ),
                  ),
                ),
              ),

              // 2. Custom Polyline Painter Overlay for all routes and selected route
              Positioned.fill(
                child: CustomPaint(
                  painter: _RouteOverlayPainter(
                    routes: widget.routes,
                    selectedRoute: widget.selectedRoute,
                    fromLat: widget.fromLat,
                    fromLon: widget.fromLon,
                    toLat: widget.toLat,
                    toLon: widget.toLon,
                  ),
                ),
              ),

              // 3. Top Floating Route Summary Badge
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0B5FD1,
                          ).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.alt_route_rounded,
                          size: 16,
                          color: Color(0xFF0B5FD1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.selectedRoute.summary,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B1B4D),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F1FE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${widget.selectedRoute.distanceKm} km',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B5FD1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Bottom Origin -> Destination Pins Legend
              Positioned(
                bottom: 8,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              size: 8,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.fromName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white70,
                          size: 12,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 11,
                              color: Color(0xFFE5484D),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                widget.toName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── ROUTE OPTIONS SECTION HEADER ────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Select Driving Route',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B1B4D),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F1FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${widget.routes.length} options',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B5FD1),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // ── ROUTE COMPARISON CARDS ──────────────────────────────────────────
        ...widget.routes.map((route) {
          final isSelected = route.id == widget.selectedRoute.id;
          return _buildRouteOptionCard(route, isSelected);
        }),

        // ── INTERMEDIATE TOWNS & SETTLEMENTS ────────────────────────────────
        const SizedBox(height: 12),
        _buildIntermediatePointsSection(),
      ],
    );
  }

  Widget _buildRouteOptionCard(RouteOption route, bool isSelected) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onRouteSelected(route);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF3F8FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF0B5FD1)
                : const Color(0xFFDDE3EE),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF0B5FD1).withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Radio indicator
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF0B5FD1)
                          : const Color(0xFF9EABB9),
                      width: 2,
                    ),
                    color: isSelected
                        ? const Color(0xFF0B5FD1)
                        : Colors.transparent,
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(
                            Icons.check,
                            size: 13,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),

                // Route title & badge
                Expanded(
                  child: Text(
                    route.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFF0B5FD1)
                          : const Color(0xFF0B1B4D),
                    ),
                  ),
                ),

                // Toll info tag
                if (route.hasTolls)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFFFB74D),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.toll_rounded,
                          size: 12,
                          color: Color(0xFFE65100),
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Toll Road',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF80CBC4),
                        width: 0.8,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 12,
                          color: Color(0xFF00796B),
                        ),
                        SizedBox(width: 3),
                        Text(
                          'Toll-Free',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF00796B),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Summary (road names)
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                route.summary,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Metrics row: Duration & Distance
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Row(
                children: [
                  _buildMetricChip(
                    icon: Icons.access_time_filled_rounded,
                    label: route.durationFormatted,
                    color: const Color(0xFF0B1B4D),
                  ),
                  const SizedBox(width: 12),
                  _buildMetricChip(
                    icon: Icons.straighten_rounded,
                    label: '${route.distanceKm} km',
                    color: const Color(0xFF4B5563),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _addCustomIntermediateStop() async {
    final result = await showLocationSearchSheet(
      context: context,
      title: 'Add Intermediate Stop',
      isPickup: false,
    );

    if (result == null || result.latitude == null || result.longitude == null) {
      return;
    }

    final lat = result.latitude!;
    final lon = result.longitude!;
    final name = result.primaryText;

    // Project onto route coordinates to compute distanceAlongRoute
    double distAlong = 0.0;
    final coords = widget.selectedRoute.coordinates;
    if (coords.length >= 2) {
      double minPerp = double.infinity;
      double cumulative = 0.0;
      double bestCumulative = 0.0;

      for (int i = 0; i < coords.length - 1; i++) {
        final x1 = coords[i][0];
        final y1 = coords[i][1];
        final x2 = coords[i + 1][0];
        final y2 = coords[i + 1][1];

        final segLen = _haversineMeters(y1, x1, y2, x2);
        if (segLen > 0) {
          final t = (((lon - x1) * (x2 - x1)) + ((lat - y1) * (y2 - y1))) /
              (((x2 - x1) * (x2 - x1)) + ((y2 - y1) * (y2 - y1)));
          final clampedT = t.clamp(0.0, 1.0);
          final projLon = x1 + clampedT * (x2 - x1);
          final projLat = y1 + clampedT * (y2 - y1);
          final perp = _haversineMeters(lat, lon, projLat, projLon);
          if (perp < minPerp) {
            minPerp = perp;
            bestCumulative = cumulative + (clampedT * segLen);
          }
        }
        cumulative += segLen;
      }
      distAlong = bestCumulative;
    }

    final newWaypoint = RouteWaypoint(
      name: name,
      category: 'stop',
      latitude: lat,
      longitude: lon,
      distanceAlongRouteMeters: distAlong,
    );

    final updatedPoints = List<RouteWaypoint>.from(
      widget.selectedRoute.intermediatePoints,
    );
    updatedPoints.add(newWaypoint);
    updatedPoints.sort(
      (a, b) => a.distanceAlongRouteMeters.compareTo(b.distanceAlongRouteMeters),
    );

    final updatedRoute = widget.selectedRoute.copyWith(
      intermediatePoints: updatedPoints,
    );
    widget.onRouteSelected(updatedRoute);
    widget.onCustomWaypointAdded?.call(newWaypoint);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "$name" as an intermediate stop'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Widget _buildCategoryBadge(String rawCategory) {
    final cat = rawCategory.toLowerCase();
    String label = 'Place';
    Color bgColor = const Color(0xFFF1F5F9);
    Color textColor = const Color(0xFF475569);

    if (cat == 'city') {
      label = 'City';
      bgColor = const Color(0xFFE8F1FE);
      textColor = const Color(0xFF0B5FD1);
    } else if (cat == 'town') {
      label = 'Town';
      bgColor = const Color(0xFFEFF6FF);
      textColor = const Color(0xFF1D4ED8);
    } else if (cat == 'village') {
      label = 'Village';
      bgColor = const Color(0xFFECFDF5);
      textColor = const Color(0xFF047857);
    } else if (cat == 'hamlet') {
      label = 'Hamlet';
      bgColor = const Color(0xFFF3F4F6);
      textColor = const Color(0xFF6B7280);
    } else if (cat == 'stop') {
      label = 'Custom Stop';
      bgColor = const Color(0xFFF5F3FF);
      textColor = const Color(0xFF7C3AED);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildIntermediatePointsSection() {
    final points = widget.selectedRoute.intermediatePoints;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE3EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B5FD1).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_city_rounded,
                  size: 15,
                  color: Color(0xFF0B5FD1),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Intermediate Towns & Villages',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B1B4D),
                      ),
                    ),
                    Text(
                      'Discovered settlements in travel order',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (points.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${points.length} found',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B5FD1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (points.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No settlements auto-detected along this stretch.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _addCustomIntermediateStop,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF0B5FD1)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 14, color: Color(0xFF0B5FD1)),
                          SizedBox(width: 4),
                          Text(
                            'Add Stop',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0B5FD1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (!_showAllWaypoints) ...[
            // Compact view: show top 6 chips with travel order
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...points.take(6).toList().asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final pt = entry.value;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$idx. ',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0B5FD1),
                          ),
                        ),
                        Text(
                          pt.name,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (pt.category.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          _buildCategoryBadge(pt.category),
                        ],
                        if (pt.distanceAlongRouteMeters > 0) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${(pt.distanceAlongRouteMeters / 1000).toStringAsFixed(0)}km',
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
                // Add Stop Action Chip
                InkWell(
                  onTap: _addCustomIntermediateStop,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_location_alt_outlined, size: 12, color: Color(0xFF7C3AED)),
                        SizedBox(width: 4),
                        Text(
                          'Add Stop',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (points.length > 6) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _showAllWaypoints = true;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View all ${points.length} towns & villages',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B5FD1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: Color(0xFF0B5FD1),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            // Expanded full scrollable list without page overflow
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Scrollbar(
                controller: _settlementsScrollController,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _settlementsScrollController,
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: points.length,
                  separatorBuilder: (context, i) => const Divider(
                    height: 8,
                    thickness: 0.6,
                    color: Color(0xFFE2E8F0),
                  ),
                  itemBuilder: (context, i) {
                    final pt = points[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F1FE),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF93C5FD)),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B5FD1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pt.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (pt.category.isNotEmpty) ...[
                            _buildCategoryBadge(pt.category),
                            const SizedBox(width: 6),
                          ],
                          if (pt.distanceAlongRouteMeters > 0)
                            Text(
                              '${(pt.distanceAlongRouteMeters / 1000).toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                InkWell(
                  onTap: _addCustomIntermediateStop,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_location_alt_outlined, size: 14, color: Color(0xFF7C3AED)),
                        SizedBox(width: 4),
                        Text(
                          'Add missing stop',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _showAllWaypoints = false;
                    });
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Show Less',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0B5FD1),
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: 16,
                        color: Color(0xFF0B5FD1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom painter to draw polylines for routes over the static map
class _RouteOverlayPainter extends CustomPainter {
  final List<RouteOption> routes;
  final RouteOption selectedRoute;
  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;

  _RouteOverlayPainter({
    required this.routes,
    required this.selectedRoute,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (routes.isEmpty) return;

    // Determine bounding box across all route coordinates to map lat/lon to canvas x/y
    double minLat = math.min(fromLat, toLat);
    double maxLat = math.max(fromLat, toLat);
    double minLon = math.min(fromLon, toLon);
    double maxLon = math.max(fromLon, toLon);

    for (final r in routes) {
      for (final pt in r.coordinates) {
        final lon = pt[0];
        final lat = pt[1];
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lon < minLon) minLon = lon;
        if (lon > maxLon) maxLon = lon;
      }
    }

    // Add 12% padding to bounds
    final latPadding = (maxLat - minLat) * 0.12;
    final lonPadding = (maxLon - minLon) * 0.12;
    minLat -= latPadding;
    maxLat += latPadding;
    minLon -= lonPadding;
    maxLon += lonPadding;

    final latSpan = maxLat - minLat > 0 ? maxLat - minLat : 0.01;
    final lonSpan = maxLon - minLon > 0 ? maxLon - minLon : 0.01;

    Offset toCanvasPoint(double lat, double lon) {
      final x = ((lon - minLon) / lonSpan) * size.width;
      // Invert Y because canvas Y increases downwards
      final y = size.height - (((lat - minLat) / latSpan) * size.height);
      return Offset(x, y);
    }

    // 1. Draw unselected alternative routes in light gray
    final altPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.6)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final r in routes) {
      if (r.id == selectedRoute.id) continue;
      if (r.coordinates.length < 2) continue;

      final path = Path();
      final p0 = toCanvasPoint(r.coordinates[0][1], r.coordinates[0][0]);
      path.moveTo(p0.dx, p0.dy);
      for (int i = 1; i < r.coordinates.length; i++) {
        final p = toCanvasPoint(r.coordinates[i][1], r.coordinates[i][0]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, altPaint);
    }

    // 2. Draw selected route with glowing shadow and bold blue stroke
    if (selectedRoute.coordinates.length >= 2) {
      final shadowPaint = Paint()
        ..color = const Color(0xFF0B5FD1).withValues(alpha: 0.25)
        ..strokeWidth = 8.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final selectedPaint = Paint()
        ..color = const Color(0xFF0B5FD1)
        ..strokeWidth = 4.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final selPath = Path();
      final p0 = toCanvasPoint(
        selectedRoute.coordinates[0][1],
        selectedRoute.coordinates[0][0],
      );
      selPath.moveTo(p0.dx, p0.dy);
      for (int i = 1; i < selectedRoute.coordinates.length; i++) {
        final p = toCanvasPoint(
          selectedRoute.coordinates[i][1],
          selectedRoute.coordinates[i][0],
        );
        selPath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(selPath, shadowPaint);
      canvas.drawPath(selPath, selectedPaint);
    }

    // 3. Draw intermediate waypoint dots for the selected route
    final townPaint = Paint()
      ..color = const Color(0xFFFFB300)
      ..style = PaintingStyle.fill;
    final townBorder = Paint()
      ..color = const Color(0xFF0B5FD1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final wpPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final wpBorder = Paint()
      ..color = const Color(0xFF0B5FD1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final customStopPaint = Paint()
      ..color = const Color(0xFF7C3AED)
      ..style = PaintingStyle.fill;

    // Up to 15 intermediate settlement markers drawn evenly along route
    final allPoints = selectedRoute.intermediatePoints;
    final pointsToDraw = allPoints.length > 15
        ? _sampleEvenly(allPoints, 15)
        : allPoints;

    for (final wp in pointsToDraw) {
      final pt = toCanvasPoint(wp.latitude, wp.longitude);
      final cat = wp.category.toLowerCase();
      if (cat == 'stop') {
        canvas.drawCircle(pt, 5.0, customStopPaint);
        canvas.drawCircle(pt, 5.0, wpBorder);
      } else if (cat == 'city' || cat == 'town') {
        canvas.drawCircle(pt, 5.0, townPaint);
        canvas.drawCircle(pt, 5.0, townBorder);
      } else {
        canvas.drawCircle(pt, 3.8, wpPaint);
        canvas.drawCircle(pt, 3.8, wpBorder);
      }
    }

    // 4. Draw Origin Pin (Green) and Destination Pin (Red)
    final fromPt = toCanvasPoint(fromLat, fromLon);
    final toPt = toCanvasPoint(toLat, toLon);

    _drawPin(canvas, fromPt, const Color(0xFF10B981), 'A');
    _drawPin(canvas, toPt, const Color(0xFFE5484D), 'B');
  }

  void _drawPin(Canvas canvas, Offset pt, Color color, String label) {
    // Outer white glow
    final glow = Paint()..color = Colors.white;
    canvas.drawCircle(pt, 9.0, glow);

    // Colored pin circle
    final pin = Paint()..color = color;
    canvas.drawCircle(pt, 7.5, pin);

    // Letter label
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(pt.dx - (textPainter.width / 2), pt.dy - (textPainter.height / 2)),
    );
  }

  List<RouteWaypoint> _sampleEvenly(List<RouteWaypoint> list, int count) {
    if (list.length <= count) return list;
    final result = <RouteWaypoint>[];
    final step = list.length / count;
    for (int i = 0; i < count; i++) {
      final idx = (i * step).floor().clamp(0, list.length - 1);
      result.add(list[idx]);
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _RouteOverlayPainter oldDelegate) {
    return oldDelegate.selectedRoute.id != selectedRoute.id ||
        oldDelegate.routes.length != routes.length;
  }
}
