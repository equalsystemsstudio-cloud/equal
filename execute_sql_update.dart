import 'package:supabase/supabase.dart';

// Supabase configuration
const String supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY';

void main() async {
  try {
    // Initialize Supabase client
    final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    
    print('Attempting to update statuses table...');
    
    // Try to add columns using direct SQL execution
    try {
      final result = await client.rpc('exec_sql', params: {
        'query': '''
          ALTER TABLE public.statuses 
          ADD COLUMN IF NOT EXISTS is_ai_generated boolean DEFAULT false,
          ADD COLUMN IF NOT EXISTS ai_prompt text,
          ADD COLUMN IF NOT EXISTS ai_model text;
        '''
      });
      print('✅ Added AI columns successfully: $result');
    } catch (e) {
      print('⚠️  Could not add columns via RPC: $e');
      
      // Try alternative approach - check if columns exist
      try {
        await client.from('statuses').select('is_ai_generated').limit(1);
        print('✅ AI columns already exist');
      } catch (e2) {
        print('❌ AI columns do not exist and could not be added');
        print('Manual SQL execution required.');
      }
    }
    
    print('\n🎉 Database check completed!');
    print('Testing status posting...');
    
    // Test if we can now post a status
    try {
      final testResult = await client.from('statuses').insert({
        'user_id': '00000000-0000-0000-0000-000000000000', // dummy user id for test
        'type': 'text',
        'text_content': 'Test status',
        'bg_color': '#FF5722',
        'is_ai_generated': false,
        'expires_at': DateTime.now().add(Duration(hours: 24)).toIso8601String(),
      }).select();
      
      print('✅ Status posting test successful!');
      
      // Clean up test data
      if (testResult.isNotEmpty) {
        await client.from('statuses').delete().eq('id', testResult[0]['id']);
        print('✅ Test data cleaned up');
      }
      
    } catch (e) {
      print('❌ Status posting test failed: $e');
      if (e.toString().contains('is_ai_generated')) {
        print('\n📋 MANUAL ACTION REQUIRED:');
        print('Please go to: https://jzougxfpnlyfhudcrlnz.supabase.co');
        print('Navigate to SQL Editor and execute the contents of update_statuses_table.sql');
      }
    }
    
  } catch (e) {
    print('❌ Error: $e');
    print('\n📋 MANUAL ACTION REQUIRED:');
    print('Please go to: https://jzougxfpnlyfhudcrlnz.supabase.co');
    print('Navigate to SQL Editor and execute the contents of update_statuses_table.sql');
  }
}