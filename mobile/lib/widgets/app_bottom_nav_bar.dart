import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/my_bookings_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/support_screen.dart';
import '../screens/wallet_screen.dart';

enum AppNavTab {
  home,
  rides,
  wallet,
  support,
  profile,
}

class AppBottomNavBar extends StatelessWidget {
  final AppNavTab? currentTab;
  final ValueChanged<AppNavTab>? onTabSelected;

  const AppBottomNavBar({
    super.key,
    required this.currentTab,
    this.onTabSelected,
  });

  static const Color _blue = Color(0xFF0B4FD8);
  static const Color _grey = Color(0xFF8A94A6);
  static const Color _activeBg = Color(0xFFE3EEFD);

  void _handleTabTap(BuildContext context, AppNavTab tab) {
    if (tab == currentTab) return;

    if (onTabSelected != null) {
      onTabSelected!(tab);
      return;
    }

    if (currentTab == AppNavTab.home) {
      Widget target;
      switch (tab) {
        case AppNavTab.rides:
          target = const MyBookingsScreen();
          break;
        case AppNavTab.wallet:
          target = const WalletScreen();
          break;
        case AppNavTab.support:
          target = const SupportScreen();
          break;
        case AppNavTab.profile:
          target = const ProfileScreen();
          break;
        case AppNavTab.home:
          return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => target),
      );
      return;
    }

    if (tab == AppNavTab.home) {
      if (Navigator.canPop(context)) {
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      return;
    }

    Widget target;
    switch (tab) {
      case AppNavTab.rides:
        target = const MyBookingsScreen();
        break;
      case AppNavTab.wallet:
        target = const WalletScreen();
        break;
      case AppNavTab.support:
        target = const SupportScreen();
        break;
      case AppNavTab.profile:
        target = const ProfileScreen();
        break;
      case AppNavTab.home:
        return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionDuration: Duration.zero,
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    required AppNavTab tab,
    required double sc,
    required double Function(double) f,
  }) {
    final selected = (currentTab == tab);
    final displayedIcon = (selected && selectedIcon != null) ? selectedIcon : icon;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleTabTap(context, tab),
        child: Center(
          child: Container(
            width: 152 * sc,
            height: 116 * sc,
            decoration: BoxDecoration(
              color: selected ? _activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(34 * sc),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  displayedIcon,
                  size: 50 * sc,
                  color: selected ? _blue : _grey,
                ),
                SizedBox(height: 4 * sc),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: f(24),
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? _blue : _grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final double w = math.min(media.size.width, 520);
    final double sc = w / 935;
    double f(double px) => px * sc * 1.1;
    final bottomInset = media.padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(
        8 * sc,
        14 * sc,
        8 * sc,
        math.max(bottomInset, 12 * sc),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40 * sc)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildItem(
            context: context,
            icon: Icons.home_rounded,
            label: 'Home',
            tab: AppNavTab.home,
            sc: sc,
            f: f,
          ),
          _buildItem(
            context: context,
            icon: Icons.directions_car_outlined,
            selectedIcon: Icons.directions_car_rounded,
            label: 'Rides',
            tab: AppNavTab.rides,
            sc: sc,
            f: f,
          ),
          _buildItem(
            context: context,
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet_rounded,
            label: 'Wallet',
            tab: AppNavTab.wallet,
            sc: sc,
            f: f,
          ),
          _buildItem(
            context: context,
            icon: Icons.support_agent_rounded,
            selectedIcon: Icons.support_agent_rounded,
            label: 'Support',
            tab: AppNavTab.support,
            sc: sc,
            f: f,
          ),
          _buildItem(
            context: context,
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'Profile',
            tab: AppNavTab.profile,
            sc: sc,
            f: f,
          ),
        ],
      ),
    );
  }
}
