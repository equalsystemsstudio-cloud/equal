// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

// Test script to debug image upload issues
void main() async {
  // Initialize Supabase (you'll need to add your credentials)
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
  );

  final supabase = Supabase.instance.client;
  
  // Test authentication
  print('Current user: ${supabase.auth.currentUser?.id}');
  
  if (supabase.auth.currentUser == null) {
    print('❌ User not authenticated. Please sign in first.');
    return;
  }
  
  try {
    // Test 1: Check if bucket exists
    print('\n🔍 Testing bucket access...');
    
    final buckets = await supabase.storage.listBuckets();
    final postImagesBucket = buckets.where((b) => b.name == 'post-images').firstOrNull;
    
    if (postImagesBucket == null) {
      print('❌ post-images bucket not found!');
      print('Available buckets: ${buckets.map((b) => b.name).join(', ')}');
      return;
    } else {
      print('✅ post-images bucket found');
      print('Bucket details: $postImagesBucket');
    }
    
    // Test 2: Try to upload a simple test file
    print('\n📤 Testing file upload...');
    
    final testData = Uint8List.fromList([1, 2, 3, 4, 5]); // Simple test data
    final fileName = 'test/${DateTime.now().millisecondsSinceEpoch}.txt';
    
    try {
      final uploadResponse = await supabase.storage
          .from('post-images')
          .uploadBinary(fileName, testData);
      
      print('✅ Upload successful: $uploadResponse');
      
      // Test 3: Get public URL
      final publicUrl = supabase.storage
          .from('post-images')
          .getPublicUrl(fileName);
      
      print('✅ Public URL: $publicUrl');
      
      // Test 4: Clean up - delete test file
      await supabase.storage
          .from('post-images')
          .remove([fileName]);
      
      print('✅ Test file cleaned up');
      
    } catch (uploadError) {
      print('❌ Upload failed: $uploadError');
      
      if (uploadError.toString().contains('403')) {
        print('\n🔧 This is likely a Row Level Security (RLS) policy issue.');
        print('Please ensure you have applied the storage policies from supabase_storage_policies.sql');
        print('\nSteps to fix:');
        print('1. Go to your Supabase Dashboard');
        print('2. Navigate to SQL Editor');
        print('3. Copy and paste the contents of supabase_storage_policies.sql');
        print('4. Click Run to execute the policies');
      }
      
      return;
    }
    
  } catch (e) {
    print('❌ Test failed: $e');
  }
}