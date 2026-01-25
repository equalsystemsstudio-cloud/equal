import 'package:supabase_flutter/supabase_flutter.dart';

// Supabase configuration
const String supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY';

void main() async {
  print('🔧 Executing missing database functions...');
  
  try {
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    
    final client = Supabase.instance.client;
    print('✅ Supabase client initialized');
    
    // Try to execute the increment function SQL
    const incrementFunctionSql = '''
    CREATE OR REPLACE FUNCTION public.increment_post_comments_count(post_id UUID)
    RETURNS void AS \$\$
    BEGIN
      UPDATE public.posts 
      SET comments_count = COALESCE(comments_count, 0) + 1,
          updated_at = NOW()
      WHERE id = post_id;
    END;
    \$\$ LANGUAGE plpgsql SECURITY DEFINER;
    ''';
    
    const decrementFunctionSql = '''
    CREATE OR REPLACE FUNCTION public.decrement_post_comments_count(post_id UUID)
    RETURNS void AS \$\$
    BEGIN
      UPDATE public.posts 
      SET comments_count = GREATEST(COALESCE(comments_count, 0) - 1, 0),
          updated_at = NOW()
      WHERE id = post_id;
    END;
    \$\$ LANGUAGE plpgsql SECURITY DEFINER;
    ''';
    
    const grantPermissionsSql = '''
    GRANT EXECUTE ON FUNCTION public.increment_post_comments_count(UUID) TO authenticated;
    GRANT EXECUTE ON FUNCTION public.decrement_post_comments_count(UUID) TO authenticated;
    ''';
    
    print('📝 Attempting to create increment function...');
    try {
      await client.rpc('exec', params: {'sql': incrementFunctionSql});
      print('✅ Increment function created successfully');
    } catch (e) {
      print('❌ Failed to create increment function: $e');
      print('   This might be expected - functions may need to be created via SQL Editor');
    }
    
    print('📝 Attempting to create decrement function...');
    try {
      await client.rpc('exec', params: {'sql': decrementFunctionSql});
      print('✅ Decrement function created successfully');
    } catch (e) {
      print('❌ Failed to create decrement function: $e');
    }
    
    print('🔐 Attempting to grant permissions...');
    try {
      await client.rpc('exec', params: {'sql': grantPermissionsSql});
      print('✅ Permissions granted successfully');
    } catch (e) {
      print('❌ Failed to grant permissions: $e');
    }
    
    // Test if the function exists now
    print('🧪 Testing if increment function exists...');
    try {
      // Try to call the function with a dummy UUID to see if it exists
      await client.rpc('increment_post_comments_count', params: {
        'post_id': '00000000-0000-0000-0000-000000000000'
      });
      print('✅ Function exists and is callable');
    } catch (e) {
      print('❌ Function test failed: $e');
      print('');
      print('🔧 MANUAL SETUP REQUIRED:');
      print('Please go to your Supabase dashboard at:');
      print('https://jzougxfpnlyfhudcrlnz.supabase.co');
      print('');
      print('Navigate to SQL Editor and execute the contents of:');
      print('add_missing_functions.sql');
      print('');
      print('This will create the required database functions.');
    }
    
  } catch (e) {
    print('❌ Setup failed: $e');
  }
}