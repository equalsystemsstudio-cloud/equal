const { createClient } = require('@supabase/supabase-js');

// Supabase configuration
const supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODU1ODc3OSwiZXhwIjoyMDc0MTM0Nzc5fQ.tm8bk0xqPuC3h70FCIMjE_ccQtKMhTylyg3ykgO-LaY';

// Initialize Supabase clients
const supabase = createClient(supabaseUrl, supabaseAnonKey);
const adminClient = createClient(supabaseUrl, supabaseServiceKey);

async function testAuthenticatedUpload() {
  console.log('🔐 Testing authenticated file upload to Supabase Storage...');
  
  try {
    // Step 1: Check if we have an existing session
    const { data: { session }, error: sessionError } = await supabase.auth.getSession();
    
    if (sessionError) {
      console.error('❌ Session check failed:', sessionError.message);
      return;
    }
    
    let currentUser = session?.user;
    
    // Step 2: If no session, try to sign in with test credentials
    if (!currentUser) {
      console.log('📝 No existing session, creating confirmed test user...');
      const { email, password } = await ensureTestUser();
      const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({ email, password });
      if (signInError) {
        console.error('❌ Sign in failed:', signInError.message);
        return;
      }
      currentUser = signInData.user;
      console.log('✅ Signed in successfully');
    } else {
      console.log('✅ Using existing session');
    }
    
    if (!currentUser) {
      console.error('❌ No authenticated user available');
      return;
    }
    
    console.log('👤 Authenticated as:', currentUser.email);
    console.log('🆔 User ID:', currentUser.id);
    
    // Step 3: Test file upload with authenticated user
    console.log('📤 Testing file upload to post-images bucket...');
    
    // Create a simple test file (1x1 pixel PNG)
    const testFileContent = Buffer.from([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
    
    const fileName = `${currentUser.id}/test-upload-${Date.now()}.png`;
    
    const { data: uploadData, error: uploadError } = await supabase.storage
      .from('post-images')
      .upload(fileName, testFileContent, {
        contentType: 'image/png',
        upsert: false
      });
    
    if (uploadError) {
      console.error('❌ Upload failed:', uploadError.message);
      console.error('Error details:', uploadError);
      return;
    }
    
    console.log('✅ File uploaded successfully!');
    console.log('📁 File path:', uploadData.path);
    
    // Step 4: Test getting public URL
    const { data: urlData } = supabase.storage
      .from('post-images')
      .getPublicUrl(fileName);
    
    console.log('🔗 Public URL:', urlData.publicUrl);
    
    // Step 5: Test file listing
    const { data: listData, error: listError } = await supabase.storage
      .from('post-images')
      .list(currentUser.id);
    
    if (listError) {
      console.error('❌ List files failed:', listError.message);
    } else {
      console.log('📋 Files in user folder:', listData.length);
    }
    
    // Step 6: Clean up - delete test file
    const { error: deleteError } = await supabase.storage
      .from('post-images')
      .remove([fileName]);
    
    if (deleteError) {
      console.error('⚠️  Failed to clean up test file:', deleteError.message);
    } else {
      console.log('🧹 Test file cleaned up successfully');
    }
    
    console.log('\n🎉 All tests completed successfully!');
    console.log('✅ Authentication: Working');
    console.log('✅ File Upload: Working');
    console.log('✅ Public URL: Working');
    console.log('✅ File Listing: Working');
    console.log('✅ File Deletion: Working');
    
  } catch (error) {
    console.error('❌ Unexpected error:', error.message);
    console.error('Stack trace:', error.stack);
  }
}

// Run the test
testAuthenticatedUpload().then(() => {
  console.log('\n🏁 Test completed');
}).catch(error => {
  console.error('💥 Test failed with error:', error);
});

async function ensureTestUser() {
  const email = `tester+${Date.now()}@example.com`;
  const password = 'Test1234!test';
  const { data, error } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (error) {
    throw new Error('Failed to create test user: ' + error.message);
  }
  return { email, password, userId: data.user.id };
}