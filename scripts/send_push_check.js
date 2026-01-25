// Simple push notification check using Supabase REST + Edge Function via fetch
// Usage: node scripts/send_push_check.js [--token=<FCM_TOKEN>] [--index=<N>]

const SUPABASE_URL = 'https://jzougxfpnlyfhudcrlnz.supabase.co';
// NOTE: Uses the same service key already present in test_supabase.js
const SUPABASE_SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1ODU1ODc3OSwiZXhwIjoyMDc0MTM0Nzc5fQ.tm8bk0xqPuC3h70FCIMjE_ccQtKMhTylyg3ykgO-LaY';

function parseArgs() {
  const args = process.argv.slice(2);
  const tokenArg = args.find(a => a.startsWith('--token='));
  const indexArg = args.find(a => a.startsWith('--index='));
  return {
    token: tokenArg ? tokenArg.split('=')[1] : null,
    index: indexArg ? parseInt(indexArg.split('=')[1], 10) : 0,
  };
}

async function fetchRecentFcmTokens(limit = 10) {
  const url = `${SUPABASE_URL}/rest/v1/users?select=id,username,display_name,fcm_token,updated_at&fcm_token=not.is.null&order=updated_at.desc&limit=${limit}`;
  const res = await fetch(url, {
    headers: {
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
    },
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Failed to fetch tokens: ${res.status} ${txt}`);
  }
  return await res.json();
}

async function sendPush(token, payload = {}) {
  const defaultPayload = {
    token,
    title: payload.title || 'Equal Test Incoming Call',
    body: payload.body || 'If you see this notification, push delivery is working.',
    type: payload.type || 'incoming_call',
    data: payload.data || { source: 'push_check', ts: Date.now(), attempt: 1 },
  };

  // Coerce data values to strings for FCM HTTP v1
  const stringData = Object.fromEntries(
    Object.entries(defaultPayload.data).map(([k, v]) => [k, String(v)])
  );

  const url = `${SUPABASE_URL.replace('.co','').replace('https://','https://')}.functions.supabase.co/send_push`;
  // Alternative: build from project ref directly
  const fnUrl = 'https://jzougxfpnlyfhudcrlnz.functions.supabase.co/send_push';

  const res = await fetch(fnUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
    },
    body: JSON.stringify({
      token: defaultPayload.token,
      title: defaultPayload.title,
      body: defaultPayload.body,
      type: String(defaultPayload.type),
      data: stringData,
    }),
  });

  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  if (!res.ok) {
    throw new Error(`send_push failed: ${res.status} ${text}`);
  }
  return json;
}

async function main() {
  console.log('🔍 Push Check starting...');
  const { token: argToken, index } = parseArgs();
  let token = argToken;
  let recipientInfo = null;

  if (!token) {
    console.log('📲 Fetching recent FCM tokens...');
    const candidates = await fetchRecentFcmTokens(20);
    if (candidates.length > 0) {
      const pick = Math.min(Math.max(index, 0), candidates.length - 1);
      recipientInfo = candidates[pick];
      token = recipientInfo.fcm_token;
      console.log(`👤 Selected recipient [${pick}]: ${recipientInfo.username || recipientInfo.display_name || recipientInfo.id}`);
    } else {
      console.log('⚠️  No non-null FCM tokens found. Ask a user/device to open the app to refresh and save its token.');
      process.exit(2);
    }
  }

  console.log('📨 Invoking send_push...');
  const result = await sendPush(token, {
    title: 'Equal Test Incoming Call',
    body: 'If you see this, push is working.',
    type: 'incoming_call',
    data: { recipient_id: recipientInfo?.id || 'unknown', attempt: 1 },
  });

  console.log('✅ Function response:', result);
  if (result && result.fcm_response && !result.fcm_response.error) {
    console.log('🎉 Push accepted by FCM. Waiting for device to display notification.');
    process.exit(0);
  } else if (result && result.fcm_response && result.fcm_response.error) {
    console.log('⚠️  FCM error:', result.fcm_response.error);
    process.exit(3);
  } else {
    console.log('ℹ️  Received response without fcm_response details:', result);
    process.exit(0);
  }
}

main().catch(err => {
  console.error('❌ Push Check failed:', err.message);
  process.exit(1);
});