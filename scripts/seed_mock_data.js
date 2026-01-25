/*
 Seed mock users and posts for Equal app, cross-platform compatible.

 Usage:
   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/seed_mock_data.js --count=100

 Notes:
 - Uses Supabase service role to create auth users and insert posts directly.
 - All media use public external URLs to avoid device-specific storage issues.
 - Hashtags include "Mock-Experiment" so the UI badge appears on Web, Phone, and Windows.
*/

// Use dynamic import for ESM-only supabase-js to avoid CJS import errors
const supabaseJsImport = () => import('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error('[seed_mock_data] Missing env variables. Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
  console.error('Example (PowerShell):');
  console.error('  $env:SUPABASE_URL = "https://YOUR_PROJECT_REF.supabase.co"');
  console.error('  $env:SUPABASE_SERVICE_ROLE_KEY = "YOUR_SERVICE_ROLE_KEY"');
  console.error('  node scripts/seed_mock_data.js --count=100');
  process.exit(1);
}

let supabase;

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick(arr) {
  return arr[randInt(0, arr.length - 1)];
}

// Diversified niches for realistic, non-copyright stock content similar to TikTok styles
const niches = [
  'fitness', 'cooking', 'travel', 'fashion', 'technology', 'pets', 'dance', 'sports', 'comedy', 'beauty',
  'gaming', 'education', 'finance', 'photography', 'automotive', 'music', 'nature', 'food', 'art', 'DIY'
];

function nicheForUser(userIdentifier) {
  const s = String(userIdentifier);
  const hash = [...s].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 0);
  return niches[hash % niches.length];
}

function nicheImage(niche, i) {
  // Unsplash Source provides random images for a given query; add sig to avoid caching collisions
  return `https://source.unsplash.com/random/1080x1920?${encodeURIComponent(niche)}&sig=${i}`;
}

function capitalize(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

function mkAvatar(i) {
  const idx = (i % 96) + 1;
  const gender = i % 2 === 0 ? 'men' : 'women';
  return `https://randomuser.me/api/portraits/${gender}/${idx}.jpg`;
}

const imageSeeds = [
  // Replaced with niche-based Unsplash Source for realistic diversity
  (n) => nicheImage(niches[n % niches.length], n),
];

const videoSamples = [
  // Keep reliable CC-licensed samples; add more later if needed
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
];

const audioSamples = [
  'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
  'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
  'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
];

function mkHashtags(n) {
  const pool = ['Mock-Experiment', 'demo', 'beta', 'fun', 'trending', 'music', 'photo'];
  // Ensure badge trigger
  const tags = new Set(['Mock-Experiment']);
  while (tags.size < 3) tags.add(pick(pool));
  return Array.from(tags);
}

function mkPrompt(n) {
  const prompts = [
    'A surreal cityscape at dawn in watercolor style',
    'Futuristic portrait with neon accents',
    'Minimalist geometric shapes with soft gradients',
    'Pastel forest scene with misty atmosphere',
  ];
  return pick(prompts);
}

function mkDisplayName(i) {
  const names = ['Ava', 'Liam', 'Mia', 'Noah', 'Zoe', 'Ethan', 'Ivy', 'Lucas', 'Nora', 'Leo'];
  return `${pick(names)} Mock ${i}`;
}

async function createAuthUser(i) {
  const email = `mock${String(i).padStart(4, '0')}@example.com`;
  const password = 'Mock1234!'; // Compatible across web/mobile/desktop
  const username = `mock_${String(i).padStart(4, '0')}`;
  const displayName = mkDisplayName(i);

  const { data, error } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      username,
      display_name: displayName,
    },
  });
  if (error) throw new Error(`createUser failed for ${email}: ${error.message}`);
  const userId = data.user?.id;
  if (!userId) throw new Error(`createUser returned no user.id for ${email}`);
  return { userId, email, username, displayName };
}

async function waitForProfile(userId, retries = 10, delayMs = 400) {
  for (let r = 0; r < retries; r++) {
    const { data, error } = await supabase
      .from('users')
      .select('id, username, display_name')
      .eq('id', userId)
      .maybeSingle();
    if (!error && data) return data;
    await new Promise((res) => setTimeout(res, delayMs));
  }
  throw new Error(`Profile not materialized for user ${userId} after ${retries} retries`);
}

