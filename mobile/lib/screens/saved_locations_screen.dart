import 'package:flutter/material.dart';

import '../services/api_service.dart';

class SavedLocationsScreen extends StatefulWidget {
  const SavedLocationsScreen({super.key});

  @override
  State<SavedLocationsScreen> createState() => _SavedLocationsScreenState();
}

class _SavedLocationsScreenState extends State<SavedLocationsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  List<dynamic> _locations = [];

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await _apiService.getLocations();
      if (!mounted) return;
      setState(() {
        _locations = locs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load locations: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0F1B4D);
    const bg = Color(0xFFF3F7FD);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Saved Locations', style: TextStyle(color: navy)),
        backgroundColor: bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: navy),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? const Center(
                  child: Text(
                    'No saved locations yet.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _locations.length,
                  itemBuilder: (context, index) {
                    final loc = _locations[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF12B58A).withAlpha(30),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_on, color: Color(0xFF12B58A)),
                        ),
                        title: Text(
                          loc['name']?.toString() ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: navy),
                        ),
                        subtitle: Text(
                          loc['address']?.toString() ?? '',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
