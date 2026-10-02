package com.oxchat.nostr;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

import com.oxchat.nostr.channel.AppPreferences;

/** Decline, from the incoming-call notification: no need to open the app. */
public class CallActionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!IncomingCallNotification.ACTION_DECLINE.equals(intent.getAction())) return;
        IncomingCallNotification.cancel(context);
        // Without a session (rung from a push, the app not running) there is
        // no call here to reject yet: silencing it is all Decline can do.
        String sessionId = intent.getStringExtra(IncomingCallNotification.EXTRA_SESSION_ID);
        if (sessionId != null && !sessionId.isEmpty()) {
            AppPreferences.sendCallEvent("onDeclineFromNotification", sessionId);
        }
    }
}
