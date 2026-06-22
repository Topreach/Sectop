import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../../../core/themes.dart';
import '../services/community_service.dart';

/// Screen for creating a new community post with media.
///
/// Allows the user to:
/// - Pick an image or video from gallery/camera
/// - Add a caption
/// - Optionally attach location
/// - Post anonymously
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final CommunityService _service = CommunityService();
  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _mediaFile;
  String? _mediaType; // 'image' or 'video'
  bool _isUploading = false;
  bool _isAnonymous = false;
  bool _attachLocation = true;

  double? _latitude;
  double? _longitude;
  String? _locationName;
  bool _isLocating = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked != null) {
        setState(() {
          _mediaFile = File(picked.path);
          _mediaType = 'image';
        });
        if (_attachLocation) await _getLocation();
      }
    } catch (e) {
      _showSnackBar('Failed to pick image: $e');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 60),
      );
      if (picked != null) {
        setState(() {
          _mediaFile = File(picked.path);
          _mediaType = 'video';
        });
        if (_attachLocation) await _getLocation();
      }
    } catch (e) {
      _showSnackBar('Failed to pick video: $e');
    }
  }

  Future<void> _getLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _latitude = position.latitude;
      _longitude = position.longitude;

      // Reverse geocode
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          _locationName = [
            place.name,
            place.subLocality,
            place.locality,
            place.administrativeArea,
          ].where((s) => s != null && s.isNotEmpty).join(', ');
        }
      } catch (_) {
        // Geocoding failed — that's ok
      }
    } catch (_) {}
    setState(() => _isLocating = false);
  }

  Future<void> _submitPost() async {
    if (_mediaFile == null) {
      _showSnackBar('Please select an image or video to post.');
      return;
    }

    setState(() => _isUploading = true);

    try {
      // 1. Upload media
      final uploadResult = await _service.uploadMedia(_mediaFile!);

      // 2. Create post
      await _service.createPost(
        mediaUrl: uploadResult['mediaUrl']!,
        mediaType: uploadResult['mediaType']!,
        caption: _captionController.text.trim(),
        latitude: _attachLocation ? _latitude : null,
        longitude: _attachLocation ? _longitude : null,
        locationName: _attachLocation ? _locationName : null,
        isAnonymous: _isAnonymous,
      );

      if (mounted) {
        _showSnackBar('Post created successfully!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      _showSnackBar('Failed to create post: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _showMediaPickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Record Video'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library),
              title: const Text('Choose Video from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickVideo(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Post'),
        actions: [
          TextButton(
            onPressed: _isUploading ? null : _submitPost,
            child: _isUploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Post', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Media preview / picker
            _buildMediaSection(),
            const SizedBox(height: 16),
            // Caption
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                hintText: 'Write a caption...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              maxLength: 500,
            ),
            const SizedBox(height: 16),
            // Options
            _buildOptions(),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    if (_mediaFile != null) {
      return Stack(
        children: [
          if (_mediaType == 'video')
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 48, color: Colors.white54),
                    SizedBox(height: 8),
                    Text('Video selected', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                _mediaFile!,
                height: 300,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(() {
                _mediaFile = null;
                _mediaType = null;
              }),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _showMediaPickerOptions,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'Tap to add photo or video',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions() {
    return Column(
      children: [
        // Anonymous toggle
        SwitchListTile(
          title: const Text('Post anonymously'),
          subtitle: const Text('Your name will not be shown'),
          value: _isAnonymous,
          onChanged: (val) => setState(() => _isAnonymous = val),
          secondary: const Icon(Icons.incognito),
        ),
        // Location toggle
        SwitchListTile(
          title: const Text('Attach location'),
          subtitle: Text(
            _isLocating
                ? 'Getting location...'
                : (_locationName ?? 'Your current location will be attached'),
          ),
          value: _attachLocation,
          onChanged: (val) {
            setState(() => _attachLocation = val);
            if (val && _latitude == null) _getLocation();
          },
          secondary: _isLocating
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.location_on_outlined),
        ),
      ],
    );
  }
}
