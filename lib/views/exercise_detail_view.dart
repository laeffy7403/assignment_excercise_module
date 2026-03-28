import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/exercise_controller.dart';
import '../models/exercise.dart';
import 'exercise_add_view.dart';

class ExerciseDetailView extends StatefulWidget {
  final Exercise exercise;

  const ExerciseDetailView({Key? key, required this.exercise}) : super(key: key);

  @override
  State<ExerciseDetailView> createState() => _ExerciseDetailViewState();
}

class _ExerciseDetailViewState extends State<ExerciseDetailView> {
  final MapController _mapController = MapController();
  bool _isMapExpanded = false;

  List<LatLng> _getRouteLatLngs() {
    if (widget.exercise.routePoints == null || widget.exercise.routePoints!.isEmpty) {
      return [];
    }

    return widget.exercise.routePoints!
        .map((point) => LatLng(point['latitude']!, point['longitude']!))
        .toList();
  }

  LatLngBounds? _getRouteBounds() {
    final points = _getRouteLatLngs();
    if (points.isEmpty) return null;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasRoute = widget.exercise.routePoints != null &&
        widget.exercise.routePoints!.isNotEmpty;
    final routePoints = _getRouteLatLngs();

    return Scaffold(
      backgroundColor: hasRoute ? Colors.black : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Map View — only shown for GPS-tracked workouts that have route data
            if (hasRoute)
              GestureDetector(
                onTap: hasRoute ? () {
                  setState(() {
                    _isMapExpanded = !_isMapExpanded;
                  });
                } : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: _isMapExpanded ? MediaQuery.of(context).size.height * 0.6 : 300,
                  child: Stack(
                    children: [
                      // OpenStreetMap (FREE!)
                      hasRoute
                          ? FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: routePoints.first,
                          initialZoom: 14.0,
                          minZoom: 3.0,
                          maxZoom: 19.0,
                          initialCameraFit: _getRouteBounds() != null
                              ? CameraFit.bounds(
                            bounds: _getRouteBounds()!,
                            padding: const EdgeInsets.all(50),
                          )
                              : null,
                        ),
                        children: [
                          // Map Tiles
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.assignment_excercise_module',
                            maxZoom: 19,
                          ),

                          // Blue Route Line
                          if (routePoints.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: routePoints,
                                  color: const Color(0xFF2196F3),
                                  strokeWidth: 5.0,
                                  borderColor: Colors.white,
                                  borderStrokeWidth: 2.0,
                                ),
                              ],
                            ),

                          // Markers
                          MarkerLayer(
                            markers: [
                              // Start (Green)
                              Marker(
                                point: routePoints.first,
                                width: 40,
                                height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.flag,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),

                              // End (Red)
                              Marker(
                                point: routePoints.last,
                                width: 40,
                                height: 40,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.location_on,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // OSM Attribution
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                '© OpenStreetMap',
                                onTap: () {},
                              ),
                            ],
                          ),
                        ],
                      )
                          : Container(
                        color: Colors.grey[900],
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map_outlined,
                                size: 48,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No route data',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Buttons
                      Positioned(
                        top: 16,
                        left: 16,
                        child: _buildMapButton(
                          icon: Icons.arrow_back,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),

                      Positioned(
                        top: 16,
                        right: 16,
                        child: Row(
                          children: [
                            _buildMapButton(
                              icon: Icons.edit,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AddExerciseView(exercise: widget.exercise),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildMapButton(
                              icon: Icons.delete,
                              color: const Color(0xFFFFCDD2),
                              iconColor: Colors.red,
                              onTap: () => _confirmDelete(context),
                            ),
                          ],
                        ),
                      ),

                      // Expand indicator
                      if (hasRoute)
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isMapExpanded ? Icons.expand_less : Icons.expand_more,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isMapExpanded ? 'Collapse' : 'Expand map',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Details Panel
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  // Only round the top corners when there's a map above
                  borderRadius: hasRoute
                      ? const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  )
                      : BorderRadius.zero,
                ),
                child: Column(
                  children: [
                    // When no map, show a simple top bar with back/edit/delete
                    if (!hasRoute)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Row(
                          children: [
                            _buildMapButton(
                              icon: Icons.arrow_back,
                              onTap: () => Navigator.pop(context),
                            ),
                            const Spacer(),
                            _buildMapButton(
                              icon: Icons.edit,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        AddExerciseView(exercise: widget.exercise),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _buildMapButton(
                              icon: Icons.delete,
                              color: const Color(0xFFFFCDD2),
                              iconColor: Colors.red,
                              onTap: () => _confirmDelete(context),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.exercise.title.isEmpty
                                  ? widget.exercise.type.displayName
                                  : widget.exercise.title,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${widget.exercise.formattedDate}, ${widget.exercise.formattedTime} - ${_getEndTime()}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),


                            /// Goal Progress Section
                            if (widget.exercise.stepGoal != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: widget.exercise.steps! >= widget.exercise.stepGoal!
                                        ? Colors.green
                                        : Colors.orange,
                                    width: 2,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          widget.exercise.steps! >= widget.exercise.stepGoal!
                                              ? Icons.check_circle
                                              : Icons.flag,
                                          color: widget.exercise.steps! >= widget.exercise.stepGoal!
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          widget.exercise.steps! >= widget.exercise.stepGoal!
                                              ? '🎉 Step Goal Achieved!'
                                              : 'Step Goal Progress',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: widget.exercise.steps! >= widget.exercise.stepGoal!
                                                ? Colors.green[700]
                                                : Colors.orange[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    LinearProgressIndicator(
                                      value: (widget.exercise.steps! / widget.exercise.stepGoal!).clamp(0.0, 1.0),
                                      backgroundColor: Colors.grey[300],
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        widget.exercise.steps! >= widget.exercise.stepGoal!
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      minHeight: 8,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${widget.exercise.steps} / ${widget.exercise.stepGoal} steps',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            _buildDetailRow('exercise', widget.exercise.type.displayName),
                            const Divider(height: 1),

                            if (widget.exercise.distanceKm != null)
                              _buildDetailRow('Distance', '${widget.exercise.distanceKm!.toStringAsFixed(1)} km'),
                            if (widget.exercise.distanceKm != null)
                              const Divider(height: 1),

                            if (widget.exercise.energyExpended != null)
                              _buildDetailRow('Energy expended', '${widget.exercise.energyExpended} cal'),
                            if (widget.exercise.energyExpended != null)
                              const Divider(height: 1),

                            _buildDetailRow('Start', 'Today   ${widget.exercise.formattedTime}'),
                            const Divider(height: 1),

                            _buildDetailRow('Duration', '${widget.exercise.durationMinutes} min'),
                            const Divider(height: 1),

                            const SizedBox(height: 16),

                            if (widget.exercise.notes != null && widget.exercise.notes!.isNotEmpty) ...[
                              const Text(
                                'add note',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.exercise.notes!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.6,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),   // Expanded(SingleChildScrollView)
                  ],
                ),       // Column
              ),
            ),           // Expanded(details panel)
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    Color iconColor = Colors.black87,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  String _getEndTime() {
    final endTime = widget.exercise.startTime.add(
      Duration(minutes: widget.exercise.durationMinutes),
    );
    final hour = endTime.hour;
    final minute = endTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'pm' : 'am';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Exercise'),
          content: const Text('Are you sure you want to delete this exercise?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final controller = Provider.of<ExerciseController>(
                  context,
                  listen: false,
                );

                final success = await controller.deleteExercise(widget.exercise.id!);

                Navigator.pop(dialogContext);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Exercise deleted' : 'Failed to delete exercise',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }
}