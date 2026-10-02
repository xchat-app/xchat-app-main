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
        AppPreferences.sendCallEvent("onDeclineFromNotification",
                intent.getStringExtra(IncomingCallNotification.EXTRA_SESSION_ID));
    }
}
