import 'package:flutter/material.dart';
import '../services/global_location_service.dart';

/// A reusable widget that lets users select a location by name (city, address,
/// landmark) from anywhere in the world, instead of manually entering
/// latitude/longitude.
///
/// Uses the [GlobalLocationService] which wraps the platform-native geocoder
/// (Google Geocoder on Android, CLGeocoder on iOS).
///
/// Returns the selected coordinates via [onLocationSelected] callback.
/// Can also be used in read-only mode to display a location name from coords.
class GlobalLocationPicker extends StatefulWidget {
  /// Callback when a location is selected (or cleared).
  final void Function(double? latitude, double? longitude, String? locationName)
      onLocationSelected;

  /// Initial latitude (for editing existing locations).
  final double? initialLatitude;

  /// Initial longitude (for editing existing locations).
  final double? initialLongitude;

  /// Optional label text.
  final String label;

  /// Show in read-only mode (just display the location name).
  final bool readOnly;

  const GlobalLocationPicker({
    Key? key,
    required this.onLocationSelected,
    this.initialLatitude,
    this.initialLongitude,
    this.label = 'Location',
    this.readOnly = false,
  }) : super(key: key);

  @override
  State<GlobalLocationPicker> createState() => _GlobalLocationPickerState();
}

class _GlobalLocationPickerState extends State<GlobalLocationPicker> {
  String? _resolvedLocationName;
  double? _latitude;
  double? _longitude;

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _latitude = widget.initialLatitude;
      _longitude = widget.initialLongitude;
      _resolveInitialLocation();
    }
  }

  Future<void> _resolveInitialLocation() async {
    final result = await GlobalLocationService.reverseGeocode(
      widget.initialLatitude!,
      widget.initialLongitude!,
    );
    if (result != null && mounted) {
      setState(() {
        _resolvedLocationName = result['displayName'] as String?;
      });
    } else if (mounted) {
      setState(() {
        _resolvedLocationName =
            '${widget.initialLatitude!.toStringAsFixed(4)}, ${widget.initialLongitude!.toStringAsFixed(4)}';
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    final results = await GlobalLocationService.searchLocation(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  void _onSearchResultSelected(Map<String, dynamic> result) {
    setState(() {
      _showSearch = false;
      _searchController.clear();
      _searchResults = [];
      _latitude = result['latitude'] as double?;
      _longitude = result['longitude'] as double?;
      _resolvedLocationName = result['displayName'] as String?;
      widget.onLocationSelected(_latitude, _longitude, _resolvedLocationName);
    });
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _resolvedLocationName = null;
      _searchController.clear();
      _searchResults = [];
      _showSearch = false;
    });
    widget.onLocationSelected(null, null, null);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return _buildReadOnlyView();
    }
    return _buildEditableView();
  }

  Widget _buildReadOnlyView() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _latitude != null ? Icons.my_location : Icons.location_off,
              color: _latitude != null ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _resolvedLocationName ?? 'No location set',
                    style: TextStyle(
                      fontSize: 13,
                      color: _resolvedLocationName != null
                          ? Colors.grey[600]
                          : Colors.orange[700],
                    ),
                  ),
                  if (_latitude != null)
                    Text(
                      '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Row(
          children: [
            Icon(Icons.location_on, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_latitude != null)
              GestureDetector(
                onTap: _clearLocation,
                child: Icon(Icons.clear, size: 18, color: Colors.red[400]),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Search field
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search for a city, address or landmark...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _isSearching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          onChanged: _onSearchChanged,
        ),

        // Search results dropdown
        if (_searchResults.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (context, index) {
                final result = _searchResults[index];
                final country = result['country'] as String? ?? '';
                final city = result['city'] as String? ?? '';
                final state = result['state'] as String? ?? '';
                return ListTile(
                  dense: true,
                  leading: Icon(
                    city.isNotEmpty ? Icons.location_city : Icons.location_on,
                    size: 18,
                    color: city.isNotEmpty ? Colors.indigo : Colors.teal,
                  ),
                  title: Text(
                    result['displayName'] as String? ?? '',
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    country.isNotEmpty
                        ? '$country${state.isNotEmpty ? ' · $state' : ''}'
                        : '${result['latitude']}, ${result['longitude']}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.add_circle_outline, size: 18),
                  onTap: () => _onSearchResultSelected(result),
                );
              },
            ),
          ),

        // Manual lat/lng entry option (shown when no search results)
        if (_searchResults.isEmpty && !_isSearching && _searchController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No results found. Try a different search term.',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),

        // Selected location display
        if (_resolvedLocationName != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[600], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _resolvedLocationName!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.green[800],
                          ),
                        ),
                        if (_latitude != null && _longitude != null)
                          Text(
                            '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.green[600],
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
    );
  }
}
