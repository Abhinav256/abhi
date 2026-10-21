import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';

/// Design tokens for the My Vehicles screen (AbhiShare blue & white identity).
class _VC {
  static const Color background = Color(0xFFF4F8FF);
  static const Color navy = Color(0xFF0B1F4B);
  static const Color blue = Color(0xFF0A5CFF);
  static const Color blueDark = Color(0xFF0048E0);
  static const Color blueLight = Color(0xFFEAF2FF);
  static const Color greyBlue = Color(0xFF5B6B8C);
  static const Color red = Color(0xFFE0212B);
  static const double maxContentWidth = 640;
}

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  List<dynamic> _vehicles = [];

  bool _isLoading = true;
  bool _isAdding = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final vehicles = await _apiService.getVehicles();

      if (!mounted) return;

      setState(() {
        _vehicles = vehicles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _showAddVehicleDialog() async {
    final vehicleNumberController = TextEditingController();
    final modelController = TextEditingController();

    String vehicleType = 'two_wheeler';

    XFile? rcImage;
    XFile? vehicleImage;

    String? validationError;

    String? createdVehicleNumber;
    String? createdVehicleType;
    String? createdModel;
    XFile? selectedRCImage;
    XFile? selectedVehicleImage;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> pickRCImage() async {
              final image = await _imagePicker.pickImage(
                source: ImageSource.gallery,
              );

              if (image == null) return;

              setDialogState(() {
                rcImage = image;
              });
            }

            Future<void> pickVehicleImage() async {
              final image = await _imagePicker.pickImage(
                source: ImageSource.gallery,
              );

              if (image == null) return;

              setDialogState(() {
                vehicleImage = image;
              });
            }

            void createVehicle() {
              final vehicleNumber = vehicleNumberController.text.trim();

              final model = modelController.text.trim();

              if (vehicleNumber.isEmpty) {
                setDialogState(() {
                  validationError = 'Please enter the vehicle number.';
                });
                return;
              }

              if (model.isEmpty) {
                setDialogState(() {
                  validationError = 'Please enter the vehicle model.';
                });
                return;
              }

              if (rcImage == null) {
                setDialogState(() {
                  validationError = 'Please select the RC image.';
                });
                return;
              }

              if (vehicleImage == null) {
                setDialogState(() {
                  validationError = 'Please select the vehicle image.';
                });
                return;
              }

              createdVehicleNumber = vehicleNumber;
              createdVehicleType = vehicleType;
              createdModel = model;
              selectedRCImage = rcImage;
              selectedVehicleImage = vehicleImage;

              Navigator.of(dialogContext).pop();
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text(
                'Add Vehicle',
                style: TextStyle(
                  color: _VC.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: vehicleNumberController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Number',
                        hintText: 'TS09AB1234',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: vehicleType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'two_wheeler',
                          child: Text(
                            '2-Seater / Two-Wheeler',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'five_seater',
                          child: Text('5-Seater'),
                        ),
                        DropdownMenuItem(
                          value: 'seven_seater',
                          child: Text('7-Seater'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setDialogState(() {
                          vehicleType = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: modelController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Model',
                        hintText: 'Hyundai Creta',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ImagePickerTile(
                      title: 'RC Document',
                      file: rcImage,
                      onTap: pickRCImage,
                    ),
                    const SizedBox(height: 12),
                    _ImagePickerTile(
                      title: 'Vehicle Photo',
                      file: vehicleImage,
                      onTap: pickVehicleImage,
                    ),
                    if (validationError != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _VC.blue),
                  onPressed: createVehicle,
                  child: const Text('Add Vehicle'),
                ),
              ],
            );
          },
        );
      },
    );

    // The dialog is fully closed now.
    // Delay disposal to allow pop animation to finish, preventing
    // '_dependents.isEmpty is not true' assertion error.
    Future.delayed(const Duration(seconds: 1), () {
      vehicleNumberController.dispose();
      modelController.dispose();
    });

    // User cancelled.
    if (createdVehicleNumber == null ||
        createdVehicleType == null ||
        createdModel == null ||
        selectedRCImage == null ||
        selectedVehicleImage == null) {
      return;
    }

    await _createVehicle(
      vehicleNumber: createdVehicleNumber!,
      vehicleType: createdVehicleType!,
      model: createdModel!,
      rcImage: selectedRCImage!,
      vehicleImage: selectedVehicleImage!,
    );
  }

  Future<void> _createVehicle({
    required String vehicleNumber,
    required String vehicleType,
    required String model,
    required XFile rcImage,
    required XFile vehicleImage,
  }) async {
    setState(() {
      _isAdding = true;
    });

    try {
      final result = await _apiService.addVehicle(
        vehicleNumber: vehicleNumber,
        vehicleType: vehicleType,
        model: model,
      );

      final vehicleId = result['vehicle_id'] as String;

      await _apiService.uploadVehicleImage(
        vehicleId: vehicleId,
        image: rcImage,
        imageType: 'rc',
      );

      await _apiService.uploadVehicleImage(
        vehicleId: vehicleId,
        image: vehicleImage,
        imageType: 'vehicle',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle added successfully')),
      );

      await _loadVehicles();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add vehicle: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  Future<void> _confirmDeleteVehicle(Map<String, dynamic> vehicle) async {
    final vehicleId = vehicle['id'] as String?;
    if (vehicleId == null) return;
    final model = vehicle['model'] as String? ?? 'Vehicle';
    final vehicleNumber = vehicle['vehicle_number'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Delete Vehicle',
          style: TextStyle(color: _VC.navy, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to delete $model ($vehicleNumber)? This will permanently remove it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _VC.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiService.deleteVehicle(vehicleId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vehicle deleted successfully')),
      );
      _loadVehicles();
    } catch (e) {
      if (!mounted) return;
      final rawMsg = e.toString().replaceFirst('Exception: ', '').trim();
      final message = (rawMsg.contains('violates foreign key constraint') ||
              rawMsg.contains('rides_vehicle_id_fkey') ||
              rawMsg.contains('23503') ||
              rawMsg.contains('existing bookings'))
          ? 'You cannot delete this vehicle because it has existing bookings.'
          : rawMsg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _vehicleTypeLabel(String type) {
    switch (type) {
      case 'two_wheeler':
        return '2-Seater';

      case 'five_seater':
        return '5-Seater';

      case 'seven_seater':
        return '7-Seater';

      default:
        return type;
    }
  }

  double _horizontalPadding(double width) =>
      (width * 0.055).clamp(16.0, 28.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final hPad = _horizontalPadding(width);

    return Scaffold(
      backgroundColor: _VC.background,
      body: Stack(
        children: [
          const Positioned.fill(child: _WaveBackground()),
          SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _VC.maxContentWidth,
                ),
                child: Column(
                  children: [
                    _buildHeader(hPad),
                    Expanded(child: _buildBody(hPad)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _AddVehicleButton(
        isBusy: _isAdding,
        onPressed: _isAdding ? null : _showAddVehicleDialog,
      ),
    );
  }

  Widget _buildHeader(double hPad) {
    final canPop = Navigator.of(context).canPop();
    final showCount = !_isLoading && _errorMessage == null;
    final count = _vehicles.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad - 8, 12, hPad - 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: _VC.navy, size: 28),
              tooltip: 'Back',
              padding: const EdgeInsets.all(12),
            )
          else
            const SizedBox(width: 8),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Vehicles',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _VC.navy,
                      height: 1.15,
                    ),
                  ),
                  if (showCount) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$count ${count == 1 ? 'vehicle' : 'vehicles'}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7C8DB0),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadVehicles,
            icon: const Icon(Icons.refresh, size: 28),
            color: _VC.navy,
            disabledColor: _VC.greyBlue.withValues(alpha: 0.4),
            tooltip: 'Refresh',
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double hPad) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _VC.blue),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(hPad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: _VC.red),
              const SizedBox(height: 16),
              const Text(
                'Unable to load vehicles',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _VC.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _VC.greyBlue),
              ),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _VC.blue,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
                onPressed: _loadVehicles,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_vehicles.isEmpty) {
      return RefreshIndicator(
        color: _VC.blue,
        onRefresh: _loadVehicles,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(hPad),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: const BoxDecoration(
                          color: _VC.blueLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.directions_car_outlined,
                          size: 56,
                          color: _VC.blue,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'No vehicles added yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _VC.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add your vehicle to start creating rides.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _VC.greyBlue, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _VC.blue,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                        ),
                        onPressed: _isAdding ? null : _showAddVehicleDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Vehicle'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      color: _VC.blue,
      onRefresh: _loadVehicles,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 120 + bottomInset),
        itemCount: _vehicles.length,
        separatorBuilder: (context, index) => const SizedBox(height: 20),
        itemBuilder: (context, index) {
          final vehicle = _vehicles[index] as Map<String, dynamic>;

          return _VehicleCard(
            vehicle: vehicle,
            vehicleTypeLabel: _vehicleTypeLabel(
              vehicle['vehicle_type'] as String? ?? '',
            ),
            onDelete: () => _confirmDeleteVehicle(vehicle),
          );
        },
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final String vehicleTypeLabel;
  final VoidCallback onDelete;

  const _VehicleCard({
    required this.vehicle,
    required this.vehicleTypeLabel,
    required this.onDelete,
  });

  Widget _imageFallback() {
    return Container(
      color: _VC.blueLight,
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car, size: 64, color: _VC.blue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = vehicle['model'] as String? ?? '';
    final vehicleNumber = vehicle['vehicle_number'] as String? ?? '';
    final vehiclePhoto = vehicle['vehicle_photo_url'] as String?;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _VC.blue.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.75,
              child: (vehiclePhoto != null && vehiclePhoto.isNotEmpty)
                  ? Image.network(
                      vehiclePhoto.startsWith('http')
                          ? vehiclePhoto
                          : '${ApiService.baseUrl}$vehiclePhoto',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: _VC.blueLight,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _VC.blue,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) =>
                          _imageFallback(),
                    )
                  : _imageFallback(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 10, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: _VC.navy,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          vehicleNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            color: _VC.greyBlue,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _SeatBadge(label: vehicleTypeLabel),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: _VC.red,
                      size: 30,
                    ),
                    tooltip: 'Delete Vehicle',
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatBadge extends StatelessWidget {
  final String label;

  const _SeatBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: _VC.blueLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_seat, size: 22, color: _VC.blue),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _VC.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddVehicleButton extends StatelessWidget {
  final bool isBusy;
  final VoidCallback? onPressed;

  const _AddVehicleButton({required this.isBusy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1470FF), _VC.blueDark],
        ),
        boxShadow: [
          BoxShadow(
            color: _VC.blue.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isBusy)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.add, color: Colors.white, size: 30),
                const SizedBox(width: 14),
                const Text(
                  'Add Vehicle',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft blue gradient with subtle flowing waves, as in the reference.
class _WaveBackground extends StatelessWidget {
  const _WaveBackground();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _WavePainter());
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F9FF), Color(0xFFEFF5FF)],
        ).createShader(rect),
    );

    final w = size.width;
    final h = size.height;

    final wave1 = Path()
      ..moveTo(w, h * 0.55)
      ..cubicTo(w * 0.80, h * 0.60, w * 0.55, h * 0.70, w * 0.45, h * 0.80)
      ..cubicTo(w * 0.30, h * 0.92, w * 0.10, h * 0.93, 0, h * 0.88)
      ..lineTo(0, h)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      wave1,
      Paint()..color = const Color(0xFFE3EDFC).withValues(alpha: 0.55),
    );

    final wave2 = Path()
      ..moveTo(w, h * 0.69)
      ..cubicTo(w * 0.80, h * 0.70, w * 0.65, h * 0.78, w * 0.55, h * 0.88)
      ..cubicTo(w * 0.45, h * 0.97, w * 0.25, h * math.min(1.0, 0.99), 0, h)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      wave2,
      Paint()..color = const Color(0xFFDCE9FB).withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ImagePickerTile extends StatelessWidget {
  final String title;
  final XFile? file;
  final VoidCallback onTap;

  const _ImagePickerTile({
    required this.title,
    required this.file,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _VC.blueLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.image_outlined, color: _VC.blue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    file == null ? 'Tap to select image' : file!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}