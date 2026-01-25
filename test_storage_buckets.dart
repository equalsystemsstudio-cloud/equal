// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lib/config/supabase_config.dart';

Future<void> main() async {
  print('Testing Supabase Storage Buckets...');
  
  try {
    // Initialize Supabase
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    
    final supabase = Supabase.instance.client;
    print('✅ Supabase initialized successfully');
    
    // Test bucket access
    final buckets = [
      SupabaseConfig.profileImagesBucket,
      SupabaseConfig.postImagesBucket,
      SupabaseConfig.postVideosBucket,
      SupabaseConfig.postAudioBucket,
      SupabaseConfig.thumbnailsBucket,
    ];
    
    for (String bucket in buckets) {
      try {
        // Try to list files in bucket (this will fail if bucket doesn't exist)
        await supabase.storage.from(bucket).list();
        print('✅ Bucket "$bucket" exists and is accessible');
      } catch (e) {
        print('❌ Bucket "$bucket" error: $e');
      }
    }
    
    // Test a simple upload to profile-images bucket
    print('\nTesting file upload...');
    try {
      // Create a simple 1x1 pixel PNG
      final testImageBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
        0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x5C, 0xC2, 0x8A, 0x8B, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ]);
      
      final testFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.png';
      
      // Try to upload to profile-images bucket
      await supabase.storage
          .from(SupabaseConfig.profileImagesBucket)
          .uploadBinary('test/$testFileName', testImageBytes);
      
      print('✅ Test upload successful!');
      
      // Get public URL
      final publicUrl = supabase.storage
          .from(SupabaseConfig.profileImagesBucket)
          .getPublicUrl('test/$testFileName');
      
      print('✅ Public URL generated: $publicUrl');
      
      // Clean up test file
      await supabase.storage
          .from(SupabaseConfig.profileImagesBucket)
          .remove(['test/$testFileName']);
      
      print('✅ Test file cleaned up');
      
    } catch (e) {
      print('❌ Upload test failed: $e');
      print('This likely means storage policies are not set up correctly.');
    }
    
  } catch (e) {
    print('❌ Supabase initialization failed: $e');
  }
  
  print('\n=== Storage Test Complete ===');
}