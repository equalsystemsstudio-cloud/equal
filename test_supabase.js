const { createClient } = require('@supabase/supabase-js');

// Supabase configuration - Using service role key for diagnostics
const supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODU1ODc3OSwiZXhwIjoyMDc0MTM0Nzc5fQ.tm8bk0xqPuC3h70FCIMjE_ccQtKMhTylyg3ykgO-LaY';

async function runDiagnostics() {
  console.log('🔍 Starting Supabase Diagnostics...');
  
  try {
    // Initialize Supabase client with service role key
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    console.log('✅ Supabase client initialized');
    
    // Test 1: Basic Connection
    console.log('\n📡 Testing basic connection...');
    try {
      const { data, error } = await supabase.from('users').select('count').limit(1);
      if (error) {
        console.log('❌ Database connection failed:', error.message);
        console.log('   Error details:', error);
      } else {
        console.log('✅ Database connection successful');
        console.log('   Response:', data);
      }
    } catch (e) {
      console.log('❌ Database connection error:', e.message);
    }
    
    // Test 2: Storage Buckets
    console.log('\n🗂️  Testing storage buckets...');
    try {
      const { data: buckets, error } = await supabase.storage.listBuckets();
      if (error) {
        console.log('❌ Storage test failed:', error.message);
      } else {
        console.log('✅ Storage accessible');
        console.log('   Available buckets:', buckets.map(b => b.name).join(', '));
        console.log('   Total buckets found:', buckets.length);
        buckets.forEach(bucket => {
          console.log(`   - ${bucket.name} (id: ${bucket.id}, public: ${bucket.public})`);
        });
        
        const requiredBuckets = ['profile-images', 'post-images', 'post-videos'];
        const existingBuckets = new Set(buckets.map(b => b.name));
        
        requiredBuckets.forEach(bucket => {
          if (existingBuckets.has(bucket)) {
            console.log(`   ✅ ${bucket} bucket exists`);
          } else {
            console.log(`   ❌ ${bucket} bucket missing`);
          }
        });
      }
    } catch (e) {
      console.log('❌ Storage test error:', e.message);
    }
    
    // Test 3: Authentication Status
    console.log('\n🔐 Testing authentication...');
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    
    if (authError) {
      console.log('❌ Auth error:', authError.message);
    } else if (user) {
      console.log('✅ User authenticated');
      console.log('   User ID:', user.id);
      console.log('   Email:', user.email);
      
      // Test 4: User Profile Access
      console.log('\n👤 Testing user profile access...');
      try {
        const { data: profile, error } = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
        
        if (error) {
          console.log('❌ Profile access failed:', error.message);
          console.log('   Error details:', error);
        } else if (profile) {
          console.log('✅ User profile found');
          console.log('   Username:', profile.username);
          console.log('   Display name:', profile.display_name);
        } else {
          console.log('❌ User profile not found in database');
        }
      } catch (e) {
        console.log('❌ Profile access error:', e.message);
      }
      
      // Test 5: Post Creation Test
      console.log('\n📝 Testing post creation...');
      try {
        const testPost = {
          user_id: user.id,
          type: 'text',
          caption: `Test post - ${Date.now()}`,
          is_public: true,
          allow_comments: true,
          allow_duets: true,
        };
        
        const { data: result, error } = await supabase
          .from('posts')
          .insert(testPost)
          .select()
          .single();
        
        if (error) {
          console.log('❌ Post creation failed:', error.message);
          console.log('   Error details:', error);
        } else {
          console.log('✅ Post creation successful');
          console.log('   Post ID:', result.id);
          
          // Clean up test post
          const { error: deleteError } = await supabase
            .from('posts')
            .delete()
            .eq('id', result.id);
          
          if (deleteError) {
            console.log('⚠️  Failed to clean up test post:', deleteError.message);
          } else {
            console.log('✅ Test post cleaned up');
          }
        }
      } catch (e) {
        console.log('❌ Post creation error:', e.message);
      }
      
      // Test 6: Profile Update Test
      console.log('\n✏️  Testing profile update...');
      try {
        const updateData = {
          updated_at: new Date().toISOString(),
        };
        
        const { data: result, error } = await supabase
          .from('users')
          .update(updateData)
          .eq('id', user.id)
          .select()
          .single();
        
        if (error) {
          console.log('❌ Profile update failed:', error.message);
          console.log('   Error details:', error);
        } else {
          console.log('✅ Profile update successful');
          console.log('   Updated at:', result.updated_at);
        }
      } catch (e) {
        console.log('❌ Profile update error:', e.message);
      }
      
    } else {
      console.log('❌ No authenticated user');
      console.log('   This is expected if you haven\'t signed in yet');
      console.log('   Please sign in through the app first, then run this test');
    }
    
    // Test 7: RLS Policy Check
    console.log('\n🛡️  Testing RLS policies...');
    try {
      const { data: allUsers, error } = await supabase
        .from('users')
        .select('id, username')
        .limit(5);
      
      if (error) {
        console.log('❌ RLS policy test failed:', error.message);
      } else {
        console.log(`✅ RLS policies working - can access ${allUsers.length} user records`);
      }
    } catch (e) {
      console.log('❌ RLS policy test error:', e.message);
    }
    
    console.log('\n🎉 Diagnostics completed!');
    console.log('\n📋 Summary:');
    console.log('   - Check the results above for any ❌ failures');
    console.log('   - If authentication shows "No authenticated user", sign in first');
    console.log('   - Missing storage buckets need to be created in Supabase dashboard');
    console.log('   - RLS policy failures indicate permission issues');
    
    return supabase; // return client for follow-up tasks
  } catch (e) {
    console.log('💥 Fatal error during diagnostics:', e.message);
    process.exit(1);
  }
}