async function insertPost(userId, type, idxForMedia, niche) {
  const base = {
    user_id: userId,
    type,
    caption: '',
    is_public: true,
    allow_comments: true,
    allow_duets: true,
    hashtags: mkHashtags(idxForMedia),
    is_ai_generated: false,
  };

  const nicheLabel = capitalize(niche ?? nicheForUser(userId));

  if (type === 'text') {
    base.caption = `${nicheLabel} thoughts ${idxForMedia} — #Mock-Experiment`;
  } else if (type === 'image') {
    base.caption = `${nicheLabel} photo ${idxForMedia} — #Mock-Experiment`;
    const chosenNiche = niche ?? nicheForUser(userId);
    base.media_url = nicheImage(chosenNiche, idxForMedia);
  } else if (type === 'video') {
    base.caption = `${nicheLabel} clip ${idxForMedia} — #Mock-Experiment`;
    base.media_url = pick(videoSamples);
  } else if (type === 'audio') {
    base.caption = `${nicheLabel} audio ${idxForMedia} — #Mock-Experiment`;
    base.media_url = pick(audioSamples);
  }

  // Add an AI-generated image variant occasionally
  if (type === 'image' && idxForMedia % 4 === 0) {
    base.is_ai_generated = true;
    base.ai_prompt = mkPrompt(idxForMedia);
    base.ai_model = 'stable-diffusion-v1';
    base.ai_metadata = { source: 'seed_script', version: '1.0', seed: idxForMedia, niche: nicheLabel };
  }

  const { data, error } = await supabase
    .from('posts')
    .insert(base)
    .select()
    .single();
  if (error) throw new Error(`insertPost failed: ${error.message}`);
  return data;
}

async function createPostsForUser(userId, niche) {
  const types = ['text', 'image', 'video', 'audio'];
  const countPerUser = 4; // one of each type
  const out = [];
  for (let i = 0; i < countPerUser; i++) {
    const p = await insertPost(userId, types[i % types.length], i + 1, niche);
    out.push(p);
  }
  return out;
}

async function updateProfileAvatar(userId, avatarUrl) {
  const { error } = await supabase
    .from('users')
    .update({ avatar_url: avatarUrl })
    .eq('id', userId);
  if (error) throw new Error(`updateProfileAvatar failed: ${error.message}`);
}

async function updateExistingPostsForUser(userId, niche) {
  // Fetch up to 10 existing posts for this user
  const { data: posts, error } = await supabase
    .from('posts')
    .select('id, type, media_url, caption')
    .eq('user_id', userId)
    .limit(10);
  if (error) throw new Error(`Failed to fetch posts for user ${userId}: ${error.message}`);
  if (!posts || posts.length === 0) return;

  const nicheLabel = capitalize(niche);
  for (let i = 0; i < posts.length; i++) {
    const p = posts[i];
    const updates = {};
    if (p.type === 'text') {
      updates.caption = `${nicheLabel} update ${i + 1} — #Mock-Experiment`;
    } else if (p.type === 'image') {
      updates.caption = `${nicheLabel} photo refresh ${i + 1} — #Mock-Experiment`;
      updates.media_url = nicheImage(niche, i + 100); // use different sig to avoid collisions
    } else if (p.type === 'video') {
      updates.caption = `${nicheLabel} clip refresh ${i + 1} — #Mock-Experiment`;
      // keep existing media_url to avoid heavy bandwidth; optional: rotate samples
    } else if (p.type === 'audio') {
      updates.caption = `${nicheLabel} audio refresh ${i + 1} — #Mock-Experiment`;
    }
    if (Object.keys(updates).length > 0) {
      const { error: upErr } = await supabase
        .from('posts')
        .update(updates)
        .eq('id', p.id);
      if (upErr) {
        console.error(`    ⚠️ Post update failed for ${p.id}: ${upErr.message}`);
      }
      await new Promise((res) => setTimeout(res, 50));
    }
  }
}

