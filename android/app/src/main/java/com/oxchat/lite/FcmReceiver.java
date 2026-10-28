package com.oxchat.lite;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.Nullable;

import com.oxchat.nostr.IncomingCallNotification;
import com.oxchat.nostr.MainActivity;

/**
 * Firebase Cloud Messaging without the Firebase SDK, the way 0xchat's FOSS
 * embedded distributor (org.unifiedpush.android:foss-embedded-fcm-distributor)
 * does it: ask Google Play services for a token through its intents, and take
 * the messages it delivers here.
 *
 * The push relay (nopu) reaches this phone through PushNotificationService's
 * socket. Once the system has stopped that service, nopu sees no one online and
 * hands the push to its gateway, which sends a data message here for the token
 * the app filed as "fcm:<token>". The message only says that something arrived:
 * post the notification the service would have, and start the service again.
 */
public class FcmReceiver extends BroadcastReceiver {
    private static final String TAG = "FcmReceiver";
    // Firebase project xchat-f8b7a; the push gateway sends with its key.
    private static final String SENDER_ID = "426689947325";
    private static final String GMS_PACKAGE = "com.google.android.gms";
    private static final String ACTION_TOKEN_REQUEST = "com.google.iid.TOKEN_REQUEST";
    private static final String ACTION_REGISTRATION = "com.google.android.c2dm.intent.REGISTRATION";
    private static final String ACTION_RECEIVE = "com.google.android.c2dm.intent.RECEIVE";
    // Google Play services prefixes the token with the request id it was given.
    private static final String KID = "|ID|1|";
    private static final String PREFS_NAME = "push_service";
    private static final String KEY_TOKEN = "fcm_token";

    /**
     * Ask Google Play services for a token; it answers later with a
     * REGISTRATION broadcast. Returns false on a phone without them.
     */
    public static boolean requestToken(Context context) {
        try {
            context.getPackageManager().getPackageInfo(GMS_PACKAGE, 0);
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
        Intent intent = new Intent(ACTION_TOKEN_REQUEST);
        intent.setPackage(GMS_PACKAGE);
        intent.putExtra("app", PendingIntent.getBroadcast(context, 0, new Intent(), PendingIntent.FLAG_IMMUTABLE));
        intent.putExtra("sender", SENDER_ID);
        intent.putExtra("subtype", SENDER_ID);
        intent.putExtra("scope", "*");
        intent.putExtra("kid", KID);
        context.sendBroadcast(intent);
        return true;
    }

    /** The last token Google Play services gave, or null. */
    @Nullable
    public static String getToken(Context context) {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).getString(KEY_TOKEN, null);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (ACTION_REGISTRATION.equals(action)) {
            String token = intent.getStringExtra("registration_id");
            if (token == null || token.isEmpty()) {
                Log.e(TAG, "No FCM token: " + intent.getStringExtra("error"));
                return;
            }
            if (token.startsWith(KID)) token = token.substring(KID.length() + 1);
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit().putString(KEY_TOKEN, token).apply();
            Log.d(TAG, "Got an FCM token");
        } else if (ACTION_RECEIVE.equals(action)) {
            if (!"push".equals(intent.getStringExtra("xchat"))) return;
            onPush(context, intent);
        }
    }

    private void onPush(Context context, Intent intent) {
        // A call offer would carry its k tag, but nopu does not pass the tag
        // to the gateway yet, so for now a call shows as "New message".
        final boolean isCall = "25050".equals(intent.getStringExtra("k"));
        if (PushNotificationService.isAppProcessRunning(context)) {
            Log.d(TAG, "App on screen, skipping the notification");
        } else if (MainActivity.isAlive()) {
            // Alive in the background: its own connection may bring the
            // message in with the sender's name. Stand in only if it posts
            // nothing, as the push service does.
            final PendingResult pending = goAsync();
            final long receivedAt = System.currentTimeMillis();
            new Handler(Looper.getMainLooper()).postDelayed(() -> {
                try {
                    if (!PushNotificationService.isAppProcessRunning(context)
                            && !PushNotificationService.hasAppNotificationSince(context, receivedAt - 3000)) {
                        notify(context, isCall);
                    }
                } finally {
                    pending.finish();
                }
            }, PushNotificationService.APP_NOTIFICATION_GRACE_MS);
        } else {
            notify(context, isCall);
        }
        PushNotificationService.startFromSavedConfig(context);
    }

    private static void notify(Context context, boolean isCall) {
        if (isCall) {
            IncomingCallNotification.showFromPush(context);
        } else {
            PushNotificationService.showNewMessageNotification(context);
        }
    }
}