// Fetch recent non-null FCM tokens
async function fetchRecentFcmTokens(supabase, limit = 10) {
  console.log('\n📲 Fetching recent FCM tokens...');
  const { data, error } = await supabase
    .from('users')
    .select('id, username, display_name, fcm_token, updated_at')
    .not('fcm_token', 'is', null)
    .order('updated_at', { ascending: false })
    .limit(limit);
  if (error) {
    console.log('❌ Failed to fetch tokens:', error.message);
    return [];
  }
  const rows = data || [];
  rows.forEach((r, idx) => {
    console.log(`   [${idx}] ${r.username || r.display_name || r.id} | updated_at=${r.updated_at} | token=${(r.fcm_token || '').slice(0, 12)}...`);
  });
  if (rows.length === 0) {
    console.log('⚠️  No non-null tokens found. Make sure the recipient app is opened to refresh its FCM token.');
  }
  return rows;
}

// Invoke send_push Edge Function
async function sendPush(supabase, token, payload = {}) {
  console.log('\n📨 Invoking send_push Edge Function...');
  const defaultPayload = {
    token,
    title: payload.title || 'Equal Test Incoming Call',
    body: payload.body || 'This is a test incoming_call push from diagnostics script.',
    type: payload.type || 'incoming_call',
    data: payload.data || { source: 'diagnostics', ts: Date.now(), attempt: 1 },
  };
  // FCM HTTP v1 requires data values to be strings; coerce here
  const stringData = Object.fromEntries(
    Object.entries(defaultPayload.data).map(([k, v]) => [k, String(v)])
  );
  const { data, error } = await supabase.functions.invoke('send_push', {
    body: {
      token: defaultPayload.token,
      title: defaultPayload.title,
      body: defaultPayload.body,
      type: String(defaultPayload.type),
      data: stringData,
    },
  });
  if (error) {
    console.log('❌ Push send failed:', error.message);
    console.log('   Error details:', error);
    return null;
  }
  console.log('✅ Push send invoked');
  console.log('   Function response:', data);
  return data;
}

async function runPushFlow() {
  // Initialize client and run standard diagnostics first
  const supabase = await runDiagnostics();
  
  // Allow token override via CLI arg: node test_supabase.js --token=<FCM_TOKEN>
  const argToken = process.argv.find(a => a.startsWith('--token='));
  const argIndex = process.argv.find(a => a.startsWith('--index='));
  let token = argToken ? argToken.split('=')[1] : null;
  let recipientInfo = null;

  const desiredIndex = argIndex ? parseInt(argIndex.split('=')[1], 10) : 0;

  if (!token) {
    const candidates = await fetchRecentFcmTokens(supabase, 20);
    if (candidates.length > 0) {
      const pick = Math.min(Math.max(desiredIndex, 0), candidates.length - 1);
      recipientInfo = candidates[pick];
      token = recipientInfo.fcm_token;
      console.log(`\n👤 Selected recipient [${pick}]: ${recipientInfo.username || recipientInfo.display_name || recipientInfo.id}`);
    }
  }

  if (!token) {
    console.log('\n❌ No token available to send push.');
    console.log('   Please ensure the target device/app is opened and signed in so it refreshes and saves a current FCM token (users.fcm_token).');
    return;
  }

  // Attempt to send push
  const result = await sendPush(supabase, token, {
    title: 'Equal Test Incoming Call',
    body: 'If you see this notification, push delivery is working.',
    type: 'incoming_call',
    data: {
      recipient_id: recipientInfo?.id || 'unknown',
      attempt: 1,
    },
  });

  // Interpret FCM errors
  if (result && result.fcm_response) {
    const resp = result.fcm_response;
    if (resp.error) {
      const code = resp.error.code || resp.error.status || 'UNKNOWN';
      console.log(`\n⚠️  FCM error: ${code}`);
      console.log('   Message:', resp.error.message || JSON.stringify(resp.error));
      if (code === 'UNREGISTERED') {
        console.log('   The token is stale. Ask the recipient to open the app to refresh and save a new fcm_token.');
      } else if (code === 'INVALID_ARGUMENT') {
        console.log('   The token format is invalid. Verify you are using a valid device token.');
      } else if (code === 'NOT_FOUND') {
        console.log('   The token does not belong to the Firebase project configured in the Edge Function. Ensure the receiver app uses the same Firebase project (google-services.json) as the service account secret.');
      }
    } else {
      console.log('\n🎉 Push delivered successfully (or accepted by FCM).');
    }
  }
}

// Entry point: run diagnostics then push flow
async function main() {
  await runPushFlow();
}

main();