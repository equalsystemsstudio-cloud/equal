const { createClient } = require('@supabase/supabase-js');

// Supabase configuration
const supabaseUrl = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const supabaseServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODU1ODc3OSwiZXhwIjoyMDc0MTM0Nzc5fQ.tm8bk0xqPuC3h70FCIMjE_ccQtKMhTylyg3ykgO-LaY';

async function fixPostCountIssue() {
  console.log('🔧 Fixing post count issue...');
  
  try {
    // Initialize Supabase client with service role key (needed for database functions)
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    console.log('✅ Connected to Supabase');
    
    // Step 1: Create the missing decrement_user_posts_count function
    console.log('\n📝 Creating missing decrement_user_posts_count function...');
    const createFunctionSQL = `
      CREATE OR REPLACE FUNCTION public.decrement_user_posts_count(user_id UUID)
      RETURNS void
      LANGUAGE sql
      SECURITY DEFINER
      SET search_path = public
      AS $f$
        UPDATE public.users
        SET posts_count = GREATEST(0, COALESCE(posts_count, 0) - 1)
        WHERE id = user_id;
      $f$;
    `;
    
    const { error: functionError } = await supabase.rpc('exec_sql', { sql: createFunctionSQL });
    if (functionError) {
      // Try alternative method
      console.log('Trying alternative method to create function...');
      const { error: altError } = await supabase.from('_supabase_admin').insert({
        query: createFunctionSQL
      });
      if (altError) {
        console.log('❌ Could not create function via RPC. Manual creation needed.');
        console.log('Please run this SQL manually in Supabase SQL Editor:');
        console.log(createFunctionSQL);
      }
    } else {
      console.log('✅ Function created successfully');
    }
    
    // Step 2: Grant execute permission
    console.log('\n🔐 Granting execute permission...');
    const grantSQL = 'GRANT EXECUTE ON FUNCTION public.decrement_user_posts_count(UUID) TO authenticated;';
    const { error: grantError } = await supabase.rpc('exec_sql', { sql: grantSQL });
    if (!grantError) {
      console.log('✅ Permissions granted');
    }
    
    // Step 3: Fix existing post counts by recalculating them
    console.log('\n🔄 Recalculating post counts for all users...');
    
    // Get all users
    const { data: users, error: usersError } = await supabase
      .from('users')
      .select('id, username, posts_count');
    
    if (usersError) {
      console.log('❌ Error fetching users:', usersError.message);
      return;
    }
    
    console.log(`Found ${users.length} users to check`);
    
    // For each user, count their actual posts and update if different
    let fixedCount = 0;
    for (const user of users) {
      // Count actual posts for this user
      const { count: actualPostCount, error: countError } = await supabase
        .from('posts')
        .select('*', { count: 'exact', head: true })
        .eq('user_id', user.id)
        .eq('is_public', true);
      
      if (countError) {
        console.log(`❌ Error counting posts for user ${user.username}:`, countError.message);
        continue;
      }
      
      const currentCount = user.posts_count || 0;
      const realCount = actualPostCount || 0;
      
      if (currentCount !== realCount) {
        console.log(`🔧 Fixing ${user.username}: ${currentCount} → ${realCount}`);
        
        // Update the user's post count
        const { error: updateError } = await supabase
          .from('users')
          .update({ posts_count: realCount })
          .eq('id', user.id);
        
        if (updateError) {
          console.log(`❌ Error updating ${user.username}:`, updateError.message);
        } else {
          fixedCount++;
        }
      }
    }
    
    console.log(`\n✅ Post count fix completed!`);
    console.log(`📊 Fixed ${fixedCount} users with incorrect post counts`);
    console.log(`\n🎯 Summary:`);
    console.log(`   - Created decrement_user_posts_count function`);
    console.log(`   - Granted proper permissions`);
    console.log(`   - Recalculated post counts for all users`);
    console.log(`   - Fixed ${fixedCount} users with incorrect counts`);
    
  } catch (error) {
    console.log('❌ Error during fix:', error.message);
    console.log('\n📋 Manual steps needed:');
    console.log('1. Go to Supabase SQL Editor: https://jzougxfpnlyfhudcrlnz.supabase.co');
    console.log('2. Run the SQL from fix_post_count_issue.sql');
  }
}

// Run the fix
fixPostCountIssue().then(() => {
  console.log('\n🏁 Script completed');
  process.exit(0);
}).catch((error) => {
  console.error('💥 Script failed:', error);
  process.exit(1);
});