async function initSupabaseClient() {
  const { createClient } = await supabaseJsImport();
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

async function pruneMockUsers(targetCount) {
  const { data: users, error } = await supabase
    .from('users')
    .select('id, username')
    .ilike('username', 'mock_%')
    .order('username', { ascending: true })
    .limit(2000);
  if (error) throw new Error(`Failed to fetch mock users for prune: ${error.message}`);
  const total = users?.length ?? 0;
  if (total <= targetCount) {
    console.log(`[seed_mock_data] Prune skipped: total=${total} <= target=${targetCount}`);
    return;
  }
  const toDelete = users.slice(targetCount);
  console.log(`[seed_mock_data] Pruning mock users: deleting ${toDelete.length} to reach ${targetCount}`);
  let idx = 0;
  for (const u of toDelete) {
    try {
      await supabase.from('posts').delete().eq('user_id', u.id);
      await supabase.from('users').delete().eq('id', u.id);
      const { error: delErr } = await supabase.auth.admin.deleteUser(u.id);
      if (delErr) {
        console.error(`  ⚠️ Auth deletion failed for ${u.username}: ${delErr.message}`);
      }
      idx++;
      if (idx % 20 === 0) {
        console.log(`  Prune progress: ${idx}/${toDelete.length} users removed`);
      }
      await new Promise((res) => setTimeout(res, 100));
    } catch (e) {
      console.error(`  ⚠️ Prune failed for user ${u.username}: ${e.message}`);
    }
  }
  console.log('[seed_mock_data] Prune completed.');
}

async function diversifyExistingMockUsers() {
  const { data: users, error } = await supabase
    .from('users')
    .select('id, username, avatar_url')
    .ilike('username', 'mock_%')
    .limit(1000);
  if (error) throw new Error(`Failed to fetch mock users: ${error.message}`);

  if (!users || users.length === 0) {
    console.log('[seed_mock_data] No existing mock users found to augment.');
    return;
  }

  let idx = 1;
  for (const u of users) {
    try {
      // Set avatar if missing
      const avatarUrl = mkAvatar(idx);
      if (!u.avatar_url || String(u.avatar_url).length === 0) {
        await updateProfileAvatar(u.id, avatarUrl);
      }
      // Derive niche and update existing posts for diversity
      const niche = nicheForUser(u.id);
      await updateExistingPostsForUser(u.id, niche);
      // Add 2 extra posts in the user's niche to increase variety
      await insertPost(u.id, 'image', 1, niche);
      await insertPost(u.id, 'video', 2, niche);
      if (idx % 25 === 0) {
        console.log(`  Augment progress: ${idx}/${users.length} users updated`);
      }
      idx++;
      await new Promise((res) => setTimeout(res, 100));
    } catch (e) {
      console.error(`  ⚠️  Augment failed for user ${u.username}: ${e.message}`);
    }
  }
}

async function main() {
  const arg = process.argv.find((a) => a.startsWith('--count='));
  const augmentExisting = process.argv.some((a) => a === '--augment-existing');
  const pruneArg = process.argv.find((a) => a.startsWith('--prune-to='));
  const pruneTarget = pruneArg ? parseInt(pruneArg.split('=')[1], 10) : null;
  const totalUsers = arg ? parseInt(arg.split('=')[1], 10) : 50;

  // Initialize Supabase client via dynamic import to support Node on Windows and CI
  supabase = await initSupabaseClient();

  if (pruneTarget !== null && !Number.isNaN(pruneTarget)) {
    console.log(`[seed_mock_data] Prune requested to ${pruneTarget} mock users`);
    await pruneMockUsers(pruneTarget);
    return;
  }

  if (augmentExisting) {
    console.log('[seed_mock_data] Augmenting existing mock users: adding avatars and diversified posts');
    await diversifyExistingMockUsers();
    console.log('[seed_mock_data] Augment completed.');
    return;
  }

  console.log(`[seed_mock_data] Starting seeding: users=${totalUsers}`);

  const created = [];
  for (let i = 1; i <= totalUsers; i++) {
    try {
      const u = await createAuthUser(i);
      // Wait until profile row exists via trigger
      await waitForProfile(u.userId);
      // Assign a profile picture
      const avatarUrl = mkAvatar(i);
      await updateProfileAvatar(u.userId, avatarUrl);
      // Pick a niche unique to this user
      const niche = niches[(i - 1) % niches.length];
      // Create posts (text, image, video, audio) in that niche
      await createPostsForUser(u.userId, niche);
      created.push(u);
      if (i % 10 === 0) {
        console.log(`  Progress: ${i}/${totalUsers} users seeded`);
      }
      // Small throttle to avoid rate limits
      await new Promise((res) => setTimeout(res, 200));
    } catch (e) {
      console.error(`  ⚠️  Failed at index ${i}: ${e.message}`);
      // Continue; best-effort seeding
    }
  }

  console.log(`[seed_mock_data] Completed. Users seeded: ${created.length}/${totalUsers}`);
  console.log('Example credentials:');
  created.slice(0, 5).forEach((u, idx) => {
    console.log(`  [${idx}] email=${u.email} password=Mock1234! username=${u.username}`);
  });
}

main().catch((e) => {
  console.error('[seed_mock_data] Fatal error:', e);
  process.exit(1);
});