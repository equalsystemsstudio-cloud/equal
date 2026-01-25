# Equal App - Release Setup Guide

## Firebase Configuration

### 1. Create Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project named "equal-app-firebase"
3. Enable Google Analytics (optional)

### 2. Add Android App
1. Click "Add app" and select Android
2. Package name: `com.equal.app.equal`
3. Download `google-services.json`
4. Replace the placeholder file in `android/app/google-services.json`

### 3. Add iOS App
1. Click "Add app" and select iOS
2. Bundle ID: `com.equal.app.equal`
3. Download `GoogleService-Info.plist`
4. Replace the placeholder file in `ios/Runner/GoogleService-Info.plist`

### 4. Update Firebase Options
1. Install Firebase CLI: `npm install -g firebase-tools`
2. Run: `firebase login`
3. Run: `flutterfire configure`
4. Replace the generated `lib/firebase_options.dart` with actual values

### 5. Enable Firebase Services
- **Authentication**: Enable Email/Password and Google Sign-In
- **Cloud Messaging**: Enable for push notifications
- **Analytics**: Enable for app insights

## Android Release Setup

### 1. Generate Release Keystore
```bash
keytool -genkey -v -keystore android/equal-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias equal-release-key
```

### 2. Update Key Properties
Edit `android/key.properties` with your actual keystore information:
```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=equal-release-key
storeFile=equal-release-key.jks
```

### 3. Build Release APK
```bash
flutter build apk --release
```

### 4. Build App Bundle (for Play Store)
```bash
flutter build appbundle --release
```

## Play Store Release Checklist

### App Information
- [x] App name: Equal
- [x] Package name: com.equal.app.equal
- [x] Version: 1.0.0 (1)
- [ ] App icon (512x512 PNG)
- [ ] Feature graphic (1024x500 PNG)
- [ ] Screenshots (phone and tablet)

### Store Listing
- [ ] Short description (80 characters max)
- [ ] Full description (4000 characters max)
- [ ] Privacy Policy URL
- [ ] Terms of Service URL
- [ ] Support email

### App Content
- [ ] Content rating questionnaire
- [ ] Target audience selection
- [ ] App category: Social
- [ ] Tags and keywords

### Release Management
- [ ] Upload signed app bundle
- [ ] Set up release tracks (internal → alpha → beta → production)
- [ ] Configure rollout percentage
- [ ] Add release notes

## iOS Release Setup

### 1. Apple Developer Account
- Enroll in Apple Developer Program ($99/year)
- Create App ID: com.equal.app.equal
- Generate certificates and provisioning profiles

### 2. Build iOS Release
```bash
flutter build ios --release
```

### 3. Archive and Upload
- Open `ios/Runner.xcworkspace` in Xcode
- Archive the app
- Upload to App Store Connect

## Environment Variables

Create `.env` file in project root:
```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
FIREBASE_PROJECT_ID=equal-app-firebase
```

## Testing

### Before Release
- [ ] Test authentication flow
- [ ] Test push notifications
- [ ] Test all major features
- [ ] Test on different screen sizes
- [ ] Performance testing
- [ ] Memory leak testing

### Post Release
- [ ] Monitor crash reports
- [ ] Monitor user feedback
- [ ] Track key metrics
- [ ] Plan updates and improvements

## Support

For technical issues:
- Email: support@equal-co.com
- Documentation: [App Documentation]
- Issue Tracker: [GitHub Issues]

---

**Note**: Replace all placeholder values with actual production values before release.