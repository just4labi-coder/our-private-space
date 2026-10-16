const {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const db = getFirestore();
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
    const sender = stringValue(message.senderName, "Your partner");
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
      detailedTitle: stringValue(after.senderName, "Your partner"),
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
      detailedTitle: stringValue(message.senderName, "Your partner"),
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
      detailedTitle: "Partner update",
      detailedBody: "Changed: " + uniqueReadable,
      privateTitle: "Check change",
      privateBody: "Your partner changed shared data.",
    };
    const recipients = await getRecipients(event.params.spaceId, senderUid);
    await Promise.all(recipients.map((uid) => sendToUser(uid, notification)));
  },
);
