package com.oxchat.nostr;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.Log;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.oxchat.nostr.channel.AppPreferences;
import com.oxchat.nostr.util.Constant;
import com.oxchat.nostr.util.SharedPreUtils;
import com.oxchat.nostr.util.Tools;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Objects;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugins.GeneratedPluginRegistrant;

public class MainActivity extends FlutterFragmentActivity {

    public static NewMyEngineIntentBuilder withNewEngine(Class<? extends FlutterFragmentActivity> activityClass) {
        return new NewMyEngineIntentBuilder(activityClass);
    }

    //Rewrite engine method
    public static class NewMyEngineIntentBuilder extends NewEngineIntentBuilder {

        protected NewMyEngineIntentBuilder(Class<? extends FlutterFragmentActivity> activityClass) {
            super(activityClass);
        }
    }

    public static String getFullRoute(String route, String params) {
        //Splicing parameter
        JSONObject jsonObject = new JSONObject();
        try {
            if (!TextUtils.isEmpty(params)) {
                jsonObject.put("pageParams", new JSONObject(params));
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }

        return route + "?" + jsonObject.toString();
    }

    // While this activity exists the Flutter side is running and posts its own
    // message notifications; PushNotificationService reads this to avoid
    // posting a second one for the same message.
    private static volatile int liveInstances = 0;

    public static boolean isAlive() {
        return liveInstances > 0;
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS);
        super.onCreate(savedInstanceState);
        liveInstances++;
        handleCallIntent(getIntent());
    }

    @Override
    protected void onDestroy() {
        liveInstances--;
        super.onDestroy();
    }

    @Override
    protected void onResume() {
        super.onResume();
        // Only process deep links if there's actual data
        Intent currentIntent = getIntent();
        if (currentIntent != null && currentIntent.getData() != null) {
            getOpenData(currentIntent);
            handleIntent(currentIntent);
        }
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        handleCallIntent(intent);
        // Use the passed intent parameter for deep link processing
        getOpenData(intent);
        handleIntent(intent);
    }

    // Answer tapped on a call rung from a push, when the app was not running:
    // the call itself only arrives once the app has started and synced, so
    // Flutter asks for this (takePendingAnswer) and answers that call.
    private static volatile long pendingAnswerAt = 0;

    public static boolean takePendingAnswer() {
        boolean recent = System.currentTimeMillis() - pendingAnswerAt < 60_000;
        pendingAnswerAt = 0;
        return recent;
    }

    /** Answer, from the incoming-call notification: Flutter accepts the call. */
    private void handleCallIntent(Intent intent) {
        if (intent == null || !IncomingCallNotification.ACTION_ANSWER.equals(intent.getAction())) return;
        IncomingCallNotification.cancel(this);
        String sessionId = intent.getStringExtra(IncomingCallNotification.EXTRA_SESSION_ID);
        if (sessionId == null || sessionId.isEmpty()) {
            pendingAnswerAt = System.currentTimeMillis();
            sessionId = "";
        }
        AppPreferences.sendCallEvent("onAnswerFromNotification", sessionId);
        intent.setAction(Intent.ACTION_MAIN); // not again if the activity is recreated
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine);
        flutterEngine.getPlugins().add(new AppPreferences(true));

    }

    private void getOpenData(Intent intent) {
        try {
            if (intent == null) {
                return;
            }
            
            Uri uridata = intent.getData();
            if (uridata == null) {
                return;
            }
            
            String param = uridata.toString();
            if (!TextUtils.isEmpty(param)) {
                try {
                    android.content.SharedPreferences sp = this.getSharedPreferences(SharedPreUtils.SP_NAME, Context.MODE_PRIVATE);
                    if (sp != null) {
                        SharedPreferences.Editor e = sp.edit();
                        e.putString(SharedPreUtils.PARAM_JUMP_INFO, param);
                        e.apply();
                    }
                } catch (Exception e) {
                    Log.e("scheme-", "Failed to save deep link to SharedPreferences", e);
                }
            }
        } catch (Exception e) {
            Log.e("scheme-", "Error processing deep link", e);
        }
    }

    void handleIntent(Intent intent) {
        String action = intent.getAction();
        String type = intent.getType();
        if (type != null) {
            if (Intent.ACTION_SEND.equals(action)) {
                if (type.startsWith("text/")) {//Process text types (may include image url)
                    // Process received text (may contain URLs)
                    String sharedText = intent.getStringExtra(Intent.EXTRA_TEXT);
                    if (sharedText != null && !sharedText.isEmpty()) {
                        //use url in here
                        try {
                            SharedPreUtils sp = new SharedPreUtils(this);
                            String schemeUrl = Constant.APP_SCHEME + Constant.APP_SCHEME_SHARE + URLEncoder.encode(sharedText, "UTF-8") + Constant.APP_SCHEME_SHARE_TYPE + "text";
                            SharedPreferences.Editor e = sp.getSharedPreferences().edit();
                            e.putString(SharedPreUtils.PARAM_JUMP_INFO, schemeUrl);
                            e.apply();
                            intent.removeExtra(Intent.EXTRA_TEXT);
                            //may include image url
                        } catch (Exception e) {
                            Log.e("JSONException", Objects.requireNonNull(e.getMessage()));
                        }
                    }
                } else if (type.startsWith("image/")) {
                    Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
                    if (uri != null) handleSharedImage(uri);
                    intent.removeExtra(Intent.EXTRA_STREAM);
                } else if (type.startsWith("application/")) {
                    Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
                    if (uri != null) handleSharedFile(uri);
                    intent.removeExtra(Intent.EXTRA_STREAM);
                }
            }
        }
    }

    private void handleSharedImage(Uri uri) {//share mobile local image to 0xchat
        try {
            File file = Tools.copyToCache(this, uri, "shared_image_" + System.currentTimeMillis() + ".jpg");
            SharedPreUtils sp = new SharedPreUtils(this);
            String schemeUrl = Constant.APP_SCHEME + Constant.APP_SCHEME_SHARE + Constant.APP_SCHEME_SHARE_TYPE + "image" + Constant.APP_SCHEME_SHARE_PATH + file.getAbsolutePath()
                    + Constant.APP_SCHEME_SHARE_NAME + file.getName();
            SharedPreferences.Editor e = sp.getSharedPreferences().edit();
            e.putString(SharedPreUtils.PARAM_JUMP_INFO, schemeUrl);
            e.apply();
        } catch (Exception e) {
            Log.e("io", Objects.requireNonNull(e.getMessage()));
        }
    }

    private void handleSharedFile(Uri uri) {//share mobile local file to 0xchat
        try {
            String fileName = Tools.getFileName(this, uri);
            File file = Tools.copyToCache(this, uri, fileName);
            SharedPreUtils sp = new SharedPreUtils(this);
            String schemeUrl = Constant.APP_SCHEME + Constant.APP_SCHEME_SHARE + Constant.APP_SCHEME_SHARE_TYPE + "file" + Constant.APP_SCHEME_SHARE_PATH + file.getAbsolutePath()
                    + Constant.APP_SCHEME_SHARE_NAME + fileName;
            SharedPreferences.Editor e = sp.getSharedPreferences().edit();
            e.putString(SharedPreUtils.PARAM_JUMP_INFO, schemeUrl);
            e.apply();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
