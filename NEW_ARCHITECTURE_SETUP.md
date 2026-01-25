# New Architecture Setup Guide

## Overview
This guide documents the migration from Supabase storage to a new architecture using:
- **Cloudflare R2** for media storage (images, videos, audio)
- **Mux** for live video streaming (pending implementation)
- **Qwen (Alibaba)** AI for content creation features (pending implementation)

## ✅ Completed: Cloudflare R2 Integration

### Files Created/Modified

#### New Services
1. **`lib/services/cloudflare_r2_service.dart`** - Core R2 service with AWS S3-compatible API
2. **`lib/services/media_upload_service.dart`** - High-level media upload abstraction

#### Updated Services
1. **`lib/services/database_service.dart`** - Updated `uploadFile` method to use MediaUploadService
2. **`lib/services/storage_service.dart`** - Updated all upload methods (uploadImage, uploadAvatar, uploadVideo, uploadFromBytes)

#### Dependencies Added
- `crypto: ^3.0.3` - Required for AWS signature calculations

### Cloudflare R2 Configuration

The following credentials are configured in `cloudflare_r2_service.dart`:
```dart
static const String accessKeyId = 'your_access_key_id';
static const String secretAccessKey = 'your_secret_access_key';
static const String endpoint = 'https://your-account-id.r2.cloudflarestorage.com';
static const String bucketName = 'equal-media';
static const String region = 'auto';
```

### Media Upload Structure

Files are organized in R2 with the following structure:
```
equal-media/
├── profile-images/
│   └── user_{userId}/
│       └── profile_{timestamp}.{ext}
├── post-images/
│   └── user_{userId}/
│       └── post_{postId}/
│           └── image_{timestamp}.{ext}
├── post-videos/
│   └── user_{userId}/
│       └── post_{postId}/
│           └── video_{timestamp}.{ext}
├── thumbnails/
│   └── user_{userId}/
│       └── post_{postId}/
│           └── thumb_{timestamp}.{ext}
└── audio/
    └── user_{userId}/
        └── post_{postId}/
            └── audio_{timestamp}.{ext}
```

### API Changes

All upload methods now require `userId` parameter:
- `DatabaseService.uploadFile()` - requires `userId` and `postId`
- `StorageService.uploadImage()` - requires `userId`
- `StorageService.uploadAvatar()` - requires `userId`
- `StorageService.uploadVideo()` - requires `userId`
- `StorageService.uploadFromBytes()` - requires `userId`

## 🔄 Next Steps

### 1. Mux Integration (High Priority)

#### Required Credentials
- Mux Token ID
- Mux Token Secret
- Mux Environment ID (optional)

#### Implementation Plan
1. Create `lib/services/mux_service.dart`
2. Add Mux SDK dependency: `mux_dart: ^1.0.0`
3. Implement live streaming features:
   - Create live streams
   - Generate stream keys
   - Handle stream events
   - Video on demand (VOD) processing

#### Files to Create
- `lib/services/mux_service.dart`
- `lib/models/live_stream_model.dart`
- `lib/screens/live_streaming/`

### 2. Qwen AI Integration (High Priority)

#### Required Credentials
- Qwen API Key
- Qwen API Endpoint
- Model Configuration

#### Implementation Plan
1. Create `lib/services/qwen_ai_service.dart`
2. Add HTTP client for API calls
3. Implement AI features:
   - Content generation
   - Image analysis
   - Text enhancement
   - Content moderation

#### Files to Create
- `lib/services/qwen_ai_service.dart`
- `lib/models/ai_response_model.dart`
- `lib/screens/ai_content/`

### 3. Testing & Validation

#### Test Cases Needed
1. **Media Upload Flow**
   - Profile image upload
   - Post image upload
   - Video upload with thumbnails
   - Audio upload

2. **Error Handling**
   - Network failures
   - Authentication errors
   - File size limits
   - Invalid file types

3. **Performance Testing**
   - Large file uploads
   - Concurrent uploads
   - Memory usage

## 🚨 Important Notes

### Breaking Changes
- All upload methods now require `userId` parameter
- File URLs now point to Cloudflare R2 instead of Supabase
- Upload file naming convention has changed

### Migration Considerations
- Existing Supabase storage files will remain accessible
- New uploads will go to Cloudflare R2
- Consider implementing a migration script for existing files

### Security
- R2 credentials are currently hardcoded (should be moved to environment variables)
- Implement proper access controls and CORS policies
- Add file type validation and virus scanning

## 📋 Deployment Checklist

- [ ] Update environment variables with R2 credentials
- [ ] Configure Cloudflare R2 bucket policies
- [ ] Set up CDN for R2 bucket
- [ ] Implement Mux integration
- [ ] Implement Qwen AI integration
- [ ] Run comprehensive tests
- [ ] Update documentation
- [ ] Deploy to staging environment
- [ ] Performance testing
- [ ] Deploy to production

## 🔧 Troubleshooting

### Common Issues
1. **Authentication Errors**: Verify R2 credentials and permissions
2. **CORS Issues**: Configure bucket CORS policies
3. **File Upload Failures**: Check file size limits and network connectivity
4. **Missing Dependencies**: Run `flutter pub get` after adding new packages

### Debug Commands
```bash
# Install dependencies
flutter pub get

# Run app in debug mode
flutter run -d chrome --web-port=3000

# Check for issues
flutter analyze

# Run tests
flutter test
```

This architecture provides a scalable foundation for media handling, live streaming, and AI-powered content features.