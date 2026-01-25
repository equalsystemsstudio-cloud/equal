# Hugging Face API Setup Guide

This guide will help you configure the Hugging Face API token for your Equal app, providing free AI image generation for all your users.

## Step 1: Create a Hugging Face Account

1. Go to [Hugging Face](https://huggingface.co/)
2. Click "Sign Up" and create a free account
3. Verify your email address

## Step 2: Generate an API Token

1. Log in to your Hugging Face account
2. Go to [Settings > Access Tokens](https://huggingface.co/settings/tokens)
3. Click "New token"
4. Give it a name (e.g., "Equal App Token")
5. Select "Read" permissions (sufficient for inference)
6. Click "Generate a token"
7. **Copy the token immediately** (you won't be able to see it again)

## Step 3: Configure Your App

1. Open `lib/config/api_config.dart`
2. Replace `'hf_YOUR_ACTUAL_TOKEN_HERE'` with your actual token:

```dart
static const String huggingFaceApiToken = 'hf_abcdefghijklmnopqrstuvwxyz1234567890';
```

## Step 4: Test the Integration

1. Build and run your app
2. Navigate to AI Generation
3. Try generating an image with a simple prompt like "a beautiful sunset"
4. You should see "Free AI (Hugging Face) - Powered by FLUX.1" in the UI

## Important Notes

### Security
- **Never commit your actual API token to version control**
- Consider using environment variables for production builds
- The token will be embedded in your app, so treat it as public

### Rate Limits
- Free Hugging Face accounts have rate limits
- The app includes built-in rate limiting (10 seconds between requests)
- Consider upgrading to Hugging Face Pro for higher limits if needed

### Model Information
- Currently using: `black-forest-labs/FLUX.1-schnell`
- This is a fast, high-quality text-to-image model
- Free to use via Hugging Face Inference API

### Fallback System
- If Qwen API is configured, it takes priority
- Hugging Face is used as fallback when Qwen is not available
- Users see clear indicators of which service is being used

## Troubleshooting

### "HTTP 401: Unauthorized" Error
- Check that your token is correctly copied
- Ensure no extra spaces or characters
- Verify the token hasn't expired

### "Model is loading" Error
- This is normal for free tier - models may need to "warm up"
- Users should try again in a few moments
- Consider using a different model if this persists

### Rate Limit Errors
- Users will see a countdown message
- Adjust `huggingFaceRateLimit` in `api_config.dart` if needed
- Consider implementing user-specific rate limiting for fairness

## Alternative Models

You can change the model in `api_config.dart`:

```dart
static const String huggingFaceImageModel = 'stabilityai/stable-diffusion-xl-base-1.0';
```

Popular free models:
- `black-forest-labs/FLUX.1-schnell` (fast, high quality)
- `stabilityai/stable-diffusion-xl-base-1.0` (classic, reliable)
- `prompthero/openjourney-v4` (artistic style)

## Production Considerations

1. **Environment Variables**: Use build-time environment variables
2. **Token Rotation**: Regularly rotate your API tokens
3. **Monitoring**: Track usage to avoid hitting limits
4. **Backup**: Consider multiple tokens or providers
5. **User Education**: Inform users about free tier limitations

Your users will now have access to free AI image generation without any setup required on their end!