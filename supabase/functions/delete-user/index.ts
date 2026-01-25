// Supabase Edge Function: delete-user
// Permanently deletes the currently authenticated user and cleans up their app data
// Requires the following environment variables to be set in the Supabase project:
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY (never store in repo; set via `supabase secrets set`)

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.1";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const url = new URL(req.url);
    const mode = url.searchParams.get("mode") ?? "delete"; // 'diagnose' to only report

    // Use service role to bypass RLS for cleanup; validate requester via their JWT separately
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // Extract JWT from Authorization header and validate
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.substring(7) : authHeader;
    const { data: userData, error: getUserError } = await supabase.auth.getUser(jwt);
    if (getUserError) {
      return json({ error: `Failed to validate user: ${getUserError.message}` }, 401);
    }
    const user = userData?.user;
    if (!user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const userId = user.id;

    // Helper: run delete and report whether it succeeded
    const runDelete = async (table: string, column: string) => {
      const { error } = await supabase.from(table).delete().eq(column, userId);
      if (error) {
        const msg = String(error.message ?? "");
        // Ignore errors due to missing relations/columns — different environments may not have all tables
        if (msg.includes('relation "') || msg.toLowerCase().includes("column") || msg.toLowerCase().includes("does not exist")) {
          console.warn(`Cleanup skipped for ${table}.${column}: ${msg}`);
          return { ok: true, skipped: true };
        } else {
          console.warn(`Cleanup error for ${table}.${column}: ${msg}`);
          return { ok: false, error: msg };
        }
      }
      return { ok: true };
    };

    // Verify rows exist utility
    const existsIn = async (table: string, column: string) => {
      const { count, error } = await supabase
        .from(table)
        .select(column, { count: 'exact', head: true })
        .eq(column, userId);
      if (error) {
        const msg = String(error.message ?? "");
        if (msg.includes('relation "') || msg.toLowerCase().includes("does not exist")) {
          return 0; // treat missing table as no rows
        }
        console.warn(`Count check error for ${table}.${column}: ${msg}`);
        return -1; // unknown
      }
      return count ?? 0;
    };

    // Helper: attempt delete across multiple possible FK column names
    const tryDeleteByColumns = async (table: string, columns: string[]) => {
      let anyOk = false;
      let lastError: string | null = null;
      for (const col of columns) {
        const res = await runDelete(table, col);
        if (res.ok) {
          anyOk = true;
        }
        if (res.error) {
          lastError = res.error;
        }
      }
      return { ok: anyOk, error: lastError };
    };

    // Helper: count rows across multiple possible FK columns
    const countByColumns = async (table: string, columns: string[]) => {
      let total = 0;
      let unknown = false;
      const perColumn: Record<string, number> = {};
      for (const col of columns) {
        const c = await existsIn(table, col);
        perColumn[col] = c;
        if (c < 0) unknown = true;
        if (c > 0) total += c;
      }
      return { total: unknown ? -1 : total, perColumn };
    };

    // Diagnose only: report counts without mutating anything
    if (mode === "diagnose") {
      const criticalCols = ["id", "user_id", "auth_user_id", "uid"];
      const usersCounts = await countByColumns("users", criticalCols);
      const userProfilesCounts = await countByColumns("user_profiles", criticalCols);
      const profilesCounts = await countByColumns("profiles", ["user_id", "id", "auth_user_id", "uid"]);

      // Non-critical tables to check
      const checks = async () => {
        return {
          posts: await countByColumns("posts", ["user_id"]),
          comments: await countByColumns("comments", ["user_id"]),
          likes: await countByColumns("likes", ["user_id"]),
          follows_by_follower: await countByColumns("follows", ["follower_id"]),
          follows_by_following: await countByColumns("follows", ["following_id"]),
          notifications: await countByColumns("notifications", ["user_id"]),
          messages_by_sender: await countByColumns("messages", ["sender_id"]),
          conversations_p1: await countByColumns("conversations", ["participant_1_id"]),
          conversations_p2: await countByColumns("conversations", ["participant_2_id"]),
          reports_by_reporter: await countByColumns("reports", ["reporter_id"]),
          reports_by_reported: await countByColumns("reports", ["reported_user_id"]),
          blocks_by_blocker: await countByColumns("blocks", ["blocker_id"]),
          blocks_by_blocked: await countByColumns("blocks", ["blocked_id"]),
          saves: await countByColumns("saves", ["user_id"]),
          shares: await countByColumns("shares", ["user_id"]),
        };
      };

      const nonCritical = await checks();
      const blockers: string[] = [];
      if (usersCounts.total > 0) blockers.push(`public.users has remaining rows (${usersCounts.total})`);
      if (userProfilesCounts.total > 0) blockers.push(`public.user_profiles has remaining rows (${userProfilesCounts.total})`);
      if (profilesCounts.total > 0) blockers.push(`public.profiles has remaining rows (${profilesCounts.total})`);

      return json({
        mode: "diagnose",
        userId,
        critical: {
          users: usersCounts,
          user_profiles: userProfilesCounts,
          profiles: profilesCounts,
        },
        non_critical: nonCritical,
        blockers,
      }, 200);
    }

    // Best-effort cleanup of app data based on your schema.sql
    // These are safe with service role and RLS bypass; they will be no-ops if a table/column doesn't exist
    const cleanupPass = async () => {
      // Critical: delete from user extension tables first to unblock auth deletion
      const criticalCols = ["id", "user_id", "auth_user_id", "uid"]; // cover common naming patterns
      const delUsers = await tryDeleteByColumns("users", criticalCols);
      const delUserProfiles = await tryDeleteByColumns("user_profiles", criticalCols);
      const delProfiles = await tryDeleteByColumns("profiles", ["user_id", "id", "auth_user_id", "uid"]);

      // If critical deletions failed, surface precise diagnostics
      const usersRemaining = await countByColumns("users", criticalCols);
      const userProfilesRemaining = await countByColumns("user_profiles", criticalCols);
      const profilesRemaining = await countByColumns("profiles", ["user_id", "id", "auth_user_id", "uid"]);
      if (!delUsers.ok || usersRemaining > 0) {
        return { ok: false, reason: `Pre-cleanup failed: public.users row still exists for user ${userId} (remaining=${usersRemaining})` };
      }
      if (!delUserProfiles.ok || userProfilesRemaining > 0) {
        return { ok: false, reason: `Pre-cleanup failed: user_profiles row still exists for user ${userId} (remaining=${userProfilesRemaining})` };
      }
      if (!delProfiles.ok || profilesRemaining > 0) {
        return { ok: false, reason: `Pre-cleanup failed: profiles row still exists for user ${userId} (remaining=${profilesRemaining})` };
      }

      // Non-critical tables (should not block auth deletion if public.users is gone)
      await runDelete("posts", "user_id");
      await runDelete("comments", "user_id");
      await runDelete("likes", "user_id");
      await runDelete("follows", "follower_id");
      await runDelete("follows", "following_id");
      await runDelete("notifications", "user_id");
      await runDelete("messages", "sender_id");
      await runDelete("conversations", "participant_1_id");
      await runDelete("conversations", "participant_2_id");
      await runDelete("reports", "reporter_id");
      await runDelete("reports", "reported_user_id");
      await runDelete("blocks", "blocker_id");
      await runDelete("blocks", "blocked_id");
      await runDelete("saves", "user_id");
      await runDelete("shares", "user_id");

      return { ok: true };
    };

    // First pass cleanup — this helps avoid constraint failures in some schemas
    const pass1 = await cleanupPass();
    if (!pass1.ok) {
      return json({ error: pass1.reason }, 500);
    }

    // Attempt to delete the auth user so they cannot log in again
    let { error: adminError } = await supabase.auth.admin.deleteUser(userId);
    if (adminError) {
      console.warn(`Admin deleteUser failed: ${adminError.message}. Retrying after extra cleanup...`);
      const pass2 = await cleanupPass();
      if (!pass2.ok) {
        return json({ error: pass2.reason }, 500);
      }
      const retry = await supabase.auth.admin.deleteUser(userId);
      adminError = retry.error;
    }

    if (adminError) {
      // Provide clear diagnostics for common constraint error from GoTrue
      return json({ error: `Database error deleting user: ${adminError.message}` }, 500);
    }

    return json({ success: true }, 200);
  } catch (e) {
    const msg = e?.message ?? String(e);
    return json({ error: msg }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}