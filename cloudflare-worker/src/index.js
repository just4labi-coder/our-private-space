const FIREBASE_PROJECT_ID = "our-privet-space";
const FIREBASE_AUTH_LOOKUP = "https://identitytoolkit.googleapis.com/v1/accounts:lookup";

let cachedAccessToken = "";
let cachedAccessTokenExpiry = 0;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "POST, OPTIONS",
      "access-control-allow-headers": "authorization, content-type",
      "cache-control": "no-store",
    },
  });
}

function b64url(input) {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToArrayBuffer(pem) {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getGoogleAccessToken(env) {
  if (cachedAccessToken && Date.now() < cachedAccessTokenExpiry - 60_000) {
    return cachedAccessToken;
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON);
  } catch (_) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON.");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/cloud-platform",
    aud: serviceAccount.token_uri || "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = header + "." + claims;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = unsigned + "." + b64url(signature);
  const response = await fetch(
    serviceAccount.token_uri || "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    },
  );
  const result = await response.json();
  if (!response.ok || !result.access_token) {
    throw new Error("Google service authentication failed.");
  }
  cachedAccessToken = result.access_token;
  cachedAccessTokenExpiry = Date.now() + (Number(result.expires_in || 3600) * 1000);
  return cachedAccessToken;
}

async function verifyFirebaseUser(idToken, env) {
  const response = await fetch(
    FIREBASE_AUTH_LOOKUP + "?key=" + encodeURIComponent(env.FIREBASE_WEB_API_KEY),
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ idToken }),
    },
  );
  const result = await response.json();
  if (!response.ok || !Array.isArray(result.users) || !result.users[0]?.localId) {
    throw new Error("Invalid Firebase login token.");
  }
  return result.users[0];
}

function decodeValue(value) {
  if (!value || typeof value !== "object") return null;
  if ("stringValue" in value) return value.stringValue;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return value.timestampValue;
  if ("nullValue" in value) return null;
  if ("arrayValue" in value) return (value.arrayValue.values || []).map(decodeValue);
  if ("mapValue" in value) return decodeFields(value.mapValue.fields || {});
  return null;
}

function decodeFields(fields) {
  const result = {};
  for (const [key, value] of Object.entries(fields || {})) result[key] = decodeValue(value);
  return result;
}

async function firestoreGet(path, accessToken) {
  const url = "https://firestore.googleapis.com/v1/projects/" +
    FIREBASE_PROJECT_ID + "/databases/(default)/documents/" +
    path.split("/").map(encodeURIComponent).join("/");
  const response = await fetch(url, {
    headers: { authorization: "Bearer " + accessToken },
  });
  if (response.status === 404) return null;
  const result = await response.json();
  if (!response.ok) throw new Error("Could not read trusted app data from Firestore.");
  return decodeFields(result.fields || {});
}

async function firestoreList(path, accessToken) {
  const url = "https://firestore.googleapis.com/v1/projects/" +
    FIREBASE_PROJECT_ID + "/databases/(default)/documents/" +
    path.split("/").map(encodeURIComponent).join("/") + "?pageSize=100";
  const response = await fetch(url, {
    headers: { authorization: "Bearer " + accessToken },
  });
  const result = await response.json();
  if (!response.ok) throw new Error("Could not read notification devices.");
  return (result.documents || []).map((doc) => ({
    name: doc.name,
    data: decodeFields(doc.fields || {}),
  }));
}

async function firestoreCreateEvent(eventId, spaceId, messageId, senderUid, accessToken) {
  const url = "https://firestore.googleapis.com/v1/projects/" +
    FIREBASE_PROJECT_ID + "/databases/(default)/documents/notificationEvents?documentId=" +
    encodeURIComponent(eventId);
  const response = await fetch(url, {
    method: "POST",
    headers: {
      authorization: "Bearer " + accessToken,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        spaceId: { stringValue: spaceId },
        messageId: { stringValue: messageId },
        senderUid: { stringValue: senderUid },
        createdAt: { timestampValue: new Date().toISOString() },
      },
    }),
  });
  if (response.status === 409) return false;
  if (!response.ok) throw new Error("Could not record notification event.");
  return true;
}


function cleanText(value, maxLength = 180) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

