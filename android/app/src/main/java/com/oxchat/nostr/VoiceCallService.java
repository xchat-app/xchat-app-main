package com.oxchat.nostr;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Person;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.drawable.Icon;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import com.oxchat.lite.R;

/**
 * Foreground service held for the length of a call (voice or video).
 *
 * Android silences the microphone, and stops the camera, of an app that is
 * not on screen unless a foreground service of that type is running. Without
 * one, switching away from a call kept it "connected" while the other side
 * heard nothing. The notification is the ongoing-call notification: tap it to
 * go back to the call, or hang up from it.
 *
 * Started and stopped from Flutter through AppPreferences
 * ("startVoiceCallService" / "stopVoiceCallService").
 */
public class VoiceCallService extends Service {
    private static final String TAG = "VoiceCallService";
    private static final String CHANNEL_ID = "OngoingCallChannel";
    // 1001 and 1002 belong to PushNotificationService.
    private static final int NOTIFICATION_ID = 1003;

    public static final String EXTRA_REMOTE_NAME = "remote_name";
    public static final String EXTRA_IS_VIDEO = "is_video";
    /** Localized "Voice Call" / "Video Call", shown below the name. */
    public static final String EXTRA_CONTENT = "content";
    /** Localized "Hang Up", for the action on Android 11 and older. */
    public static final String EXTRA_HANG_UP_LABEL = "hang_up_label";
    public static final String ACTION_HANG_UP = "com.oxchat.nostr.ACTION_HANG_UP";

    /** Set by AppPreferences: tells Flutter the user hung up from the notification. */
    public static volatile Runnable onHangUp;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            // Restarted after the process died: the call died with it.
            stopSelf();
            return START_NOT_STICKY;
        }
        if (ACTION_HANG_UP.equals(intent.getAction())) {
            Runnable hangUp = onHangUp;
            if (hangUp != null) {
                hangUp.run(); // Flutter ends the call, then stops this service
            } else {
                stopSelf();
            }
            return START_NOT_STICKY;
        }

        boolean isVideo = intent.getBooleanExtra(EXTRA_IS_VIDEO, false);
        Notification notification = buildNotification(
                intent.getStringExtra(EXTRA_REMOTE_NAME),
                intent.getStringExtra(EXTRA_CONTENT),
                intent.getStringExtra(EXTRA_HANG_UP_LABEL));
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                int type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE;
                if (isVideo) type |= ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA;
                startForeground(NOTIFICATION_ID, notification, type);
            } else {
                startForeground(NOTIFICATION_ID, notification);
            }
        } catch (Exception e) {
            // Missing permission or started from the background: the call goes
            // on, it just loses the microphone when the app leaves the screen.
            Log.e(TAG, "Could not start the call service", e);
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    private Notification buildNotification(String remoteName, String content, String hangUpLabel) {
        NotificationManager manager = getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, "Ongoing calls", NotificationManager.IMPORTANCE_DEFAULT);
        channel.setSound(null, null);
        channel.enableVibration(false);
        manager.createNotificationChannel(channel);

        int piFlags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        Intent open = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (open == null) open = new Intent(this, MainActivity.class);
        open.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent openApp = PendingIntent.getActivity(this, 0, open, piFlags);
        PendingIntent hangUp = PendingIntent.getService(this, 1,
                new Intent(this, VoiceCallService.class).setAction(ACTION_HANG_UP), piFlags);

        String name = remoteName == null || remoteName.isEmpty() ? "XChat" : remoteName;
        Notification.Builder builder = new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(name)
                .setContentText(content)
                .setContentIntent(openApp)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL)
                .setUsesChronometer(true)
                .setWhen(System.currentTimeMillis());
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Person caller = new Person.Builder().setName(name).setImportant(true).build();
            builder.setStyle(Notification.CallStyle.forOngoingCall(caller, hangUp))
                    .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE);
        } else {
            String label = hangUpLabel == null || hangUpLabel.isEmpty() ? "Hang Up" : hangUpLabel;
            builder.addAction(new Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.ic_notification), label, hangUp).build());
        }
        return builder.build();
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        // Swiping the app away destroys the Flutter engine, and the call with it.
        stopSelf();
        super.onTaskRemoved(rootIntent);
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }
}
