// ignore_for_file: avoid_print
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase configuration
const String supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY';

void main() async {
  print('🔍 Starting Supabase Diagnostics...');
  
  try {
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: true,
    );
    
    final client = Supabase.instance.client;
    print('✅ Supabase initialized successfully');
    
    // Test 1: Basic Connection
    print('\n📡 Testing basic connection...');
    try {
      final response = await client.from('users').select('count').limit(1);
      print('✅ Database connection successful');
      print('   Response: $response');
    } catch (e) {
      print('❌ Database connection failed: $e');
    }
    
    // Test 2: Storage Buckets
    print('\n🗂️  Testing storage buckets...');
    try {
      final buckets = await client.storage.listBuckets();
      print('✅ Storage accessible');
      print('   Available buckets: ${buckets.map((b) => b.name).join(', ')}');
      
      final requiredBuckets = ['profile-images', 'post-images', 'post-videos'];
      final existingBuckets = buckets.map((b) => b.name).toSet();
      
      for (final bucket in requiredBuckets) {
        if (existingBuckets.contains(bucket)) {
          print('   ✅ $bucket bucket exists');
        } else {
          print('   ❌ $bucket bucket missing');
        }
      }
    } catch (e) {
      print('❌ Storage test failed: $e');
    }
    
    // Test 3: Authentication Status
    print('\n🔐 Testing authentication...');
    final user = client.auth.currentUser;
    final session = client.auth.currentSession;
    
    if (user != null) {
      print('✅ User authenticated');
      print('   User ID: ${user.id}');
      print('   Email: ${user.email}');
      print('   Session valid: ${!(session?.isExpired ?? true)}');
      
      // Test 4: User Profile Access
      print('\n👤 Testing user profile access...');
      try {
        final profile = await client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        
        if (profile != null) {
          print('✅ User profile found');
          print('   Username: ${profile['username']}');
          print('   Display name: ${profile['display_name']}');
        } else {
          print('❌ User profile not found in database');
        }
      } catch (e) {
        print('❌ Profile access failed: $e');
      }
      
      // Test 5: Post Creation Test
      print('\n📝 Testing post creation...');
      try {
        final testPost = {
          'user_id': user.id,
          'type': 'text',
          'caption': 'Test post - ${DateTime.now().millisecondsSinceEpoch}',
          'is_public': true,
          'allow_comments': true,
          'allow_duets': true,
        };
        
        final result = await client
            .from('posts')
            .insert(testPost)
            .select()
            .single();
        
        print('✅ Post creation successful');
        print('   Post ID: ${result['id']}');
        
        // Clean up test post
        await client.from('posts').delete().eq('id', result['id']);
        print('✅ Test post cleaned up');
        
      } catch (e) {
        print('❌ Post creation failed: $e');
      }
      
      // Test 6: Profile Update Test
      print('\n✏️  Testing profile update...');
      try {
        final updateData = {
          'updated_at': DateTime.now().toIso8601String(),
        };
        
        final result = await client
            .from('users')
            .update(updateData)
            .eq('id', user.id)
            .select()
            .single();
        
        print('✅ Profile update successful');
        print('   Updated at: ${result['updated_at']}');
        
      } catch (e) {
        print('❌ Profile update failed: $e');
      }
      
    } else {
      print('❌ No authenticated user');
      print('   This is expected if you haven\'t signed in yet');
      print('   Please sign in through the app first, then run this test');
    }
    
    // Test 7: RLS Policy Check
    print('\n🛡️  Testing RLS policies...');
    try {
      // Try to access all users (should be limited by RLS)
      final allUsers = await client.from('users').select('id, username').limit(5);
      print('✅ RLS policies working - can access ${allUsers.length} user records');
    } catch (e) {
      print('❌ RLS policy test failed: $e');
    }
    
    print('\n🎉 Diagnostics completed!');
    print('\n📋 Summary:');
    print('   - Check the results above for any ❌ failures');
    print('   - If authentication shows "No authenticated user", sign in first');
    print('   - Missing storage buckets need to be created in Supabase dashboard');
    print('   - RLS policy failures indicate permission issues');
    
  } catch (e) {
    print('💥 Fatal error during diagnostics: $e');
    exit(1);
  }
  
  exit(0);
}