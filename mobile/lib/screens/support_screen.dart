import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../widgets/app_bottom_nav_bar.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  static const Color _navy = Color(0xFF0B1B3B);
  static const Color _blue = Color(0xFF0B4FD8);
  static const Color _grey = Color(0xFF6B7280);
  static const Color _bg = Color(0xFFF6F9FF);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double w = math.min(media.size.width, 520);

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
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Page Heading
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Support',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'We are here to assist you with your journey',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 36),

                        // Prominent Support Card / Main Content Area
                        Center(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 40,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Support Icon Badge
                                Container(
                                  width: 92,
                                  height: 92,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFE8F1FD),
                                        Color(0xFFD3E5FD),
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.support_agent_rounded,
                                    size: 50,
                                    color: _blue,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Prominently displayed: "How can I help you?"
                                const Text(
                                  'How can I help you?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Our support team is always ready to assist you with your rides, bookings, and account.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _grey,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const AppBottomNavBar(currentTab: AppNavTab.support),
            ],
          ),
        ),
      ),
    );
  }
}
