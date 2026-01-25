# Cloudflare R2 Setup Guide

## Issue Summary
The "failing to post" error you're experiencing is due to incomplete Cloudflare R2 configuration. The app has been updated with a **Supabase fallback system** so photo uploads will work immediately, but to fully utilize R2, follow this setup guide.

## Current Status
✅ **Immediate Fix Applied**: Photo uploads now automatically fall back to Supabase if R2 fails  
❌ **R2 Configuration**: Needs to be completed for optimal performance

## Required R2 Setup Steps

### 1. Verify R2 Credentials
The current credentials in `lib/services/cloudflare_r2_service.dart` may be invalid:
```dart
static const String _accessKeyId = '6fcb86e3f11fc8662d215e00adc8a03a';
static const String _secretAccessKey = '01e7f847d5f608803bbbd206d8b6305f39adcbb2295f3692de6493e23140720d';
static const String _endpoint = 'https://27e3a9baccd9653e1ade329045460213.r2.cloudflarestorage.com';
```

**Action Required:**
1. Log into your Cloudflare dashboard
2. Go to R2 Object Storage
3. Generate new API tokens with R2 permissions
4. Update the credentials in the service file

### 2. Create Required R2 Buckets
The following buckets must be created in your Cloudflare R2 dashboard:

- `profile-images` - For user profile pictures
- `post-images` - For post photos
- `post-videos` - For video content
- `post-audio` - For audio content
- `thumbnails` - For video thumbnails

**Action Required:**
1. In Cloudflare dashboard → R2 Object Storage
2. Click "Create bucket" for each bucket name above
3. Set appropriate CORS policies for web access

### 3. Configure CORS Policies
Add these CORS rules to each bucket:

```json
[
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

### 4. Test R2 Configuration
After setup, run this test:
```bash
dart test_r2_upload.dart
```

Expected output:
```
✅ Upload successful!
Public URL: https://your-endpoint.r2.cloudflarestorage.com/post-images/test_user/test_xxxxx.png
✅ File is publicly accessible!
```

## Current Fallback Behavior

Until R2 is properly configured, the app will:

1. **Try R2 first** - Attempt upload to Cloudflare R2
2. **Fallback to Supabase** - If R2 fails, automatically use Supabase storage
3. **Log the error** - R2 errors are logged to console for debugging

This means **photo uploads will work immediately** even without R2 setup.

## Benefits of Completing R2 Setup

- **Better Performance**: R2 is optimized for media delivery
- **Lower Costs**: More cost-effective than Supabase storage
- **Global CDN**: Faster image loading worldwide
- **Scalability**: Better handling of large media files

## Troubleshooting

### If uploads still fail after R2 setup:
1. Check browser console for detailed error messages
2. Verify bucket names match exactly
3. Ensure CORS policies are applied
4. Test credentials with a simple API call

### If you prefer to keep using Supabase:
You can disable R2 entirely by updating `media_upload_service.dart` to skip the R2 attempt and go directly to Supabase.

## Files Modified

- `lib/services/media_upload_service.dart` - Added Supabase fallback
- `lib/services/cloudflare_r2_service.dart` - Fixed signature issues
- `test_r2_upload.dart` - Created for testing R2 connectivity

## Next Steps

1. **Immediate**: Photo uploads should work now with Supabase fallback
2. **Short-term**: Complete R2 setup following this guide
3. **Long-term**: Consider migrating existing Supabase files to R2

The "failing to post" error should be resolved immediately with the fallback system in place.