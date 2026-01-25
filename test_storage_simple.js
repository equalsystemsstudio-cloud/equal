const { createClient } = require('@supabase/supabase-js');

// Supabase configuration
const supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg1NTg3NzksImV4cCI6MjA3NDEzNDc3OX0.gGRkxyfWlzQC2UrX-QTSB0J4-4w5J_Q9ZezZLCaznPY';

async function testStorageBuckets() {
  console.log('🔍 Testing Supabase Storage Buckets...');
  
  try {
    // Initialize Supabase client
    const supabase = createClient(supabaseUrl, supabaseKey);
    console.log('✅ Supabase client initialized');
    
    // Test bucket access
    const buckets = [
      'profile-images',
      'post-images', 
      'post-videos',
      'post-audio',
      'thumbnails'
    ];
    
    console.log('\n📂 Checking bucket existence...');
    
    for (const bucket of buckets) {
      try {
        // Try to list files in bucket
        const { data, error } = await supabase.storage.from(bucket).list('', {
          limit: 1
        });
        
        if (error) {
          console.log(`❌ Bucket "${bucket}": ${error.message}`);
        } else {
          console.log(`✅ Bucket "${bucket}" exists and is accessible`);
        }
      } catch (e) {
        console.log(`❌ Bucket "${bucket}" error: ${e.message}`);
      }
    }
    
    // Test upload to profile-images bucket
    console.log('\n📤 Testing file upload...');
    
    try {
      // Create a simple test file (1x1 pixel PNG)
      const testImageBuffer = Buffer.from([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
        0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x01, 0x5C, 0xC2, 0x8A, 0x8B, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
      ]);
      
      const testFileName = `test/upload_test_${Date.now()}.png`;
      
      // Try to upload to profile-images bucket
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('profile-images')
        .upload(testFileName, testImageBuffer, {
          contentType: 'image/png'
        });
      
      if (uploadError) {
        console.log(`❌ Upload failed: ${uploadError.message}`);
        console.log('   This likely means:');
        console.log('   1. Storage buckets don\'t exist, OR');
        console.log('   2. Storage policies are not configured, OR');
        console.log('   3. Authentication is required but not provided');
      } else {
        console.log('✅ Test upload successful!');
        
        // Get public URL
        const { data: urlData } = supabase.storage
          .from('profile-images')
          .getPublicUrl(testFileName);
        
        console.log(`✅ Public URL: ${urlData.publicUrl}`);
        
        // Clean up test file
        const { error: deleteError } = await supabase.storage
          .from('profile-images')
          .remove([testFileName]);
        
        if (!deleteError) {
          console.log('✅ Test file cleaned up');
        }
      }
      
    } catch (e) {
      console.log(`❌ Upload test failed: ${e.message}`);
    }
    
  } catch (e) {
    console.log(`❌ Supabase initialization failed: ${e.message}`);
  }
  
  console.log('\n=== Storage Test Complete ===');
}

// Run the test
testStorageBuckets().catch(console.error);