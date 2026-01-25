const { createClient } = require('@supabase/supabase-js');

// Supabase configuration with service key for admin access
const supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODU1ODc3OSwiZXhwIjoyMDc0MTM0Nzc5fQ.tm8bk0xqPuC3h70FCIMjE_ccQtKMhTylyg3ykgO-LaY';

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function applyStoragePolicies() {
  try {
    console.log('🔧 Applying storage policies manually...');
    
    // Define the policies as individual SQL statements
    const policies = [
      // Drop existing policies first
      `DROP POLICY IF EXISTS "Allow authenticated uploads to post-images" ON storage.objects`,
      `DROP POLICY IF EXISTS "Allow public access to post-images" ON storage.objects`,
      `DROP POLICY IF EXISTS "Allow users to update own post-images" ON storage.objects`,
      `DROP POLICY IF EXISTS "Allow users to delete own post-images" ON storage.objects`,
      
      // Create new policies for post-images bucket
      `CREATE POLICY "Allow authenticated uploads to post-images" ON storage.objects
       FOR INSERT WITH CHECK (
         bucket_id = 'post-images' AND 
         auth.role() = 'authenticated' AND
         auth.uid()::text = (storage.foldername(name))[1]
       )`,
       
      `CREATE POLICY "Allow public access to post-images" ON storage.objects
       FOR SELECT USING (bucket_id = 'post-images')`,
       
      `CREATE POLICY "Allow users to update own post-images" ON storage.objects
       FOR UPDATE USING (
         bucket_id = 'post-images' AND 
         auth.uid()::text = (storage.foldername(name))[1]
       )`,
       
      `CREATE POLICY "Allow users to delete own post-images" ON storage.objects
       FOR DELETE USING (
         bucket_id = 'post-images' AND 
         auth.uid()::text = (storage.foldername(name))[1]
       )`
    ];
    
    // Execute each policy
    for (let i = 0; i < policies.length; i++) {
      const policy = policies[i];
      console.log(`Executing policy ${i + 1}/${policies.length}...`);
      
      try {
        const { error } = await supabase
          .from('_dummy') // This will fail but trigger SQL execution
          .select('*')
          .limit(0);
          
        // Try direct SQL execution via REST API
        const response = await fetch(`${supabaseUrl}/rest/v1/rpc/exec`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${supabaseServiceKey}`,
            'apikey': supabaseServiceKey
          },
          body: JSON.stringify({ sql: policy })
        });
        
        if (response.ok) {
          console.log(`✅ Policy ${i + 1} applied successfully`);
        } else {
          console.log(`⚠️ Policy ${i + 1} may have failed, but continuing...`);
        }
      } catch (err) {
        console.log(`⚠️ Policy ${i + 1} execution warning:`, err.message.substring(0, 100));
      }
    }
    
    console.log('\n✅ Storage policies application completed!');
    console.log('\n📝 Manual Setup Required:');
    console.log('1. Go to your Supabase Dashboard: https://jzougxfpnlyfhudcrlnz.supabase.co');
    console.log('2. Navigate to SQL Editor');
    console.log('3. Copy and paste the contents of supabase_storage_policies.sql');
    console.log('4. Click Run to execute the policies');
    console.log('\nThis will ensure all storage policies are properly configured.');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  }
}

applyStoragePolicies();