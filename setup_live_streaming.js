// Setup Live Streaming Database Schema in Supabase
// Run this script to create/update the necessary tables, policies and functions idempotently

const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

// Supabase configuration (prefer environment variables; fallback to constants in repo)
const SUPABASE_URL = process.env.SUPABASE_URL || 'https://jzougxfpnlyfhudcrlnz.supabase.co';
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imp6b3VneGZwbmx5Zmh1ZGNybG56Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczNDU0NzI3NSwiZXhwIjoyMDUwMTIzMjc1fQ.YCJGJhkJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJhJh';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

function splitSqlStatements(sql) {
  const statements = [];
  let buf = '';
  let i = 0;
  const len = sql.length;
  let inSingle = false;
  let inDouble = false;
  let inDollar = false;
  let dollarTag = null;
  let inLineComment = false;
  let inBlockComment = false;

  while (i < len) {
    const ch = sql[i];
    const next = i + 1 < len ? sql[i + 1] : '';

    // Handle line comments
    if (inLineComment) {
      buf += ch;
      if (ch === '\n') inLineComment = false;
      i++;
      continue;
    }

    // Handle block comments
    if (inBlockComment) {
      buf += ch;
      if (ch === '*' && next === '/') {
        buf += '/';
        i += 2;
        inBlockComment = false;
        continue;
      }
      i++;
      continue;
    }

    // Enter comments if not in quotes/dollar-quote
    if (!inSingle && !inDouble && !inDollar) {
      if (ch === '-' && next === '-') {
        buf += ch + next;
        i += 2;
        inLineComment = true;
        continue;
      }
      if (ch === '/' && next === '*') {
        buf += ch + next;
        i += 2;
        inBlockComment = true;
        continue;
      }
    }

    // Single quotes (handle escaped '')
    if (!inDouble && !inDollar && ch === '\'') {
      buf += ch;
      if (inSingle) {
        if (next === '\'') {
          buf += '\'';
          i += 2;
          continue;
        } else {
          inSingle = false;
          i++;
          continue;
        }
      } else {
        inSingle = true;
        i++;
        continue;
      }
    }

    // Double quotes
    if (!inSingle && !inDollar && ch === '"') {
      buf += ch;
      inDouble = !inDouble;
      i++;
      continue;
    }

    // Dollar-quoted strings/functions
    if (!inSingle && !inDouble && ch === '$') {
      // Attempt to find a tag like $tag$
      let j = i + 1;
      while (j < len && sql[j] !== '$' && /[A-Za-z0-9_]/.test(sql[j])) j++;
      if (j < len && sql[j] === '$') {
        const tag = sql.slice(i, j + 1); // includes both $...$
        if (!inDollar) {
          inDollar = true;
          dollarTag = tag;
          buf += tag;
          i = j + 1;
          continue;
        } else if (tag === dollarTag) {
          inDollar = false;
          dollarTag = null;
          buf += tag;
          i = j + 1;
          continue;
        }
      }
    }

    // Split on semicolon only when not inside quotes/dollar-quote/comments
    if (!inSingle && !inDouble && !inDollar && ch === ';') {
      const stmt = buf.trim();
      if (stmt.length) statements.push(stmt);
      buf = '';
      i++;
      continue;
    }

    buf += ch;
    i++;
  }

  const tail = buf.trim();
  if (tail.length) statements.push(tail);
  return statements;
}

async function hasExecSqlFunction() {
  try {
    const { error } = await supabase.rpc('exec_sql', { sql: 'SELECT 1' });
    return !error;
  } catch (_) {
    return false;
  }
}

async function applySqlFile(filePath) {
  const label = path.basename(filePath);
  if (!fs.existsSync(filePath)) {
    console.log(`⚠️  Skipping ${label}: file not found`);
    return;
  }
  const sql = fs.readFileSync(filePath, 'utf-8');
  console.log(`\n📄 Applying ${label} (${sql.length} chars)`);

  const hasExec = await hasExecSqlFunction();
  if (!hasExec) {
    console.log('❌ exec_sql function is not available via PostgREST.');
    const bootstrapPath = path.resolve(__dirname, 'bootstrap_exec_sql_function.sql');
    console.log('➡️  Please run this bootstrap file ONCE in the Supabase SQL Editor to enable RPC SQL execution:', bootstrapPath);
    console.log(`➡️  After running the bootstrap, re-run this script to apply ${label}.`);
    return;
  }

  const statements = splitSqlStatements(sql);
  console.log(`🔬 Split into ${statements.length} statements. Executing sequentially...`);

  for (let idx = 0; idx < statements.length; idx++) {
    const stmt = statements[idx];
    const preview = stmt.replace(/\s+/g, ' ').slice(0, 120);
    try {
      const { error } = await supabase.rpc('exec_sql', { sql: stmt });
      if (error) {
        console.log(`   ⛔ [${idx + 1}/${statements.length}] Error: ${error.message}`);
      } else {
        console.log(`   ✅ [${idx + 1}/${statements.length}] OK: ${preview}...`);
      }
    } catch (e) {
      console.log(`   ❌ [${idx + 1}/${statements.length}] Exception: ${e.message}`);
    }
  }

  console.log(`✅ Finished applying ${label}.`);
}

async function verifyIsEphemeralColumn() {
  console.log('\n🔎 Verifying live_streams.is_ephemeral column presence...');
  try {
    // Attempt to select the column; if PostgREST cache is stale, this may 404/column-missing
    const { data, error } = await supabase
      .from('live_streams')
      .select('id, is_ephemeral')
      .limit(1);
    if (error) {
      console.log(`⚠️  Verification error: ${error.message}`);
      console.log('If this mentions schema cache, wait a few seconds and try again, or reload the PostgREST schema by restarting the project in Supabase.');
    } else {
      console.log('✅ Column is accessible via PostgREST. Sample:', data);
    }
  } catch (e) {
    console.log('❌ Verification exception:', e.message);
  }
}

async function reloadPostgrestSchema() {
  console.log('\n🔁 Requesting PostgREST schema cache reload...');
  try {
    // Try NOTIFY channel first
    let { error } = await supabase.rpc('exec_sql', { sql: "NOTIFY pgrst, 'reload schema';" });
    if (error) {
      console.log(`⚠️  NOTIFY failed: ${error.message}. Trying pg_notify...`);
      const res2 = await supabase.rpc('exec_sql', { sql: "SELECT pg_notify('pgrst', 'reload schema');" });
      if (res2.error) {
        console.log(`❌ pg_notify also failed: ${res2.error.message}`);
      } else {
        console.log('✅ pg_notify sent');
      }
    } else {
      console.log('✅ NOTIFY sent');
    }
  } catch (e) {
    console.log('❌ Unexpected error sending reload notify:', e.message);
  }
  // Give PostgREST a moment to reload
  await new Promise((r) => setTimeout(r, 2000));
}

async function main() {
  console.log('🚀 Starting live streaming schema setup');
  console.log(`Supabase: ${SUPABASE_URL}`);

  const files = [
    path.resolve(__dirname, 'jitsi_live_streams_schema.sql'),
    path.resolve(__dirname, 'live_streams_schema.sql'),
  ];

  for (const f of files) {
    await applySqlFile(f);
  }

  if (await hasExecSqlFunction()) {
    await reloadPostgrestSchema();
  } else {
    console.log('\nℹ️ Skipping PostgREST reload because exec_sql is not available yet.');
  }

  await verifyIsEphemeralColumn();

  console.log('\n🏁 Setup completed.');
}

main().catch((err) => {
  console.error('💥 Setup failed:', err);
  process.exit(1);
});