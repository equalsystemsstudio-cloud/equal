/*
 Script to clear mock data and content.
 Usage:
   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/clear_mock_data.js
*/
const supabaseJsImport = () => import('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('[clear_mock_data] Missing env variables.');
  console.error('Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

async function main() {
  const { createClient } = await supabaseJsImport();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  console.log('Starting cleanup...');

  // 1. Clear all live streams
  console.log('Clearing live_streams...');
  const { error: streamErr } = await supabase
    .from('live_streams')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000'); // Delete all rows
  
  if (streamErr) console.error('Error clearing streams:', streamErr.message);
  else console.log('Streams cleared.');

  // 2. Clear all posts
  console.log('Clearing all posts...');
  const { error: postErr } = await supabase
    .from('posts')
    .delete()
    .neq('id', '00000000-0000-0000-0000-000000000000'); // Delete all rows

  if (postErr) console.error('Error clearing posts:', postErr.message);
  else console.log('Posts cleared.');

  // 3. Delete mock users
  console.log('Finding mock users...');
  const { data: mockUsers, error: uErr } = await supabase
    .from('users')
    .select('id, username')
    .ilike('username', 'mock_%');

  if (uErr) {
    console.error('Error finding mock users:', uErr.message);
  } else if (mockUsers && mockUsers.length > 0) {
    console.log(`Found ${mockUsers.length} mock users. Deleting...`);
    
    // Delete from auth.users (requires service role key)
    // Deleting from auth.users usually cascades to public.users if set up, 
    // or we delete from public.users manually.
    
    for (const user of mockUsers) {
      const { error: delErr } = await supabase.auth.admin.deleteUser(user.id);
      if (delErr) {
        console.error(`Failed to delete auth user ${user.username} (${user.id}):`, delErr.message);
      } else {
        // console.log(`Deleted user ${user.username}`);
      }
    }
    console.log('Mock users deleted from Auth.');
    
    // Clean up public.users just in case cascade didn't catch it
    const ids = mockUsers.map(u => u.id);
    const { error: pubErr } = await supabase
      .from('users')
      .delete()
      .in('id', ids);
      
    if (pubErr) console.error('Error deleting public users:', pubErr.message);
    else console.log('Mock users deleted from public table.');
    
  } else {
    console.log('No mock users found.');
  }

  console.log('Cleanup complete.');
}

main().catch(e => {
  console.error('Fatal error:', e);
  process.exit(1);
});
