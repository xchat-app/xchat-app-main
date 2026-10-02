package com.oxchat.nostr;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Person;
import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Icon;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.os.Build;

import com.oxchat.lite.R;

/**
 * The ringing notification for a call that arrives while the app is not on
 * screen. Before it, such a call showed nothing: the call page opened inside
 * the backgrounded app and the caller waited out the ring timeout.
 *
 * It shows the caller with Answer and Decline, plays the ringtone until one of
 * them (or the caller giving up) clears it, and carries a full-screen intent so
 * a phone with its screen off lights up and rings. Flutter posts and cancels it
 * through AppPreferences ("showIncomingCall" / "cancelIncomingCall"); with the
 * app on screen the call page rings instead.
 *
 * Answer opens the app (MainActivity), which tells Flutter to accept once the
 * call page has the microphone; Decline goes through CallActionReceiver.
 * On a locked phone Answer asks for the unlock first: the app is not shown over
 * the lock screen.
 */
public final class IncomingCallNotification {
    public static final String ACTION_ANSWER = "com.oxchat.nostr.ACTION_ANSWER_CALL";
    public static final String ACTION_DECLINE = "com.oxchat.nostr.ACTION_DECLINE_CALL";
    public static final String EXTRA_SESSION_ID = "call_session_id";

    private static final String CHANNEL_ID = "IncomingCallChannel";
    // 1001/1002 are PushNotificationService's, 1003 VoiceCallService's.
    private static final int NOTIFICATION_ID = 1004;
    // The caller gives up after 45 s and Flutter cancels this then; the
    // timeout only covers the case where nothing does.
    private static final long TIMEOUT_MS = 60_000;

    private IncomingCallNotification() {}

    public static void show(Context context, String sessionId, String remoteName, boolean isVideo,
                            String content, String answerLabel, String declineLabel) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "Incoming calls", NotificationManager.IMPORTANCE_HIGH);
        channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build());
        channel.enableVibration(true);
        channel.setVibrationPattern(new long[]{0, 1000, 1000});
        manager.createNotificationChannel(channel);

        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        Intent answer = new Intent(context, MainActivity.class)
                .setAction(ACTION_ANSWER)
                .putExtra(EXTRA_SESSION_ID, sessionId)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent answerIntent = PendingIntent.getActivity(context, 2, answer, flags);
        PendingIntent declineIntent = PendingIntent.getBroadcast(context, 4,
                new Intent(context, CallActionReceiver.class)
                        .setAction(ACTION_DECLINE)
                        .putExtra(EXTRA_SESSION_ID, sessionId), flags);
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open == null) open = new Intent(context, MainActivity.class);
        open.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent openIntent = PendingIntent.getActivity(context, 3, open, flags);

        String name = remoteName == null || remoteName.isEmpty() ? "XChat" : remoteName;
        // On a lock screen that hides sensitive content: no name, just the call.
        Notification publicVersion = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("XChat")
                .setContentText(content)
                .setCategory(Notification.CATEGORY_CALL)
                .build();
        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(name)
                .setContentText(content)
                .setCategory(Notification.CATEGORY_CALL)
                .setOngoing(true)
                .setAutoCancel(false)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setContentIntent(openIntent)
                .setTimeoutAfter(TIMEOUT_MS);

        // Android 14 takes the full-screen permission away from apps Play has
        // not approved as calling apps; without it CallStyle is refused too.
        boolean fullScreen = Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE
                || manager.canUseFullScreenIntent();
        if (fullScreen) builder.setFullScreenIntent(openIntent, true);
        if (fullScreen && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Person caller = new Person.Builder().setName(name).setImportant(true).build();
            builder.setStyle(Notification.CallStyle.forIncomingCall(caller, declineIntent, answerIntent));
        } else {
            Icon icon = Icon.createWithResource(context, R.drawable.ic_notification);
            builder.addAction(new Notification.Action.Builder(icon, label(declineLabel, "Decline"), declineIntent).build())
                    .addAction(new Notification.Action.Builder(icon, label(answerLabel, "Accept"), answerIntent).build());
        }

        Notification notification = builder.build();
        notification.flags |= Notification.FLAG_INSISTENT; // ring until handled
        manager.notify(NOTIFICATION_ID, notification);
    }

    public static void cancel(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) manager.cancel(NOTIFICATION_ID);
    }

    private static String label(String label, String fallback) {
        return label == null || label.isEmpty() ? fallback : label;
    }
}
