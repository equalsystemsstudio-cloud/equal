# Jitsi Live Streaming Database Setup

To fix the "Could not find the table 'public.live_streams'" error, you need to execute the database schema in your Supabase project.

## Steps to Setup the Database:

1. **Open Supabase Dashboard**
   - Go to [supabase.com](https://supabase.com)
   - Sign in to your account
   - Select your project

2. **Navigate to SQL Editor**
   - Click on "SQL Editor" in the left sidebar
   - Click "New Query"

3. **Execute the Schema**
   - Copy the entire contents of `jitsi_live_streams_schema.sql`
   - Paste it into the SQL editor
   - Click "Run" to execute the schema

4. **Verify Tables Created**
   - Go to "Table Editor" in the left sidebar
   - You should see the following new tables:
     - `live_streams`
     - `live_stream_viewers`
     - `live_stream_chat`
     - `live_stream_reactions`

## What This Schema Creates:

- **live_streams**: Main table for storing live stream information with Jitsi Meet integration
- **live_stream_viewers**: Tracks who joins/leaves streams
- **live_stream_chat**: Stores chat messages during streams
- **live_stream_reactions**: Stores reactions (hearts, likes, etc.)
- **Row Level Security (RLS)**: Proper security policies
- **Triggers**: Automatic viewer count updates
- **Views**: Analytics and active streams views

## Key Changes from Mux to Jitsi:

- Replaced `mux_stream_id`, `mux_playback_id`, `stream_key` with `jitsi_room_name` and `jitsi_stream_url`
- Updated views to remove Mux-specific playback URLs
- Maintained all other functionality for chat, viewers, and reactions

After executing this schema, your live streaming functionality should work properly!