// Minimal ffmpeg.wasm interop shim to avoid null references and support basic operations.
// In production, you should replace this with a full ffmpeg.wasm integration.
(function () {
  // State
  window.equalLastProgress = 0.0;

  // Lazy init: load @ffmpeg/ffmpeg UMD and create a singleton instance
  window.equalInitFFmpeg = async function () {
    try {
      if (window._equalFFmpeg && window._equalFFmpeg.isLoaded()) {
        return;
      }
      if (!window.FFmpeg || !window.FFmpeg.createFFmpeg) {
        throw new Error('FFmpeg UMD not loaded');
      }
      const ffmpeg = window.FFmpeg.createFFmpeg({
        log: false,
        corePath: 'https://unpkg.com/@ffmpeg/core@0.12.6/dist/ffmpeg-core.js',
      });
      // Track progress
      ffmpeg.setProgress(({ ratio }) => {
        try {
          window.equalLastProgress = ratio;
        } catch (_) {}
      });
      await ffmpeg.load();
      window._equalFFmpeg = ffmpeg;
    } catch (e) {
      console.error('equalInitFFmpeg error', e);
      throw e;
    }
  };

  // Helper: ensure input is an ArrayBuffer
  function toArrayBuffer(buf) {
    if (buf instanceof ArrayBuffer) return buf;
    if (buf && buf.buffer instanceof ArrayBuffer) return buf.buffer;
    // Fallback: create new ArrayBuffer
    const arr = new Uint8Array(buf || []);
    return arr.buffer;
  }

  // Apply filter: encode with filterGraph and optional speed (video+audio)
  window.equalApplyFilterFFmpegWasm = async function (inputBuffer, filterGraph, speed) {
    try {
      await window.equalInitFFmpeg();
      const ffmpeg = window._equalFFmpeg;
      if (!ffmpeg) throw new Error('FFmpeg not initialized');

      const inU8 = new Uint8Array(toArrayBuffer(inputBuffer));
      ffmpeg.FS('writeFile', 'in.mp4', inU8);

      const hasSpeed = typeof speed === 'number' && isFinite(speed) && speed !== 1.0;
      const safeAt = hasSpeed ? Math.max(0.5, Math.min(2.0, speed)) : 1.0;
      const vf = hasSpeed
        ? `${filterGraph},setpts=${(1 / speed).toFixed(4)}*PTS`
        : filterGraph;

      const args = [
        '-y',
        '-i', 'in.mp4',
        '-vf', vf,
        ...(hasSpeed ? ['-filter:a', `atempo=${safeAt.toFixed(2)}`] : []),
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '23',
        '-c:a', hasSpeed ? 'aac' : 'copy',
        '-movflags', '+faststart',
        'out.mp4',
      ];

      window.equalLastProgress = 0.0;
      try {
        await ffmpeg.run(...args);
      } catch (e1) {
        // Fallback: try mpeg4 codec if libx264 unavailable
        const argsMpeg4 = [
          '-y',
          '-i', 'in.mp4',
          '-vf', vf,
          ...(hasSpeed ? ['-filter:a', `atempo=${safeAt.toFixed(2)}`] : []),
          '-c:v', 'mpeg4',
          '-q:v', '5',
          ...(hasSpeed ? ['-c:a', 'aac'] : []),
          'out.mp4',
        ];
        await ffmpeg.run(...argsMpeg4);
      }

      const out = ffmpeg.FS('readFile', 'out.mp4');
      window.equalLastProgress = 1.0;
      return out.buffer;
    } catch (e) {
      console.error('equalApplyFilterFFmpegWasm error', e);
      throw e;
    }
  };

  // Compress video: encode using libx264 with scale + targetKbps or CRF and audio bitrate
  window.equalCompressFFmpegWasm = async function (inputBuffer, options) {
    try {
      await window.equalInitFFmpeg();
      const ffmpeg = window._equalFFmpeg;
      if (!ffmpeg) throw new Error('FFmpeg not initialized');

      const inU8 = new Uint8Array(toArrayBuffer(inputBuffer));
      ffmpeg.FS('writeFile', 'in.mp4', inU8);

      const scaleHeight = options && options.scaleHeight ? Number(options.scaleHeight) : 720;
      const targetKbps = options && options.targetKbps != null ? Number(options.targetKbps) : null;
      const audioKbps = options && options.audioKbps != null ? Number(options.audioKbps) : 96;
      const crf = options && options.crf != null ? Number(options.crf) : 28;

      const vf = `scale=-2:${scaleHeight},format=yuv420p`;
      const argsBitrate = [
        '-y',
        '-i', 'in.mp4',
        '-vf', vf,
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-b:v', `${targetKbps}k`,
        '-maxrate', `${targetKbps}k`,
        '-bufsize', `${targetKbps * 2}k`,
        '-c:a', 'aac',
        '-b:a', `${audioKbps}k`,
        '-movflags', '+faststart',
        'out.mp4',
      ];
      const argsCrf = [
        '-y',
        '-i', 'in.mp4',
        '-vf', vf,
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', String(crf),
        '-c:a', 'aac',
        '-b:a', `${audioKbps}k`,
        '-movflags', '+faststart',
        'out.mp4',
      ];

      window.equalLastProgress = 0.0;
      try {
        if (targetKbps && isFinite(targetKbps)) {
          await ffmpeg.run(...argsBitrate);
        } else {
          await ffmpeg.run(...argsCrf);
        }
      } catch (e1) {
        // Fallback: try mpeg4 codec
        const argsMpeg4 = [
          '-y',
          '-i', 'in.mp4',
          '-vf', vf,
          '-c:v', 'mpeg4',
          '-q:v', '5',
          '-c:a', 'aac',
          '-b:a', `${audioKbps}k`,
          'out.mp4',
        ];
        await ffmpeg.run(...argsMpeg4);
      }

      const out = ffmpeg.FS('readFile', 'out.mp4');
      window.equalLastProgress = 1.0;
      return out.buffer;
    } catch (e) {
      console.error('equalCompressFFmpegWasm error', e);
      throw e;
    }
  };

  // Combine side-by-side: stub returns left input unchanged.
  window.equalCombineFFmpegWasm = async function (leftBuffer, rightBuffer, options) {
    try {
      const ab = toArrayBuffer(leftBuffer);
      window.equalLastProgress = 1.0;
      return Promise.resolve(ab);
    } catch (e) {
      console.error('equalCombineFFmpegWasm error', e);
      throw e;
    }
  };

  // Append outro to input video bytes using ffmpeg.wasm
  // Concatenates original video with a black tail of length `outroSeconds` and optional outro audio.
  // If a logo image is provided (PNG), overlays it during the outro with fade in/out.
  window.equalAppendOutroFFmpegWasm = async function (inputBuffer, options) {
    try {
      await window.equalInitFFmpeg();
      const ffmpeg = window._equalFFmpeg;
      if (!ffmpeg) throw new Error('FFmpeg not initialized');

      // Write inputs
      const inU8 = new Uint8Array(toArrayBuffer(inputBuffer));
      const outroSeconds = (options && options.outroSeconds) ? Number(options.outroSeconds) : 2;
      ffmpeg.FS('writeFile', 'in.mp4', inU8);

      let hasOutroAudio = false;
      let outroAudioName = 'outro.m4a';
      if (options && options.outroAudio) {
        try {
          const outAud = new Uint8Array(toArrayBuffer(options.outroAudio));
          const ext = (options && options.outroAudioExt) ? String(options.outroAudioExt) : 'm4a';
          outroAudioName = `outro.${ext}`;
          ffmpeg.FS('writeFile', outroAudioName, outAud);
          hasOutroAudio = true;
        } catch (_) {
          hasOutroAudio = false;
        }
      }

      let hasLogo = false;
      if (options && options.logoPng) {
        try {
          const logo = new Uint8Array(toArrayBuffer(options.logoPng));
          ffmpeg.FS('writeFile', 'logo.png', logo);
          hasLogo = true;
        } catch (_) {
          hasLogo = false;
        }
      }

      // Build filter graph, optionally overlay logo on outro segment
      const outroOverlay = hasLogo
        ? '[3:v]scale=300:-1,format=rgba,fade=t=in:st=0:d=0.25:alpha=1,fade=t=out:st=' + (outroSeconds - 0.25).toFixed(2) + ':d=0.25:alpha=1[lg];[v1][lg]overlay=x=(main_w-overlay_w)/2:y=(main_h-overlay_h)-60-10*sin(2*PI*t):format=auto[v1o];'
        : '[v1]copy[v1o];';

      // Build primary command with audio concat
      const argsWithAudio = [
        '-y',
        '-i', 'in.mp4',
        '-f', 'lavfi', '-t', String(outroSeconds), '-i', 'color=c=black:s=1280x720',
        ...(hasOutroAudio
          ? ['-i', outroAudioName]
          : ['-f', 'lavfi', '-t', String(outroSeconds), '-i', 'sine=frequency=600:sample_rate=44100']),
        ...(hasLogo ? ['-loop', '1', '-i', 'logo.png'] : []),
        '-filter_complex',
        '[0:v]scale=-2:720,format=yuv420p[v0];' +
          '[1:v]format=yuv420p[v1];' +
          (hasLogo ? outroOverlay : '[v1]copy[v1o];') +
          '[0:a]aformat=sample_rates=44100:channel_layouts=stereo[a0];' +
          '[2:a]aformat=sample_rates=44100:channel_layouts=stereo[a1];' +
          '[v0][a0][v1o][a1]concat=n=2:v=1:a=1[v][a]',
        '-map', '[v]',
        '-map', '[a]',
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '23',
        '-c:a', 'aac',
        '-movflags', '+faststart',
        'out.mp4',
      ];

      try {
        window.equalLastProgress = 0.0;
        await ffmpeg.run(...argsWithAudio);
      } catch (e1) {
        console.warn('equalAppendOutroFFmpegWasm primary failed, trying video-only fallback', e1);
        // Fallback: video-only concat; drop audio mapping and encoding
        const argsVideoOnly = [
          '-y',
          '-i', 'in.mp4',
          '-f', 'lavfi', '-t', String(outroSeconds), '-i', 'color=c=black:s=1280x720',
          ...(hasLogo ? ['-loop', '1', '-i', 'logo.png'] : []),
          '-filter_complex',
          '[0:v]scale=-2:720,format=yuv420p[v0];' +
            '[1:v]format=yuv420p[v1];' +
            (hasLogo ? '[3:v]scale=300:-1,format=rgba,fade=t=in:st=0:d=0.25:alpha=1,fade=t=out:st=' + (outroSeconds - 0.25).toFixed(2) + ':d=0.25:alpha=1[lg];[v1][lg]overlay=x=(main_w-overlay_w)/2:y=(main_h-overlay_h)-60-10*sin(2*PI*t):format=auto[v1o];' : '[v1]copy[v1o];') +
            '[v0][v1o]concat=n=2:v=1[outv]',
          '-map', '[outv]',
          '-c:v', 'libx264',
          '-preset', 'veryfast',
          '-crf', '23',
          '-movflags', '+faststart',
          'out.mp4',
        ];
        try {
          await ffmpeg.run(...argsVideoOnly);
        } catch (e2) {
          // Final fallback: try mpeg4 codec to maximize compatibility with wasm builds
          const argsMpeg4 = [
            '-y',
            '-i', 'in.mp4',
            '-f', 'lavfi', '-t', String(outroSeconds), '-i', 'color=c=black:s=1280x720',
            '-filter_complex',
            '[0:v]scale=-2:720,format=yuv420p[v0];[1:v]format=yuv420p[v1];[v0][v1]concat=n=2:v=1[outv]',
            '-map', '[outv]',
            '-c:v', 'mpeg4',
            '-q:v', '5',
            'out.mp4',
          ];
          await ffmpeg.run(...argsMpeg4);
        }
      }

      // Read output
      const out = ffmpeg.FS('readFile', 'out.mp4');
      window.equalLastProgress = 1.0;
      return out.buffer;
    } catch (e) {
      console.error('equalAppendOutroFFmpegWasm error', e);
      throw e;
    }
  };

  // Extract frame thumbnail: return a tiny JPEG placeholder (1x1 white) encoded as ArrayBuffer
  window.equalExtractFrameFFmpegWasm = async function (inputBuffer, atSeconds) {
    try {
      // Minimal 1x1 JPEG binary
      const jpegBase64 =
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxISEhUTEhIWFRUWFRUVFRUVFRUVFRUWFxUVFRUYHSggGBolHRUVITEhJSkrLi4uFx8zODMtNygtLisBCgoKDg0OGxAQGy0lICUtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIAAEAAQMBIgACEQEDEQH/xAAbAAACAgMBAAAAAAAAAAAAAAAFBgMEAAIBB//EADYQAAIBAwMCBQMFAQAAAAAAAAECAwQFEQASITEGE0FRImFxgZHwIjMUI0KCsdH/xAAZAQEAAwEBAAAAAAAAAAAAAAABAgMEBQb/xAAjEQEBAAICAwADAQAAAAAAAAABAgMRBBIhMUFRE2GR/9oADAMBAAIRAxEAPwCk2rq3S6GmW2J4iXgq1q4qQFQ3QKkq6E3uNwS5vX1KfWm7HnYkqBf1dPzYV2m3s9HjJv+u1rF5zKkzG9W1vZr3Wl2V7o1l3Y8g3rDkC6bO5CwCqGk0+gqQk7I3iZyqk3cXgZ6S8or0z6vZk1K6oGkWvWZ9mYhYj1kQe5I1B7wB7eYk6yq1g0VZb1CT0fHfZfOaT8aK1fXKf2bW3KcYpJ5oQhKKA1b3WkV+oL5g3bo7bY3G+o4qj3z5Ff7mZcQ6gUQp9uP3K0UjWbqjWbqjWbqjWbqjWbqjWbqjWbqj/9k=';
      const bin = atob(jpegBase64);
      const len = bin.length;
      const buf = new Uint8Array(len);
      for (let i = 0; i < len; i++) buf[i] = bin.charCodeAt(i);
      window.equalLastProgress = 1.0;
      return Promise.resolve(buf.buffer);
    } catch (e) {
      console.error('equalExtractFrameFFmpegWasm error', e);
      throw e;
    }
  };
})();