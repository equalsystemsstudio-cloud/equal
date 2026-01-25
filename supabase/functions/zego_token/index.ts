// Supabase Edge Function: ZEGOCLOUD Token v04 generator (Deno)
// Reads credentials from environment variables and returns a token for the given user.
// Env vars required:
// - ZEGO_APP_ID (number)
// - ZEGO_SERVER_SECRET (32-char string)

function jsonResponse(body: unknown, status = 200) {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type,authorization",
  });
  return new Response(JSON.stringify(body), { status, headers });
}

function textResponse(text: string, status = 200) {
  const headers = new Headers({
    "content-type": "text/plain; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type,authorization",
  });
  return new Response(text, { status, headers });
}

function badRequest(message: string) {
  return jsonResponse({ error: message }, 400);
}

// Utility: base64 encode Uint8Array
function base64FromBytes(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  // btoa expects binary string
  return btoa(binary);
}

// Generate a random IV of 16 bytes
function randomIV(): Uint8Array {
  const iv = new Uint8Array(16);
  crypto.getRandomValues(iv);
  return iv;
}

// Convert serverSecret string into raw key bytes
function keyBytesFromSecret(secret: string): Uint8Array {
  // Decode 32-hex-character string into 16 raw bytes (AES-128 key)
  const clean = secret.trim();
  if (/^[0-9a-fA-F]{32}$/.test(clean)) {
    const bytes = new Uint8Array(16);
    for (let i = 0; i < 32; i += 2) {
      bytes[i / 2] = parseInt(clean.slice(i, i + 2), 16);
    }
    return bytes;
  }
  // Fallback: use UTF-8 bytes when secret isn't hex (e.g., custom deployments)
  return new TextEncoder().encode(clean);
}

function pkcs7Pad(data: Uint8Array, blockSize = 16): Uint8Array {
  const remainder = data.length % blockSize;
  const padLen = remainder === 0 ? blockSize : (blockSize - remainder);
  const out = new Uint8Array(data.length + padLen);
  out.set(data);
  out.fill(padLen, data.length);
  return out;
}

async function aesCbcEncrypt(secret: string, iv: Uint8Array, plainText: string): Promise<Uint8Array> {
  const keyBytes = keyBytesFromSecret(secret);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "AES-CBC" },
    false,
    ["encrypt"],
  );
  const plainBytes = new TextEncoder().encode(plainText);
  const padded = pkcs7Pad(plainBytes, 16);
  const cipherBuf = await crypto.subtle.encrypt(
    { name: "AES-CBC", iv },
    cryptoKey,
    padded,
  );
  return new Uint8Array(cipherBuf);
}

// Implements the v04 packing specification based on ZEGOCLOUD docs
// Token = "04" + Base64(expire(8 bytes) + ivLen(2 bytes) + iv + cipherLen(2 bytes) + cipher)
function packToken(expire: number, iv: Uint8Array, cipher: Uint8Array): string {
  const ivLen = iv.length; // expected 16
  const cipherLen = cipher.length;
  const out = new Uint8Array(8 + 2 + ivLen + 2 + cipherLen);

  // expire: 8 bytes (store as unsigned 64-bit big-endian, but typical samples store high 4 bytes zero + low 4 as Unix seconds)
  const dv = new DataView(out.buffer);
  // Write high 32 bits as 0
  dv.setUint32(0, 0, false);
  // Write low 32 bits = expire seconds
  dv.setUint32(4, expire >>> 0, false);

  // iv length: 2 bytes big-endian
  out[8] = (ivLen >> 8) & 0xff;
  out[9] = ivLen & 0xff;
  // iv: 16 bytes
  out.set(iv, 10);

  // cipher length: 2 bytes big-endian
  const cipherLenOffset = 10 + ivLen;
  out[cipherLenOffset] = (cipherLen >> 8) & 0xff;
  out[cipherLenOffset + 1] = cipherLen & 0xff;

  // cipher bytes
  out.set(cipher, cipherLenOffset + 2);

  return "04" + base64FromBytes(out);
}

export async function generateToken04(
  appID: number,
  userID: string,
  serverSecret: string,
  effectiveTimeInSeconds: number,
  payload?: string,
) {
  if (!appID || !userID || !serverSecret || !effectiveTimeInSeconds) {
    throw new Error("Missing required parameters");
  }
  const now = Math.floor(Date.now() / 1000);
  const expire = now + effectiveTimeInSeconds;
  // Body per published client spec; include payload if provided for privilege control
  const body: Record<string, unknown> = {
    app_id: appID,
    user_id: userID,
    nonce: Math.floor(Math.random() * 2147483647),
    ctime: now,
    expire,
  };
  if (payload && payload.length > 0) {
    body.payload = payload;
  }
  const iv = randomIV();
  const plainText = JSON.stringify(body);
  const cipher = await aesCbcEncrypt(serverSecret, iv, plainText);
  const token = packToken(expire, iv, cipher);
  return { token, expire };
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: new Headers({
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET,POST,OPTIONS",
        "access-control-allow-headers": "content-type,authorization",
      }),
    });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, service: "zego_token", version: 1 });
  }

  if (req.method !== "POST") {
    return badRequest("Method not allowed");
  }

  const ZEGO_APP_ID = Deno.env.get("ZEGO_APP_ID");
  const ZEGO_SERVER_SECRET = Deno.env.get("ZEGO_SERVER_SECRET");
  if (!ZEGO_APP_ID || !ZEGO_SERVER_SECRET) {
    return jsonResponse({ error: "Server not configured: missing ZEGO_APP_ID or ZEGO_SERVER_SECRET" }, 500);
  }

  let body: any = {};
  try {
    body = await req.json();
  } catch (_) {
    return badRequest("Invalid JSON body");
  }

  const userID: string | undefined = body.user_id ?? body.userId;
  const role: string | undefined = body.role; // "host" | "viewer" optional
  const roomId: string | undefined = body.room_id ?? body.roomId;
  const streamIdList: string[] | undefined = body.stream_id_list ?? body.streamIdList;
  const secondsRaw = body.effective_time_in_seconds ?? body.seconds ?? body.ttl_seconds;
  const effectiveTimeInSeconds = Number(secondsRaw ?? 3600);

  if (!userID || typeof userID !== "string") {
    return badRequest("Missing required field: user_id");
  }
  if (!Number.isFinite(effectiveTimeInSeconds) || effectiveTimeInSeconds <= 0) {
    return badRequest("Invalid effective_time_in_seconds");
  }

  let payload: string | undefined;
  if (role || roomId || streamIdList) {
    const loginPrivilege = 1;
    const publishPrivilege = role === "viewer" ? 0 : 1; // viewer cannot publish by default
    const payloadObj = {
      room_id: roomId ?? "",
      privilege: { 1: loginPrivilege, 2: publishPrivilege },
      stream_id_list: streamIdList ?? [],
    };
    payload = JSON.stringify(payloadObj);
  } else if (typeof body.payload === "string") {
    payload = body.payload;
  }

  try {
    const { token, expire } = await generateToken04(
      Number(ZEGO_APP_ID),
      userID,
      ZEGO_SERVER_SECRET,
      effectiveTimeInSeconds,
      payload,
    );
    return jsonResponse({ token, app_id: Number(ZEGO_APP_ID), user_id: userID, expire });
  } catch (err) {
    return jsonResponse({ error: (err as Error).message }, 500);
  }
});