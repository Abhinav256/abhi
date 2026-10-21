import 'package:flutter/material.dart';
import '../models/wallet_models.dart';
import '../services/wallet_service.dart';
import 'transaction_detail_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  static const Color _navy = Color(0xFF0F1B4D);
  static const Color _blue = Color(0xFF0B6FE0);
  static const Color _bg = Color(0xFFF3F7FD);

  final WalletService _walletService = WalletService.instance;
  final TextEditingController _searchController = TextEditingController();

  int _selectedFilterIndex = 0;
  final List<String> _filters = [
    'All',
    'Money Added',
    'Withdrawals',
    'Rides',
    'Refunds',
  ];

  @override
  void initState() {
    super.initState();
    _walletService.addListener(_onWalletChanged);
  }

  @override
  void dispose() {
    _walletService.removeListener(_onWalletChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onWalletChanged() {
    if (mounted) setState(() {});
  }

  List<WalletTransaction> _filterTransactions(List<WalletTransaction> list) {
    var result = list;

    // Filter by type
    if (_selectedFilterIndex == 1) {
      result = result.where((t) => t.type == TransactionType.moneyAdded).toList();
    } else if (_selectedFilterIndex == 2) {
      result = result.where((t) => t.type == TransactionType.withdrawal).toList();
    } else if (_selectedFilterIndex == 3) {
      result = result.where((t) => t.type == TransactionType.ridePayment).toList();
    } else if (_selectedFilterIndex == 4) {
      result = result.where((t) => t.type == TransactionType.refund).toList();
    }

    // Filter by query
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((t) {
        return t.title.toLowerCase().contains(q) ||
            t.subtitle.toLowerCase().contains(q) ||
            t.id.toLowerCase().contains(q) ||
            t.paymentMethod.toLowerCase().contains(q) ||
            t.referenceNumber.toLowerCase().contains(q);
      }).toList();
    }

    return result;
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isYesterday = dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;

    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute $period';

    if (isToday) return 'Today, $timeStr';
    if (isYesterday) return 'Yesterday, $timeStr';
    return '${dt.day} ${months[dt.month - 1]}, $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final transactions = _filterTransactions(_walletService.transactions);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Transaction History',
          style: TextStyle(
            color: _navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _navy, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Search & Filter Bar Container
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                // Search Input
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by title, ID or reference...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_filters.length, (index) {
                      final isSelected = _selectedFilterIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_filters[index]),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedFilterIndex = index);
                            }
                          },
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : Colors.grey.shade700,
                          ),
                          selectedColor: _blue,
                          backgroundColor: Colors.grey.shade100,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          // Transaction List or Empty State
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.receipt_long_outlined,
                              size: 40,
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No transactions found',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _searchController.text.isNotEmpty || _selectedFilterIndex != 0
                                ? 'Try adjusting your search or filters'
                                : 'Your wallet transactions will show up here',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: transactions.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final txn = transactions[index];
                      return _buildTransactionCard(txn);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(WalletTransaction txn) {
    final isCredit = txn.isCredit;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionDetailScreen(transaction: txn),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            children: [
              // Type Icon
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: txn.type.backgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  txn.type.icon,
                  color: txn.type.color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Title and Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            txn.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _navy,
                            ),
                          ),
                        ),
                        if (txn.status != TransactionStatus.completed) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: txn.status.badgeBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              txn.status.displayName,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: txn.status.color,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(txn.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      txn.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Amount & Chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isCredit ? '+' : '-'}${WalletService.formatAmount(txn.amount)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isCredit ? const Color(0xFF0E8A6A) : _navy,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
