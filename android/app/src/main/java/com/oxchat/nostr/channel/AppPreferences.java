package com.oxchat.nostr.channel;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import com.oxchat.nostr.MultiEngineActivity;
import com.oxchat.nostr.util.SharedPreUtils;
import com.oxchat.nostr.IncomingCallNotification;
import com.oxchat.nostr.VoiceCallService;
import com.oxchat.lite.PushNotificationService;
import com.oxchat.lite.KeystoreHelper;
import java.util.HashMap;
import java.util.List;

import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Title: ApplicationPreferences
 * Description: TODO(Fill in by oneself)
 * Copyright: Copyright (c) 2023
 *
 * @author john
 * @CheckItem Fill in by oneself
 * @since JDK1.8
 */
public class AppPreferences implements MethodChannel.MethodCallHandler, FlutterPlugin, ActivityAware {
    private static final String OX_PERFERENCES_CHANNEL = "com.oxchat.global/perferences";
    // Its own channel: the Dart side of the one above already has a handler
    // (push AUTH), and a channel takes only one.
    private static final String OX_CALL_CHANNEL = "com.oxchat.global/call";
    private Context mContext;
    private Activity mActivity;
    private MethodChannel.Result mMethodChannelResult;
    private MethodChannel mChannel;
    private MethodChannel mCallChannel;
    private static volatile MethodChannel sCallChannel;
    // Only the main engine runs the call code; MultiEngineActivity's second
    // engine must not take the call events over.
    private final boolean ownsCallEvents;

    public AppPreferences() {
        this(false);
    }

    public AppPreferences(boolean ownsCallEvents) {
        this.ownsCallEvents = ownsCallEvents;
    }

