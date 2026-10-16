const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getAuth } = require("firebase-admin/auth");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const nodemailer = require("nodemailer");

initializeApp();

const db = getFirestore();

const SMTP_HOST = defineSecret("SMTP_HOST");
const SMTP_PORT = defineSecret("SMTP_PORT");
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");
const SMTP_FROM = defineSecret("SMTP_FROM");
const ORBIT_LOGO_URL = defineSecret("ORBIT_LOGO_URL");

const LABELS = {
  loveNotes: "Love Notes",
  specialDates: "Special Dates",
  spaceComplaints: "Complaints Box",
  galleryMedia: "Gallery",
  galleryFolders: "Gallery folders",
  relationshipStartAt: "Together For",
  chatMessages: "Chat",
};

function stringValue(value, fallback = "") {
  return typeof value === "string" ? value : fallback;
}

async function sendToUser(uid, notification) {
  if (!uid) return;
  const snapshot = await db.collection("users").doc(uid).collection("pushTokens").get();
  if (snapshot.empty) return;

  const tasks = [];
  for (const tokenDoc of snapshot.docs) {
    const token = stringValue(tokenDoc.get("token"));
    if (!token) continue;
    const hide = tokenDoc.get("hideNotificationDetails") === true;
    const title = hide ? notification.privateTitle : notification.detailedTitle;
    const body = hide ? notification.privateBody : notification.detailedBody;
    tasks.push({
      token,
      title,
      body,
      data: {
        kind: notification.kind,
        detailedTitle: notification.detailedTitle,
        detailedBody: notification.detailedBody,
        privateTitle: notification.privateTitle,
        privateBody: notification.privateBody,
      },
      tokenDoc,
    });
  }

  for (let start = 0; start < tasks.length; start += 500) {
    const chunk = tasks.slice(start, start + 500);
    const response = await getMessaging().sendEach(
      chunk.map((item) => ({
        token: item.token,
        notification: { title: item.title, body: item.body },
        data: item.data,
        android: {
          priority: "high",
          notification: {
            channelId: "partner_updates",
            sound: "default",
          },
        },
      })),
    );

    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success &&
          (result.error?.code === "messaging/registration-token-not-registered" ||
           result.error?.code === "messaging/invalid-registration-token")) {
        invalidTokens.push(chunk[index].tokenDoc.ref.delete());
      }
    });
    if (invalidTokens.length) await Promise.all(invalidTokens);
  }
}

async function getRecipients(spaceId, senderUid) {
  const space = await db.collection("privateSpaces").doc(spaceId).get();
  if (!space.exists) return [];
  // Do not send old-space notifications after either partner disconnects.
  if (space.get("connectionStatus") === "disconnected") return [];
  const members = space.get("memberUids");
  if (!Array.isArray(members)) return [];
  return members.filter((uid) => typeof uid === "string" && uid && uid !== senderUid);
}

async function getSenderName(spaceId, senderUid) {
  const space = await db.collection("privateSpaces").doc(spaceId).get();
  const names = space.exists ? space.get("memberNames") : null;
  if (names && typeof names[senderUid] === "string" && names[senderUid].trim()) {
    return names[senderUid].trim();
  }

  const profile = await db.collection("users").doc(senderUid).get();
  const name = profile.exists ? stringValue(profile.get("name")).trim() : "";
  return name || "Your partner";
}

exports.notifyNewChatMessage = onDocumentCreated(
  "privateSpaces/{spaceId}/chatMessages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message || message.unsent === true) return;
    const senderUid = stringValue(message.senderUid);
    if (!senderUid) return;

    const text = stringValue(message.text).trim();
    const type = stringValue(message.type, "text");
    const detailedBody = text ||
      (type === "voice" ? "Sent a voice message" :
       type === "image" ? "Sent a photo" :
       type === "video" ? "Sent a video" : "Sent a media file");
    const sender = await getSenderName(event.params.spaceId, senderUid);
    const notification = {
      kind: "message",
      detailedTitle: sender,
      detailedBody,
      privateTitle: "Check message",
      privateBody: "You have a new message.",
    };

    const recipients = await getRecipients(event.params.spaceId, senderUid);
    await Promise.all(recipients.map((uid) => sendToUser(uid, notification)));
  },
);

exports.notifyChangedChatMessage = onDocumentUpdated(
  "privateSpaces/{spaceId}/chatMessages/{messageId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    const senderUid = stringValue(after.senderUid || before.senderUid);
    const becameUnsent = before.unsent !== true && after.unsent === true;
    const textChanged = before.text !== after.text && after.unsent !== true;
    if (!becameUnsent && !textChanged) return;

    const recipients = await getRecipients(event.params.spaceId, senderUid);
    const notification = {
      kind: "change",
      detailedTitle: await getSenderName(event.params.spaceId, senderUid),
      detailedBody: becameUnsent ? "A message was removed." : "A message was edited.",
      privateTitle: "Check change",
      privateBody: "Your partner changed a message.",
    };
    await Promise.all(recipients.map((uid) => sendToUser(uid, notification)));
  },
);

exports.notifyDeletedChatMessage = onDocumentDeleted(
  "privateSpaces/{spaceId}/chatMessages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message || message.unsent === true) return;
    const senderUid = stringValue(message.senderUid);
    if (!senderUid) return;

    const recipients = await getRecipients(event.params.spaceId, senderUid);
    const notification = {
      kind: "change",
      detailedTitle: await getSenderName(event.params.spaceId, senderUid),
      detailedBody: "A message was removed.",
      privateTitle: "Check change",
      privateBody: "Your partner changed a message.",
    };
    await Promise.all(recipients.map((uid) => sendToUser(uid, notification)));
  },
);

