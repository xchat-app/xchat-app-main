package com.oxchat.nostr.channel;

import android.app.Activity;
import android.app.ActivityManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import androidx.annotation.NonNull;

import com.oxchat.nostr.MultiEngineActivity;
import com.oxchat.nostr.util.SharedPreUtils;
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
    private Context mContext;
    private Activity mActivity;
    private MethodChannel.Result mMethodChannelResult;
    private MethodChannel mChannel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        mContext = binding.getApplicationContext();
        mChannel = new MethodChannel(binding.getBinaryMessenger(), OX_PERFERENCES_CHANNEL);
        mChannel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {

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
                String title = "";
                String content = "";
                if (paramsMap != null && paramsMap.containsKey(VoiceCallService.VOICE_TITLE_STR)) {
                    title = (String) paramsMap.get(VoiceCallService.VOICE_TITLE_STR);
                }
                if (paramsMap != null && paramsMap.containsKey(VoiceCallService.VOICE_CONTENT_STR)) {
                    content = (String) paramsMap.get(VoiceCallService.VOICE_CONTENT_STR);
                }
                Intent serviceIntent = new Intent(mContext, VoiceCallService.class);
                serviceIntent.putExtra(VoiceCallService.VOICE_TITLE_STR, title);
                serviceIntent.putExtra(VoiceCallService.VOICE_CONTENT_STR, content);
                mContext.startForegroundService(serviceIntent);
            }
            case "stopVoiceCallService" -> {
                Intent serviceIntent = new Intent(mContext, VoiceCallService.class);
                mContext.stopService(serviceIntent);
            }
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
                Intent serviceIntent = new Intent(mContext, PushNotificationService.class);
                mContext.stopService(serviceIntent);
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