    /**
     * Tells Flutter about a call action taken outside the app (the call
     * notifications' Hang Up, Answer and Decline). Returns false if no
     * Flutter engine is listening.
     */
    public static boolean sendCallEvent(String method, Object arguments) {
        MethodChannel channel = sCallChannel;
        if (channel == null) return false;
        new Handler(Looper.getMainLooper()).post(() -> channel.invokeMethod(method, arguments));
        return true;
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        mContext = binding.getApplicationContext();
        mChannel = new MethodChannel(binding.getBinaryMessenger(), OX_PERFERENCES_CHANNEL);
        mChannel.setMethodCallHandler(this);
        mCallChannel = new MethodChannel(binding.getBinaryMessenger(), OX_CALL_CHANNEL);
        mCallChannel.setMethodCallHandler(this);
        if (ownsCallEvents) sCallChannel = mCallChannel;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (mCallChannel != null) {
            mCallChannel.setMethodCallHandler(null);
            if (sCallChannel == mCallChannel) sCallChannel = null;
            mCallChannel = null;
        }
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        mActivity = binding.getActivity();

    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {

    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {

    }

    @Override
    public void onDetachedFromActivity() {

    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        mMethodChannelResult = result;
        HashMap paramsMap = null;
        if (call.arguments instanceof HashMap) {
            paramsMap = (HashMap) call.arguments;
        }
        switch (call.method) {
            case "isAppInBackground" -> {
                boolean isAppInBackground = isAppInBackground();
                result.success(isAppInBackground);
            }
            case "startVoiceCallService" -> {
                Intent serviceIntent = new Intent(mContext, VoiceCallService.class);
                if (paramsMap != null) {
                    serviceIntent.putExtra(VoiceCallService.EXTRA_REMOTE_NAME, (String) paramsMap.get("remoteName"));
                    serviceIntent.putExtra(VoiceCallService.EXTRA_IS_VIDEO, Boolean.TRUE.equals(paramsMap.get("isVideo")));
                    serviceIntent.putExtra(VoiceCallService.EXTRA_CONTENT, (String) paramsMap.get("content"));
                    serviceIntent.putExtra(VoiceCallService.EXTRA_HANG_UP_LABEL, (String) paramsMap.get("hangUpLabel"));
                }
                try {
                    mContext.startForegroundService(serviceIntent);
                    result.success(true);
                } catch (Exception e) {
                    Log.e("AppPreferences", "Could not start the call service", e);
                    result.success(false);
                }
            }
            case "stopVoiceCallService" -> {
                Intent serviceIntent = new Intent(mContext, VoiceCallService.class);
                mContext.stopService(serviceIntent);
                result.success(null);
            }
            case "showIncomingCall" -> {
                if (paramsMap != null) {
                    IncomingCallNotification.show(mContext,
                            (String) paramsMap.get("sessionId"),
                            (String) paramsMap.get("remoteName"),
                            Boolean.TRUE.equals(paramsMap.get("isVideo")),
                            (String) paramsMap.get("content"),
                            (String) paramsMap.get("answerLabel"),
                            (String) paramsMap.get("declineLabel"));
                }
                result.success(null);
            }
            case "cancelIncomingCall" -> {
                IncomingCallNotification.cancel(mContext);
                result.success(null);
            }
            case "takePendingCallAnswer" -> result.success(com.oxchat.nostr.MainActivity.takePendingAnswer());
            case "startPushNotificationService" -> {
                String serverRelay = "";
                String pubkey = "";
                String privkey = "";
                if (paramsMap != null) {
                    if (paramsMap.containsKey("serverRelay")) {
                        serverRelay = (String) paramsMap.get("serverRelay");
                    }
                    if (paramsMap.containsKey("pubkey")) {
                        pubkey = (String) paramsMap.get("pubkey");
                    }
                    if (paramsMap.containsKey("privkey")) {
                        privkey = (String) paramsMap.get("privkey");
                    }
                }
                // Store private key in Android Keystore (encrypted in memory, not in SharedPreferences)
                if (!privkey.isEmpty()) {
                    boolean success = KeystoreHelper.storePrivateKey(mContext, privkey);
                    if (success) {
                        Log.d("AppPreferences", "Private key stored in Android Keystore");
                    } else {
                        Log.e("AppPreferences", "Failed to store private key in Android Keystore");
                    }
                }
                // For Android, deviceId is optional, will use pubkey if not provided
                Intent serviceIntent = new Intent(mContext, PushNotificationService.class);
                serviceIntent.putExtra(PushNotificationService.EXTRA_SERVER_RELAY, serverRelay);
                // deviceId is optional for Android, service will use pubkey if not provided
                serviceIntent.putExtra(PushNotificationService.EXTRA_PUBKEY, pubkey);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    mContext.startForegroundService(serviceIntent);
                } else {
                    mContext.startService(serviceIntent);
                }
                result.success(true);
            }
            case "stopPushNotificationService" -> {
                Intent stopIntent = new Intent(mContext, PushNotificationService.class);
                stopIntent.setAction(PushNotificationService.ACTION_STOP);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    mContext.startForegroundService(stopIntent);
                } else {
                    mContext.startService(stopIntent);
                }
                result.success(true);
            }
            case "sendAuthResponse" -> {
                String authJson = "";
                if (paramsMap != null && paramsMap.containsKey("authJson")) {
                    authJson = (String) paramsMap.get("authJson");
                }
                // Send auth response to push service
                Intent serviceIntent = new Intent(mContext, PushNotificationService.class);
                serviceIntent.setAction("com.oxchat.nostr.SEND_AUTH");
                serviceIntent.putExtra("authJson", authJson);
                mContext.startService(serviceIntent);
                result.success(true);
            }
            case "getPendingAuthChallenge" -> {
                // Get pending AUTH challenge from SharedPreferences
                android.content.SharedPreferences prefs = mContext.getSharedPreferences("push_service", Context.MODE_PRIVATE);
                String challenge = prefs.getString("auth_challenge", "");
                String relay = prefs.getString("auth_relay", "");
                if (!challenge.isEmpty() && !relay.isEmpty()) {
                    HashMap<String, String> resultMap = new HashMap<>();
                    resultMap.put("challenge", challenge);
                    resultMap.put("relay", relay);
                    result.success(resultMap);
                } else {
                    result.success(null);
                }
            }
            case "clearPendingAuthChallenge" -> {
                // Clear pending AUTH challenge
                android.content.SharedPreferences prefs = mContext.getSharedPreferences("push_service", Context.MODE_PRIVATE);
                prefs.edit()
                    .remove("auth_challenge")
                    .remove("auth_relay")
                    .apply();
                result.success(true);
            }
            case "getAppOpenURL" -> {
                SharedPreferences preferences = mContext.getSharedPreferences(SharedPreUtils.SP_NAME, Context.MODE_PRIVATE);
                String jumpInfo = preferences.getString(SharedPreUtils.PARAM_JUMP_INFO, "");
                SharedPreferences.Editor e = preferences.edit();
                e.remove(SharedPreUtils.PARAM_JUMP_INFO);
                e.apply();
                if (mMethodChannelResult != null) {
                    mMethodChannelResult.success(jumpInfo);
                    mMethodChannelResult = null;
                }
            }
            case "changeTheme" -> {
                int themeStyle = 0;
                if (paramsMap != null && paramsMap.containsKey("themeStyle")) {
                    themeStyle = (int) paramsMap.get("themeStyle");
                }
                SharedPreferences preferences = mContext.getSharedPreferences(SharedPreUtils.SP_NAME, Context.MODE_PRIVATE);
                preferences.edit().putInt("themeStyle", themeStyle);
                if (themeStyle == 0) {
                    //TODO light
                } else {
                    //TODO Dark
                }
            }
            case "showFlutterActivity" -> {
                String route = null;
                if (paramsMap != null && paramsMap.containsKey("route")) {
                    route = (String) paramsMap.get("route");
                }
                String params = null;
                if (paramsMap.containsKey("params")) {
                    params = (String) paramsMap.get("params");
                }
                Intent intent = MultiEngineActivity
                        .withNewEngine(MultiEngineActivity.class)
                        .initialRoute(MultiEngineActivity.getFullRoute(route, params))
                        .build(mContext);
                //intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                mActivity.startActivity(intent);
            }
        }
    }

    private boolean isAppInBackground() {
        ActivityManager activityManager = (ActivityManager) mActivity.getSystemService(Context.ACTIVITY_SERVICE);
        List<ActivityManager.RunningAppProcessInfo> runningApps = activityManager.getRunningAppProcesses();
        for (ActivityManager.RunningAppProcessInfo processInfo : runningApps) {
            if (processInfo.processName.equals(mActivity.getPackageName())) {
                if (processInfo.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) {
                    //ActivityState", "App is in the foreground.  is see
                    return false;
                } else {
                    //ActivityState", "App is in the background.
                    return true;
                }
            }
        }
        return false;
    }
}
