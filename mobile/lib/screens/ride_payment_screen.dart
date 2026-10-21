import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/razorpay_service.dart';
import '../services/wallet_service.dart';
import 'railone_payment_screen.dart';

/// RidePaymentScreen implements the RailOne payment gateway experience
/// for ride booking checkout with dynamic fare calculation and Razorpay test-mode integration.
class RidePaymentScreen extends StatelessWidget {
  final Map<String, dynamic> ride;
  final int seatsBooked;
  final double pricePerSeat;
  final double totalAmount;
  final List<Map<String, dynamic>> passengers;
  final ApiService? apiService;
  final WalletService? walletService;
  final RazorpayService? razorpayService;

  const RidePaymentScreen({
    super.key,
    required this.ride,
    required this.seatsBooked,
    required this.pricePerSeat,
    required this.totalAmount,
    required this.passengers,
    this.apiService,
    this.walletService,
    this.razorpayService,
  });

  @override
  Widget build(BuildContext context) {
    return RailOnePaymentScreen.forRide(
      ride: ride,
      seatsBooked: seatsBooked,
      pricePerSeat: pricePerSeat,
      totalAmount: totalAmount,
      passengers: passengers,
      apiService: apiService,
      walletService: walletService,
      razorpayService: razorpayService,
    );
  }
}