exports.notifySharedSpaceChanges = onDocumentWritten(
  "privateSpaces/{spaceId}/syncData/appState",
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : {};
    const after = event.data?.after.exists ? event.data.after.data() : null;
    if (!after) return;

    const senderUid = stringValue(after.updatedBy);
    if (!senderUid) return;

    const ignored = new Set(["updatedBy", "updatedAt", "partnerOne", "partnerTwo"]);
    const changed = new Set();
    for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) {
      if (ignored.has(key)) continue;
      if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) changed.add(key);
    }
    if (!changed.size) return;

    const readable = [...changed].map((key) => LABELS[key] || "Shared data").filter(Boolean);
    const uniqueReadable = [...new Set(readable)].join(", ");
    const notification = {
      kind: "change",
      detailedTitle: await getSenderName(event.params.spaceId, senderUid),
      detailedBody: "Changed: " + uniqueReadable,
      privateTitle: "Check change",
      privateBody: "Your partner changed shared data.",
    };
    const recipients = await getRecipients(event.params.spaceId, senderUid);
    await Promise.all(recipients.map((uid) => sendToUser(uid, notification)));
  },
);

exports.sendBrandedPasswordResetEmail = onCall(
  {
    secrets: [
      SMTP_HOST,
      SMTP_PORT,
      SMTP_USER,
      SMTP_PASS,
      SMTP_FROM,
      ORBIT_LOGO_URL,
    ],
  },
  async (request) => {
    const email = stringValue(request.data?.email).trim().toLowerCase();
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Enter a valid email address.");
    }

    try {
      const resetLink = await getAuth().generatePasswordResetLink(email);
      const port = Number(SMTP_PORT.value() || 587);
      const transporter = nodemailer.createTransport({
        host: SMTP_HOST.value(),
        port,
        secure: port === 465,
        auth: {
          user: SMTP_USER.value(),
          pass: SMTP_PASS.value(),
        },
      });

      const logoUrl = ORBIT_LOGO_URL.value().trim();
      const logo = logoUrl
        ? '<img src="' + logoUrl.replace(/&/g, "&amp;").replace(/"/g, "&quot;") +
          '" width="76" height="76" alt="Orbit Two" style="display:block;width:76px;height:76px;object-fit:contain;margin:0 auto 18px;border-radius:18px;">'
        : '<div style="font-size:42px;line-height:1;margin:0 auto 18px;">♡</div>';
      const safeLink = resetLink.replace(/&/g, "&amp;").replace(/"/g, "&quot;");

      await transporter.sendMail({
        from: SMTP_FROM.value(),
        to: email,
        subject: "Reset your Orbit Two password",
        text:
          "Orbit Two password reset\n\n" +
          "We received a request to reset your Orbit Two password. Use this link to choose a new password:\n\n" +
          resetLink + "\n\n" +
          "If you did not request this, you can ignore this email.",
        html: `<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f4f2f8;font-family:Arial,Helvetica,sans-serif;color:#211b31;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Reset your Orbit Two password securely.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f2f8;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border-radius:22px;overflow:hidden;">
        <tr><td style="padding:36px 28px 30px;text-align:center;background:#100b24;color:#ffffff;">
          ${logo}
          <div style="font-size:25px;font-weight:700;letter-spacing:.2px;">Orbit Two</div>
          <div style="font-size:14px;color:#d8cfee;margin-top:8px;">Your private space for two</div>
        </td></tr>
        <tr><td style="padding:34px 28px 18px;">
          <h1 style="font-size:24px;line-height:1.3;margin:0 0 16px;color:#211b31;">Reset your password</h1>
          <p style="font-size:16px;line-height:1.7;margin:0 0 14px;">We received a request to reset the password for your Orbit Two account.</p>
          <p style="font-size:16px;line-height:1.7;margin:0 0 26px;">Use the button below to choose a new password. For your security, only use this link if you requested the reset.</p>
          <p style="text-align:center;margin:0 0 26px;">
            <a href="${safeLink}" style="display:inline-block;background:#ff2e93;color:#ffffff;text-decoration:none;font-size:17px;font-weight:700;padding:17px 28px;border-radius:12px;">Reset my password</a>
          </p>
          <p style="font-size:14px;line-height:1.7;margin:0 0 8px;color:#5e566e;">If the button does not work, open this secure link:</p>
          <p style="font-size:15px;line-height:1.7;word-break:break-all;margin:0 0 22px;"><a href="${safeLink}" style="color:#8b3dcb;text-decoration:underline;">Reset your Orbit Two password</a></p>
          <p style="font-size:13px;line-height:1.7;color:#756d83;margin:0;">If you did not request a password reset, you can safely ignore this email. Your password will not change unless you use the link.</p>
        </td></tr>
        <tr><td style="padding:22px 28px;background:#faf9fc;text-align:center;border-top:1px solid #eeeaf4;">
          <p style="font-size:12px;line-height:1.6;color:#8a8298;margin:0;">Orbit Two · Made with care for your private space</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`,
      });

      return { ok: true };
    } catch (error) {
      // Keep account-existence details private, matching Firebase's reset flow.
      if (error?.code === "auth/user-not-found") return { ok: true };
      console.error("Branded password reset email failed:", error);
      throw new HttpsError(
        "internal",
        "The password reset email could not be sent. Please try again later.",
      );
    }
  },
);
