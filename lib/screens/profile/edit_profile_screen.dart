import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../config/app_colors.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../services/localization_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const EditProfileScreen({super.key, required this.userProfile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _authService = AuthService();
  final _storageService = StorageService();
  final _imagePicker = ImagePicker();

  bool _isLoading = false;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  String? _selectedImagePath;
  Uint8List? _selectedImageBytes;
  XFile? _selectedImageFile;
  String? _currentAvatarUrl;

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _usernameController.addListener(_checkUsernameAvailability);
  }

  // Detect MIME type from file bytes (for web uploads)
  String _detectMimeTypeFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return 'image/jpeg'; // Default fallback

    // Check for common image file signatures
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg'; // JPEG
    } else if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png'; // PNG
    } else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif'; // GIF
    } else if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp'; // WebP
    }

    return 'image/jpeg'; // Default to JPEG if unknown
  }

  // Get file extension from MIME type
  String _getExtensionFromMimeType(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      default:
        return '.jpg'; // Default to .jpg
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initializeFields() {
    _fullNameController.text =
        widget.userProfile['display_name'] ??
        ''; // Fixed: use display_name instead of full_name
    _usernameController.text = widget.userProfile['username'] ?? '';
    _bioController.text = widget.userProfile['bio'] ?? '';
    _currentAvatarUrl = widget.userProfile['avatar_url'];
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();
    if (username.length < 3 || username == widget.userProfile['username']) {
      setState(() {
        _isUsernameAvailable = true;
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() => _isCheckingUsername = true);

    try {
      final isAvailable = await _authService.isUsernameAvailable(username);
      if (mounted) {
        setState(() {
          _isUsernameAvailable = isAvailable;
          _isCheckingUsername = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = false;
        });

        // Debug logging for username check errors
        if (kDebugMode) {
          debugPrint(('Username availability check error: $e').toString());
          debugPrint(('Username being checked: $username').toString());
        }

        // Show error message for network issues
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('network') ||
            errorString.contains('connection') ||
            errorString.contains('timeout')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Unable to check username availability. Please check your connection.',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        if (kIsWeb) {
          // For web, read as bytes
          final bytes = await image.readAsBytes();
          setState(() {
            _selectedImageFile = image;
            _selectedImageBytes = bytes;
            _selectedImagePath = null;
            _currentAvatarUrl =
                null; // Clear existing avatar when a new image is selected
          });
        } else {
          // For mobile, use path
          setState(() {
            _selectedImagePath = image.path;
            _selectedImageFile = image;
            _selectedImageBytes = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // Get specific error message for image picking
        String errorMessage = LocalizationService.t('failed_pick_image');
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('permission') ||
            errorString.contains('denied')) {
          errorMessage =
              'Camera/Gallery permission denied. Please enable in settings.';
        } else if (errorString.contains('camera') ||
            errorString.contains('unavailable')) {
          errorMessage = 'Camera is not available on this device.';
        } else if (errorString.contains('cancelled') ||
            errorString.contains('canceled')) {
          return; // Don't show error for user cancellation
        } else if (errorString.contains('network') ||
            errorString.contains('connection')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (errorString.contains('storage') ||
            errorString.contains('space')) {
          errorMessage =
              'Insufficient storage space. Please free up some space.';
        } else if (errorString.contains('format') ||
            errorString.contains('unsupported')) {
          errorMessage =
              'Unsupported image format. Please choose a different image.';
        }

        // Debug logging
        if (kDebugMode) {
          debugPrint(('Image picker error: $e').toString());
          debugPrint(('Error type: ${e.runtimeType}').toString());
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    if (kIsWeb) {
      // Camera not supported on web
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LocalizedText('camera_not_available_web_use_gallery'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        if (kIsWeb) {
          // For web, read as bytes
          final bytes = await image.readAsBytes();
          setState(() {
            _selectedImageFile = image;
            _selectedImageBytes = bytes;
            _selectedImagePath = null;
          });
        } else {
          // For mobile, use path
          setState(() {
            _selectedImagePath = image.path;
            _selectedImageFile = image;
            _selectedImageBytes = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // Get specific error message for camera
        String errorMessage = 'Failed to take photo. Please try again.';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('permission') ||
            errorString.contains('denied')) {
          errorMessage =
              'Camera permission denied. Please enable camera access in settings.';
        } else if (errorString.contains('camera') ||
            errorString.contains('unavailable')) {
          errorMessage = 'Camera is not available on this device.';
        } else if (errorString.contains('cancelled') ||
            errorString.contains('canceled')) {
          return; // Don't show error for user cancellation
        } else if (errorString.contains('storage') ||
            errorString.contains('space')) {
          errorMessage =
              'Insufficient storage space. Please free up some space.';
        } else if (errorString.contains('hardware') ||
            errorString.contains('busy')) {
          errorMessage = 'Camera is busy or unavailable. Please try again.';
        }

        // Debug logging
        if (kDebugMode) {
          debugPrint(('Camera error: $e').toString());
          debugPrint(('Error type: ${e.runtimeType}').toString());
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<String> _uploadImage(String imagePath) async {
    try {
      final currentUser = _authService.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      if (kIsWeb) {
        // Web upload: read bytes from XFile
        final xFile = XFile(imagePath);
        final bytes = await xFile.readAsBytes();
        String fileName = xFile.name;

        // Debug logging
        debugPrint(('🔍 DEBUG: Original fileName: $fileName').toString());
        debugPrint(('🔍 DEBUG: Image path: $imagePath').toString());

        // Ensure fileName has proper extension for web uploads
        if (!fileName.contains('.') || fileName.startsWith('image_picker_')) {
          // Fallback: detect MIME type from bytes and add appropriate extension
          final mimeType = _detectMimeTypeFromBytes(bytes);
          final extension = _getExtensionFromMimeType(mimeType);
          fileName =
              'avatar_${DateTime.now().millisecondsSinceEpoch}$extension';
          debugPrint(
            ('🔍 DEBUG: Generated fileName: $fileName (MIME: $mimeType)')
                .toString(),
          );
        }

        return await _storageService.uploadAvatar(
          userId: currentUser.id,
          avatarBytes: bytes,
          fileName: fileName,
        );
      } else {
        // Mobile upload: use File
        final imageFile = File(imagePath);
        return await _storageService.uploadAvatar(
          avatarFile: imageFile,
          userId: currentUser.id,
        );
      }
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  Future<void> _debugTestProfileUpload() async {
    debugPrint(
      ('🚨 DEBUG BUTTON PRESSED! Function is being called!').toString(),
    );
    debugPrint(('🚨 DEBUG: Current time: ${DateTime.now()}').toString());

    // Show immediate visual feedback
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const LocalizedText('Debug Test Running'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              const LocalizedText('Testing profile upload functionality...'),
            ],
          ),
        ),
      );
    }

    try {
      debugPrint(
        ('🔍 DEBUG: Starting comprehensive profile upload test...').toString(),
      );

      // Check authentication
      final currentUser = _authService.currentUser;
      debugPrint(('🔍 DEBUG: Current user: ${currentUser?.id}').toString());
      debugPrint(('🔍 DEBUG: User email: ${currentUser?.email}').toString());

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Check session validity
      debugPrint(('🔍 DEBUG: Checking session validity...').toString());
      final isAuthenticated = _authService.isAuthenticated;
      debugPrint(('🔍 DEBUG: Is authenticated: $isAuthenticated').toString());

      // Test storage bucket access using Supabase directly
      debugPrint(('🔍 DEBUG: Testing storage bucket access...').toString());
      try {
        final supabaseClient = Supabase.instance.client;
        final buckets = await supabaseClient.storage.listBuckets();
        debugPrint(
          (
            '🔍 DEBUG: Available buckets: ${buckets.map((b) => b.name).toList()}',
          ).toString(),
        );

        // Test profile-images bucket specifically
        try {
          final files = await supabaseClient.storage
              .from('profile-images')
              .list(path: currentUser.id);
          debugPrint(
            ('🔍 DEBUG: User folder files: ${files.length}').toString(),
          );
          for (var file in files) {
            debugPrint(
              (
                '🔍 DEBUG: File: ${file.name}, Size: ${file.metadata?['size']}, Updated: ${file.updatedAt}',
              ).toString(),
            );
          }
        } catch (e) {
          debugPrint(('🔍 DEBUG: Error accessing user folder: $e').toString());
        }
      } catch (storageError) {
        debugPrint(
          ('🔍 DEBUG: Storage access failed: $storageError').toString(),
        );
      }

      // Test actual image selection and upload if user has selected an image
      if (_selectedImagePath != null) {
        debugPrint(('🔍 DEBUG: Testing actual image upload...').toString());
        try {
          final uploadedUrl = await _uploadImage(_selectedImagePath!);
          debugPrint(
            ('🔍 DEBUG: Upload successful! URL: $uploadedUrl').toString(),
          );
        } catch (uploadError) {
          debugPrint(('🔍 DEBUG: Upload failed: $uploadError').toString());
        }
      } else {
        debugPrint(('🔍 DEBUG: No image selected for upload test').toString());
      }

      // Test getUserProfile method
      try {
        debugPrint(('🔍 DEBUG: Testing getUserProfile...').toString());
        final profile = await _authService.getUserProfile(currentUser.id);
        debugPrint(('🔍 DEBUG: Profile loaded: ${profile != null}').toString());
        if (profile != null) {
          debugPrint(
            ('🔍 DEBUG: Avatar URL: ${profile['avatar_url']}').toString(),
          );
        }
      } catch (profileError) {
        debugPrint(
          ('🔍 DEBUG: getUserProfile failed: $profileError').toString(),
        );
      }

      // Close dialog and show success message
      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Debug test completed! Check console for detailed results.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint(('🔍 DEBUG: Test failed with error: $e').toString());
      debugPrint(('🔍 DEBUG: Error type: ${e.runtimeType}').toString());
      debugPrint(('🔍 DEBUG: Stack trace: ${StackTrace.current}').toString());

      if (mounted) {
        Navigator.of(context).pop(); // Close the dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Debug test failed: ${e.toString().length > 100 ? '${e.toString().substring(0, 100)}...' : e.toString()}',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showImagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Change Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImageOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _takePhoto();
                  },
                ),
                _buildImageOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage();
                  },
                ),
                if (_currentAvatarUrl != null || _selectedImagePath != null)
                  _buildImageOption(
                    icon: Icons.delete,
                    label: 'Remove',
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedImagePath = null;
                        _currentAvatarUrl = null;
                      });
                    },
                    isDestructive: true,
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildImageOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDestructive
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(
              icon,
              color: isDestructive ? AppColors.error : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDestructive ? AppColors.error : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isUsernameAvailable) return;

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      // Upload image if selected
      String? avatarUrl = _currentAvatarUrl;
      if (_selectedImagePath != null) {
        // Mobile: upload from file path
        avatarUrl = await _uploadImage(_selectedImagePath!);
      } else if (kIsWeb &&
          _selectedImageBytes != null &&
          _selectedImageFile != null) {
        // Web: upload from bytes + filename
        final currentUser = _authService.currentUser;
        if (currentUser == null) {
          throw Exception('User not authenticated');
        }

        var fileName = _selectedImageFile!.name;
        // Ensure filename has an extension; generate one if needed
        if (!fileName.contains('.') || fileName.startsWith('image_picker_')) {
          final mimeType = _detectMimeTypeFromBytes(_selectedImageBytes!);
          final extension = _getExtensionFromMimeType(mimeType);
          fileName =
              'avatar_${DateTime.now().millisecondsSinceEpoch}$extension';
        }

        avatarUrl = await _storageService.uploadAvatar(
          userId: currentUser.id,
          avatarBytes: _selectedImageBytes!,
          fileName: fileName,
        );
      }

      await _authService.updateProfile(
        fullName: _fullNameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
        bio: _bioController.text.trim(),
        avatarUrl: avatarUrl,
      );

      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Profile updated successfully!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();

        // Get specific error message
        String errorMessage = 'Failed to update profile. Please try again.';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('network') ||
            errorString.contains('connection')) {
          errorMessage =
              'Network error. Please check your internet connection.';
        } else if (errorString.contains('unauthorized') ||
            errorString.contains('401')) {
          errorMessage = 'Session expired. Please log in again.';
        } else if (errorString.contains('forbidden') ||
            errorString.contains('403')) {
          errorMessage = 'Access denied. Please check your permissions.';
        } else if (errorString.contains('username already exists') ||
            errorString.contains('username')) {
          errorMessage =
              'Username is already taken. Please choose a different one.';
        } else if (errorString.contains('timeout')) {
          errorMessage = 'Request timed out. Please try again.';
        } else if (errorString.contains('server') ||
            errorString.contains('500')) {
          errorMessage = 'Server error. Please try again later.';
        } else if (errorString.contains('validation') ||
            errorString.contains('invalid')) {
          errorMessage = 'Invalid profile data. Please check your inputs.';
        } else if (errorString.contains('storage') ||
            errorString.contains('upload')) {
          errorMessage = 'Failed to upload profile image. Please try again.';
        } else if (errorString.contains('database') ||
            errorString.contains('constraint')) {
          errorMessage =
              'Database error. Please contact support if this persists.';
        }

        // Debug logging
        if (kDebugMode) {
          debugPrint(('🔥 PROFILE UPDATE ERROR DETAILS:').toString());
          debugPrint(('Error: $e').toString());
          debugPrint(('Error type: ${e.runtimeType}').toString());
          debugPrint(('Error string: $errorString').toString());
          debugPrint(
            ('Current user: ${_authService.currentUser?.id}').toString(),
          );
          debugPrint(
            (
              'Update data: {fullName: ${_fullNameController.text}, username: ${_usernameController.text}, bio: ${_bioController.text}}',
            ).toString(),
          );

          // Check if this is a Supabase error with more details
          if (e is PostgrestException) {
            debugPrint(('PostgrestException details:').toString());
            debugPrint(('  Message: ${e.message}').toString());
            debugPrint(('  Code: ${e.code}').toString());
            debugPrint(('  Details: ${e.details}').toString());
            debugPrint(('  Hint: ${e.hint}').toString());
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action:
                errorString.contains('network') ||
                    errorString.contains('timeout')
                ? SnackBarAction(
                    label: LocalizationService.t('retry'),
                    textColor: Colors.white,
                    onPressed: () {
                      _saveProfile();
                    },
                  )
                : null,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          LocalizationService.t('edit_profile'),
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (kDebugMode && false)
            IconButton(
              onPressed: _debugTestProfileUpload,
              icon: Icon(Icons.bug_report, color: AppColors.primary),
              tooltip: 'Debug Profile Upload',
            ),
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: Text(
              'Save',
              style: TextStyle(
                color: _isLoading ? AppColors.textSecondary : AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Profile Photo
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _showImagePicker,
                      child: Stack(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary,
                                width: 3,
                              ),
                            ),
                            child: ClipOval(
                              child: _selectedImageBytes != null
                                  ? Image.memory(
                                      _selectedImageBytes!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildDefaultAvatar(),
                                    )
                                  : _selectedImagePath != null
                                  ? Image.file(
                                      File(_selectedImagePath!),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildDefaultAvatar(),
                                    )
                                  : _currentAvatarUrl != null &&
                                        _currentAvatarUrl!.isNotEmpty
                                  ? Image.network(
                                      _currentAvatarUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              _buildDefaultAvatar(),
                                    )
                                  : _buildDefaultAvatar(),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.background,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Debug button hidden
                    if (kDebugMode && false)
                      ElevatedButton.icon(
                        onPressed: _debugTestProfileUpload,
                        icon: Icon(Icons.bug_report, size: 16),
                        label: const LocalizedText('Debug Upload Test'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          foregroundColor: AppColors.primary,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          textStyle: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Full Name
              CustomTextField(
                controller: _fullNameController,
                label: 'Full Name',
                hint: 'Enter your full name',
                prefixIcon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your full name';
                  }
                  if (value.length < 2) {
                    return 'Name must be at least 2 characters';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Username
              CustomTextField(
                controller: _usernameController,
                label: 'Username',
                hint: 'Choose a unique username',
                prefixIcon: Icons.alternate_email,
                suffixIcon: _isCheckingUsername
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _usernameController.text.length >= 3 &&
                          _usernameController.text !=
                              widget.userProfile['username']
                    ? Icon(
                        _isUsernameAvailable ? Icons.check_circle : Icons.error,
                        color: _isUsernameAvailable
                            ? AppColors.success
                            : AppColors.error,
                      )
                    : null,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a username';
                  }
                  if (value.length < 3) {
                    return 'Username must be at least 3 characters';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                    return 'Username can only contain letters, numbers, and underscores';
                  }
                  if (!_isUsernameAvailable &&
                      value != widget.userProfile['username']) {
                    return 'Username is already taken';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Bio
              CustomTextField(
                controller: _bioController,
                label: 'Bio',
                hint: 'Tell us about yourself...',
                prefixIcon: Icons.info_outline,
                maxLines: 4,
                maxLength: 150,
                validator: (value) {
                  if (value != null && value.length > 150) {
                    return 'Bio must be 150 characters or less';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 40),

              // Save Button
              CustomButton(
                text: LocalizationService.t('save_changes'),
                onPressed: _saveProfile,
                isLoading: _isLoading,
                width: double.infinity,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.primaryGradient,
      ),
      child: Center(
        child: Text(
          (_fullNameController.text.isNotEmpty
                  ? _fullNameController.text[0]
                  : widget.userProfile['display_name']?[0] ??
                        'U') // Fixed: use display_name instead of full_name
              .toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
