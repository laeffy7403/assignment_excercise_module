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

  // FIX: track mutable title/notes locally so UI refreshes after editing
  late String _title;
  late String? _notes;

  @override
  void initState() {
    super.initState();
    _title = widget.exercise.title;
    _notes = widget.exercise.notes;
  }

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

  String _formatDistance(double km) {
    if (km < 0.1) {
      return '${km.toStringAsFixed(3)} km';
    }
    return '${km.toStringAsFixed(2)} km';
  }

  @override
  Widget build(BuildContext context) {
    final hasRoute = widget.exercise.routePoints != null &&
        widget.exercise.routePoints!.isNotEmpty;
    final routePoints = _getRouteLatLngs();
    final hasDistance = widget.exercise.distanceKm != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Map View — only shown for live-tracked sessions that have route data
                if (hasRoute)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isMapExpanded = !_isMapExpanded;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: _isMapExpanded ? MediaQuery.of(context).size.height * 0.6 : 300,
                      child: Stack(
                        children: [
                          FlutterMap(
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
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.assignment_excercise_module',
                                maxZoom: 19,
                              ),
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
                              MarkerLayer(
                                markers: [
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
                                      child: const Icon(Icons.flag, color: Colors.white, size: 20),
                                    ),
                                  ),
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
                                      child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                                    ),
                                  ),
                                ],
                              ),
                              RichAttributionWidget(
                                attributions: [
                                  TextSourceAttribution('© OpenStreetMap', onTap: () {}),
                                ],
                              ),
                            ],
                          ),

                          // Back button
                          Positioned(
                            top: 16,
                            left: 16,
                            child: _buildMapButton(
                              icon: Icons.arrow_back,
                              onTap: () => Navigator.pop(context),
                            ),
                          ),

                          // FIX: GPS edit button → title/notes-only dialog
                          // (does NOT open AddExerciseView, so routePoints are never lost)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: _buildMapButton(
                              icon: Icons.edit,
                              onTap: () => _showLiveEditDialog(context),
                            ),
                          ),

                          // Delete button
                          Positioned(
                            top: 16,
                            right: 68,
                            child: _buildMapButton(
                              icon: Icons.delete_outline,
                              iconColor: Colors.red,
                              onTap: () => _confirmDelete(context),
                            ),
                          ),

                          // Expand/collapse button
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: _buildMapButton(
                              icon: _isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                              onTap: () {
                                setState(() {
                                  _isMapExpanded = !_isMapExpanded;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Details Panel
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(20, hasRoute ? 20 : 72, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // FIX: display _title (local state) so it refreshes
                          // after editing without needing a full Navigator rebuild
                          Text(
                            _title,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.exercise.formattedDate}  ·  ${widget.exercise.formattedTime} – ${_getEndTime()}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 20),

                          // Step Goal Progress (if available)
                          if (widget.exercise.steps != null && widget.exercise.stepGoal != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[200]!),
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
                                    value: (widget.exercise.steps! / widget.exercise.stepGoal!)
                                        .clamp(0.0, 1.0),
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
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          _buildDetailRow('Exercise', widget.exercise.type.displayName),
                          const Divider(height: 1),

                          if (hasDistance) ...[
                            _buildDetailRow('Distance', _formatDistance(widget.exercise.distanceKm!)),
                            const Divider(height: 1),
                          ],

                          if (widget.exercise.steps != null) ...[
                            _buildDetailRow('Steps', '${widget.exercise.steps} steps'),
                            const Divider(height: 1),
                          ],

                          if (widget.exercise.energyExpended != null) ...[
                            _buildDetailRow('Energy expended', '${widget.exercise.energyExpended} cal'),
                            const Divider(height: 1),
                          ],

                          _buildDetailRow(
                            'Start',
                            '${widget.exercise.formattedDate}   ${widget.exercise.formattedTime}',
                          ),
                          const Divider(height: 1),

                          _buildDetailRow('Duration', '${widget.exercise.durationMinutes} min'),
                          const Divider(height: 1),

                          const SizedBox(height: 16),

                          // FIX: display _notes (local state) so it refreshes after editing
                          if (_notes != null && _notes!.isNotEmpty) ...[
                            const Text(
                              'Note',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _notes!,
                              style: const TextStyle(fontSize: 13, height: 1.6, color: Colors.black87),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ), // end Column

            // Nav overlay for manual entries (no map) — back / delete / edit
            if (!hasRoute)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _buildMapButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      _buildMapButton(
                        icon: Icons.delete_outline,
                        iconColor: Colors.red,
                        onTap: () => _confirmDelete(context),
                      ),
                      const SizedBox(width: 8),
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
                    ],
                  ),
                ),
              ),
          ],
        ), // end Stack
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
          Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87)),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)],
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  String _getEndTime() {
    final endTime = widget.exercise.startTime.add(Duration(minutes: widget.exercise.durationMinutes));
    final hour = endTime.hour;
    final minute = endTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'pm' : 'am';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  // FIX: GPS entries only allow editing title + notes.
  // All sensor data (distance, steps, calories, duration, type, routePoints)
  // are preserved exactly via copyWith — they are never shown as editable fields.
  void _showLiveEditDialog(BuildContext context) {
    final titleController = TextEditingController(text: _title);
    final notesController = TextEditingController(text: _notes ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Workout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = titleController.text.trim().isEmpty
                  ? _title
                  : titleController.text.trim();
              final newNotes = notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim();

              // copyWith preserves routePoints, distanceKm, steps, energyExpended,
              // durationMinutes, type, startTime — nothing sensor-related is touched.
              final updated = widget.exercise.copyWith(
                title: newTitle,
                notes: newNotes,
              );

              final controller =
              Provider.of<ExerciseController>(context, listen: false);
              await controller.updateExercise(updated);

              Navigator.pop(dialogContext);

              // Refresh local display state without Navigator rebuild
              if (mounted) {
                setState(() {
                  _title = newTitle;
                  _notes = newNotes;
                });
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C6FDC),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
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
                final controller =
                Provider.of<ExerciseController>(context, listen: false);
                final success =
                await controller.deleteExercise(widget.exercise.id!);
                Navigator.pop(dialogContext);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success
                        ? 'Exercise deleted'
                        : 'Failed to delete exercise'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}