async function sendFcm(accessToken, token, title, body, details) {
  const response = await fetch(
    "https://fcm.googleapis.com/v1/projects/" + FIREBASE_PROJECT_ID + "/messages:send",
    {
      method: "POST",
      headers: {
        authorization: "Bearer " + accessToken,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: {
            kind: "message",
            detailedTitle: details.title,
            detailedBody: details.body,
            privateTitle: "Check message",
            privateBody: "You have a new message.",
          },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "orbit_partner_updates_v2",
              sound: "default",
              icon: "ic_stat_orbit",
              color: "#FF2E93",
              default_sound: true,
              default_vibrate_timings: true,
              notification_priority: "PRIORITY_MAX",
              visibility: "PRIVATE",
            },
          },
        },
      }),
    },
  );
  return response.ok;
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return json({ ok: true });
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      let serviceAccountConfigured = false;
      try {
        const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || "");
        serviceAccountConfigured = Boolean(
          account.client_email &&
          account.private_key &&
          (account.token_uri || "https://oauth2.googleapis.com/token")
        );
      } catch (_) {
        serviceAccountConfigured = false;
      }

      return json({
        ok: true,
        service: "Orbit Two notifications",
        firebaseApiKeyConfigured: Boolean(env.FIREBASE_WEB_API_KEY),
        serviceAccountConfigured,
      });
    }
    if (request.method !== "POST" || url.pathname !== "/notify-message") {
      return json({ error: "Not found" }, 404);
    }

    const authorization = request.headers.get("authorization") || "";
    const idToken = authorization.startsWith("Bearer ")
      ? authorization.slice(7).trim()
      : "";
    if (!idToken) return json({ error: "Authentication required" }, 401);

    // Fail early with a clear configuration status instead of making Firebase
    // requests that cannot succeed when Cloudflare secrets are missing.
    if (!env.FIREBASE_WEB_API_KEY || !env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      console.error("Orbit notification Worker is missing required Firebase secrets.");
      return json({ error: "Worker Firebase secrets are not configured" }, 503);
    }

    let input;
    try {
      input = await request.json();
    } catch (_) {
      return json({ error: "Invalid JSON" }, 400);
    }
    const spaceId = cleanText(input.spaceId, 150);
    const messageId = cleanText(input.messageId, 150);
    if (!/^[A-Za-z0-9_-]+$/.test(spaceId) ||
        !/^[A-Za-z0-9_-]+$/.test(messageId)) {
      return json({ error: "Invalid space or message ID" }, 400);
    }

    try {
      const user = await verifyFirebaseUser(idToken, env);
      const uid = user.localId;
      const accessToken = await getGoogleAccessToken(env);
      const [space, message] = await Promise.all([
        firestoreGet("privateSpaces/" + spaceId, accessToken),
        firestoreGet("privateSpaces/" + spaceId + "/chatMessages/" + messageId, accessToken),
      ]);

      if (!space || !message) return json({ error: "Message or space not found" }, 404);
      const members = Array.isArray(space.memberUids) ? space.memberUids : [];
      if (members.length !== 2 || !members.includes(uid) ||
          space.connectionStatus === "disconnected") {
        return json({ error: "Not an active space member" }, 403);
      }
      if (message.senderUid !== uid || message.unsent === true) {
        return json({ error: "Message sender could not be verified" }, 403);
      }

      const partnerUid = members.find((member) => member !== uid);
      if (!partnerUid) return json({ error: "Partner not found" }, 404);

      // Check for a completed notification before attempting delivery. The
      // event is recorded only after at least one FCM send succeeds, so missing
      // tokens or temporary FCM errors do not permanently block a later retry.
      const eventId = (spaceId + "_" + messageId).slice(0, 180);
      const existingEvent = await firestoreGet("notificationEvents/" + eventId, accessToken);
      if (existingEvent) return json({ ok: true, duplicate: true, pushCount: 0 });

      const [senderProfile, tokenDocs] = await Promise.all([
        firestoreGet("users/" + uid, accessToken),
        firestoreList("users/" + partnerUid + "/pushTokens", accessToken),
      ]);

      const memberNames = space.memberNames && typeof space.memberNames === "object"
        ? space.memberNames : {};
      const senderName = cleanText(memberNames[uid], 80) ||
        cleanText(senderProfile?.name, 80) ||
        cleanText(user.email?.split("@")[0], 80) || "Your partner";
      const type = cleanText(message.type, 20) || "text";
      const messageText = cleanText(message.text, 180);
      const preview = messageText || (
        type === "voice" ? "Sent a voice message" :
        type === "image" ? "Sent a photo" :
        type === "video" ? "Sent a video" : "Sent a message"
      );

      let pushCount = 0;
      for (const tokenDoc of tokenDocs) {
        const token = cleanText(tokenDoc.data.token, 5000);
        if (!token) continue;
        const hidden = tokenDoc.data.hideNotificationDetails === true;
        const sent = await sendFcm(
          accessToken,
          token,
          hidden ? "Check message" : senderName,
          hidden ? "You have a new message." : preview,
          { title: senderName, body: preview },
        );
        if (sent) pushCount++;
      }

      if (pushCount === 0) {
        // Do not record a completed event: the partner may register a token
        // later, and a retry should then be able to deliver the notification.
        return json({ ok: true, pushCount: 0, retryable: true });
      }

      await firestoreCreateEvent(eventId, spaceId, messageId, uid, accessToken);
      return json({ ok: true, pushCount });
    } catch (error) {
      console.error("Orbit Two notification request failed:", error?.message || "unknown");
      return json({ error: "Notification could not be processed" }, 500);
    }
  },
};
