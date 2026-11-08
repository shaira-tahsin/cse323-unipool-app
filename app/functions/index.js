const { onDocumentUpdated, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

// ── Helper: save notification to Firestore ───────────────────────────────
async function saveNotification(uid, { title, body, screen, rideId, chatId }) {
  await getFirestore()
    .collection("notifications")
    .doc(uid)
    .collection("items")
    .add({
      title,
      body,
      screen: screen ?? null,
      rideId: rideId ?? null,
      chatId: chatId ?? null,
      read: false,
      createdAt: new Date(),
    });
}


exports.notifyPassengerOnRequestUpdate = onDocumentUpdated(
  "rides/{rideId}/requests/{passengerId}",
  async (event) => {
    const before = event.data.before.data();
    const after  = event.data.after.data();

    // Only fire when status actually changes
    if (before.status === after.status) return null;

    const newStatus = after.status;
    if (newStatus !== "accepted" && newStatus !== "rejected") return null;

    const { passengerId, rideId } = event.params;

    // Fetch passenger's FCM token
    const userDoc = await getFirestore().collection("users").doc(passengerId).get();
    if (!userDoc.exists) return null;

    const fcmToken = userDoc.data()?.fcmToken;
    if (!fcmToken) return null;

    // Build notification payload
    const isAccepted = newStatus === "accepted";
    const title = isAccepted ? "Ride confirmed! 🎉" : "Request declined";
    const body  = isAccepted
      ? "Your driver has accepted your request. Open the app to chat."
      : "Your join request was declined. Try finding another ride.";

    // Send via FCM
    await getMessaging().send({
      token: fcmToken,
      notification: { title, body },
      data: {
        rideId,
        status: newStatus,
        screen: "driverProfile",
      },
      android: {
        priority: "high",
        notification: { channelId: "ride_updates" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });

    // Save to in-app notifications
    await saveNotification(passengerId, {
      title,
      body,
      screen: "driverProfile",
      rideId,
    });

    return null;
  }
);

// ── Notify DRIVER when a passenger sends a join request ───────────────────

exports.notifyDriverOnJoinRequest = onDocumentCreated(
  "rides/{rideId}/requests/{passengerId}",
  async (event) => {
    const { rideId, passengerId } = event.params;

    // Get the ride to find the driverId
    const rideDoc = await getFirestore().collection("rides").doc(rideId).get();
    if (!rideDoc.exists) return null;

    const driverId = rideDoc.data()?.driverId;
    if (!driverId) return null;

    // Get passenger name for the notification
    const passengerDoc = await getFirestore().collection("users").doc(passengerId).get();
    const passengerName = passengerDoc.exists
      ? (passengerDoc.data()?.name ?? "Someone")
      : "Someone";

    // Get driver's FCM token
    const driverDoc = await getFirestore().collection("users").doc(driverId).get();
    if (!driverDoc.exists) return null;

    const fcmToken = driverDoc.data()?.fcmToken;
    if (!fcmToken) return null;

    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: "New ride request! 🚗",
        body: `${passengerName} wants to join your ride.`,
      },
      data: { rideId, screen: "rideRequests" },
      android: {
        priority: "high",
        notification: { channelId: "ride_updates" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });

    // Save to in-app notifications
    await saveNotification(driverId, {
      title: "New ride request! 🚗",
      body: `${passengerName} wants to join your ride.`,
      screen: "rideRequests",
      rideId,
    });

    return null;
  }
);

// ── Notify the OTHER person when a chat message is sent ───────────────────
// chatId format: "{rideId}_{passengerId}"

exports.notifyOnChatMessage = onDocumentCreated(
  "chats/{chatId}/messages/{messageId}",
  async (event) => {
    const { chatId } = event.params;
    const message = event.data.data();

    const senderId = message?.senderId;
    const text     = message?.text;
    if (!senderId || !text) return null;

    // Parse rideId and passengerId from chatId
    const underscoreIndex = chatId.indexOf("_");
    if (underscoreIndex === -1) return null;
    const rideId      = chatId.substring(0, underscoreIndex);
    const passengerId = chatId.substring(underscoreIndex + 1);

    // Get the ride to find the driverId
    const rideDoc = await getFirestore().collection("rides").doc(rideId).get();
    if (!rideDoc.exists) return null;
    const driverId = rideDoc.data()?.driverId;
    if (!driverId) return null;

    // The recipient is whoever did NOT send the message
    const recipientId = senderId === driverId ? passengerId : driverId;

    // Get sender's name for the notification
    const senderDoc = await getFirestore().collection("users").doc(senderId).get();
    const senderName = senderDoc.exists
      ? (senderDoc.data()?.name ?? "Someone")
      : "Someone";

    // Get recipient's FCM token
    const recipientDoc = await getFirestore().collection("users").doc(recipientId).get();
    if (!recipientDoc.exists) return null;
    const fcmToken = recipientDoc.data()?.fcmToken;
    if (!fcmToken) return null;

    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: senderName,
        body: text.length > 100 ? text.substring(0, 97) + "..." : text,
      },
      data: {
        chatId,
        rideId,
        screen: "chat",
      },
      android: {
        priority: "high",
        notification: { channelId: "ride_updates" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    });

    // Save to in-app notifications
    await saveNotification(recipientId, {
      title: senderName,
      body: text.length > 100 ? text.substring(0, 97) + "..." : text,
      screen: "chat",
      rideId,
      chatId,
    });

    return null;
  }
);
