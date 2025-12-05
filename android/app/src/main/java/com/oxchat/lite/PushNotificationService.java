package com.oxchat.lite;

import android.app.ActivityManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.List;

import androidx.core.app.NotificationCompat;

import com.oxchat.lite.R;
import com.oxchat.lite.KeystoreHelper;
import com.oxchat.nostr.MainActivity;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Random;
import java.util.concurrent.TimeUnit;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

import fr.acinq.secp256k1.Secp256k1;

/**
 * Foreground service for push notification monitoring
 * Connects to push serverRelay via WebSocket and listens for events
 */
public class PushNotificationService extends Service {
    private static final String TAG = "PushNotificationService";
    private static final String CHANNEL_ID = "PushNotificationServiceChannel";
    private static final String PUSH_NOTIFICATION_CHANNEL_ID = "PushNotificationChannel";
    
    // Jackson ObjectMapper for JSON serialization (matching nostr-java EventJsonMapper)
    private static final ObjectMapper JSON_MAPPER = new ObjectMapper();
    private static final JsonNodeFactory JSON_NODE_FACTORY = JsonNodeFactory.instance;
    private static final int NOTIFICATION_ID = 1001;
    private static final int PUSH_NOTIFICATION_ID = 1002;
    
    public static final String EXTRA_SERVER_RELAY = "server_relay";
    public static final String EXTRA_DEVICE_ID = "device_id";
    public static final String EXTRA_PUBKEY = "pubkey";
    
    private WebSocket webSocket;
    private OkHttpClient httpClient;
    private String serverRelay;
    private String deviceId;
    private String pubkey;
    private String subscriptionId;
    private Handler reconnectHandler;
    private Runnable reconnectRunnable;
    private static final long RECONNECT_DELAY_MS = 5000; // 5 seconds
    private String pendingAuthChallenge;
    private String authEventId; // Track AUTH event ID to match OK response
    private boolean regenerateSubscriptionId; // Flag to regenerate subscription ID after AUTH
    private boolean isConnecting = false; // Track if we're currently connecting
    private boolean isReconnecting = false; // Track if we're reconnecting (to avoid duplicate reconnects)
    private Secp256k1 secp256k1; // For Schnorr signature
    private Handler authRetryHandler; // Handler for retrying AUTH challenge when privatekey is not available
    private Runnable authRetryRunnable; // Runnable for retrying AUTH challenge

    private static final String PREFS_NAME = "push_service";
    private static final String KEY_SERVER_RELAY = "server_relay";
    private static final String KEY_DEVICE_ID = "device_id";
    private static final String KEY_PUBKEY = "pubkey";
    // Note: private key is stored in Android Keystore, not in SharedPreferences
    
    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "PushNotificationService created");
        createNotificationChannel();
        
        httpClient = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS)
                .build();
        
        reconnectHandler = new Handler(Looper.getMainLooper());
        authRetryHandler = new Handler(Looper.getMainLooper());
        
        // Initialize secp256k1 for Schnorr signature
        try {
            secp256k1 = Secp256k1.get();
            Log.d(TAG, "Secp256k1 initialized");
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize Secp256k1", e);
        }
        
        // Load config from SharedPreferences early in onCreate
        // This ensures privatekey is available even if Service is restarted by system
        loadConfigFromPrefs();
        
        // If config exists, try to start the service
        if (serverRelay != null && !serverRelay.isEmpty() && pubkey != null && !pubkey.isEmpty()) {
            Log.d(TAG, "Service restarted by system, config loaded from prefs in onCreate");
            if (deviceId == null || deviceId.isEmpty()) {
                deviceId = pubkey;
            }
            // Start foreground service and connect
            startForeground(NOTIFICATION_ID, createNotification());
            if (!isConnecting && webSocket == null) {
                Log.d(TAG, "Auto-connecting to relay after system restart: " + serverRelay);
                connectToRelay();
            }
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        Log.d(TAG, "PushNotificationService started");
        
        if (intent != null) {
            // New start from Flutter app
            serverRelay = intent.getStringExtra(EXTRA_SERVER_RELAY);
            deviceId = intent.getStringExtra(EXTRA_DEVICE_ID);
            pubkey = intent.getStringExtra(EXTRA_PUBKEY);
            persistConfig();
            
            if (serverRelay == null || serverRelay.isEmpty() || pubkey == null || pubkey.isEmpty()) {
                Log.e(TAG, "Missing required config, cannot start service");
                stopSelf();
                return START_STICKY;
            }
            
            // For Android, if deviceId is not provided, use pubkey as deviceId
            if (deviceId == null || deviceId.isEmpty()) {
                deviceId = pubkey;
            }
            
            // Only connect if not already connecting
            if (!isConnecting && webSocket == null) {
                Log.d(TAG, "Connecting to relay: " + serverRelay + ", deviceId: " + deviceId);
                connectToRelay();
            } else {
                Log.d(TAG, "WebSocket already connected or connecting, skipping connection");
            }
            
            // Start foreground service
            startForeground(NOTIFICATION_ID, createNotification());
        } else {
            // Service restarted by system
            // Config should already be loaded in onCreate(), but double-check
            if (serverRelay == null || serverRelay.isEmpty() || pubkey == null || pubkey.isEmpty()) {
                loadConfigFromPrefs();
                if (serverRelay == null || serverRelay.isEmpty() || pubkey == null || pubkey.isEmpty()) {
                    Log.e(TAG, "Missing required config after system restart, cannot start service");
                    stopSelf();
                    return START_STICKY;
                }
            }
            // Service should already be started in onCreate(), just ensure foreground
            startForeground(NOTIFICATION_ID, createNotification());
        }
        
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        Log.d(TAG, "PushNotificationService destroyed");
        disconnectFromRelay();
        if (reconnectRunnable != null) {
            reconnectHandler.removeCallbacks(reconnectRunnable);
        }
        if (authRetryRunnable != null) {
            authRetryHandler.removeCallbacks(authRetryRunnable);
        }
        isConnecting = false;
        isReconnecting = false;
        // Clear private key from file system when service is destroyed
        KeystoreHelper.clearPrivateKey(this);
        stopForeground(true);
    }

    /**
     * Create notification channel for Android O and above
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager == null) return;
            
            // Channel for foreground service
            NotificationChannel serviceChannel = new NotificationChannel(
                    CHANNEL_ID,
                    "Push Notification Service",
                    NotificationManager.IMPORTANCE_LOW
            );
            serviceChannel.setDescription("Service for monitoring push notifications");
            serviceChannel.setShowBadge(false);
            manager.createNotificationChannel(serviceChannel);
            
            // Channel for push notifications (higher priority)
            NotificationChannel pushChannel = new NotificationChannel(
                    PUSH_NOTIFICATION_CHANNEL_ID,
                    "Push Notifications",
                    NotificationManager.IMPORTANCE_HIGH
            );
            pushChannel.setDescription("Notifications for new messages");
            pushChannel.setShowBadge(true);
            pushChannel.enableLights(true);
            pushChannel.enableVibration(true);
            manager.createNotificationChannel(pushChannel);
        }
    }

    /**
     * Create foreground notification
     */
    private Notification createNotification() {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        notificationIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                flags
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(getString(R.string.push_service_title))
                .setContentText(getString(R.string.push_service_text))
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE);

        return builder.build();
    }

    /**
     * Connect to WebSocket relay
     */
    private void connectToRelay() {
        // Avoid duplicate connections
        if (isConnecting) {
            Log.d(TAG, "Already connecting, skipping duplicate connection attempt");
            return;
        }
        
        // If WebSocket is already connected and healthy, don't reconnect
        if (webSocket != null) {
            Log.d(TAG, "WebSocket already exists, closing existing connection first");
            isReconnecting = true; // Mark as reconnecting to avoid duplicate reconnect calls
            webSocket.close(1000, "Reconnecting");
            webSocket = null;
        }
        
        isConnecting = true;
        
        try {
            Request request = new Request.Builder()
                    .url(serverRelay)
                    .build();
            
            webSocket = httpClient.newWebSocket(request, new WebSocketListener() {
                @Override
                public void onOpen(WebSocket webSocket, Response response) {
                    Log.d(TAG, "WebSocket connected to: " + serverRelay);
                    isConnecting = false;
                    isReconnecting = false;
                    sendSubscriptionRequest();
                }

                @Override
                public void onMessage(WebSocket webSocket, String text) {
                    Log.d(TAG, "Received message: " + text);
                    handleMessage(text);
                }

                @Override
                public void onMessage(WebSocket webSocket, okio.ByteString bytes) {
                    Log.d(TAG, "Received bytes message");
                    handleMessage(bytes.utf8());
                }

                @Override
                public void onClosing(WebSocket webSocket, int code, String reason) {
                    Log.d(TAG, "WebSocket closing: " + code + " " + reason);
                    webSocket.close(1000, null);
                }

                @Override
                public void onClosed(WebSocket webSocket, int code, String reason) {
                    Log.d(TAG, "WebSocket closed: " + code + " " + reason);
                    isConnecting = false;
                    // Only schedule reconnect if we're not already reconnecting (to avoid duplicate reconnects)
                    if (!isReconnecting) {
                        scheduleReconnect();
                    } else {
                        isReconnecting = false;
                    }
                }

                @Override
                public void onFailure(WebSocket webSocket, Throwable t, Response response) {
                    Log.e(TAG, "WebSocket failure", t);
                    isConnecting = false;
                    isReconnecting = false;
                    scheduleReconnect();
                }
            });
        } catch (Exception e) {
            Log.e(TAG, "Failed to connect to WebSocket", e);
            isConnecting = false;
            isReconnecting = false;
            scheduleReconnect();
        }
    }

    /**
     * Send subscription request to relay
     * Format: ["REQ", subscriptionId, {"kinds": [20284], "#h": [pubkey], "since": now}]
     * subscriptionId is a random number
     */
    private void sendSubscriptionRequest() {
        if (pubkey == null) {
            Log.e(TAG, "Cannot send subscription: missing pubkey");
            return;
        }
        
        try {
            // Generate random subscription ID
            if (subscriptionId == null || regenerateSubscriptionId) {
                subscriptionId = generateRandomHex(16);
                regenerateSubscriptionId = false;
            }
            
            // Build Request: ["REQ", subscriptionId, {"kinds": [20285, 20284], "#h": [pubkey]}]
            JSONArray requestArray = new JSONArray();
            requestArray.put("REQ");
            requestArray.put(subscriptionId);
            
            JSONObject filter = new JSONObject();
            // NIP-29 group events
            JSONArray kindsArray = new JSONArray();
            kindsArray.put(20285);
            kindsArray.put(20284);
            filter.put("kinds", kindsArray);
            
            // h tag contains any of the groupIds (pubkey)
            JSONArray hArray = new JSONArray();
            hArray.put(pubkey);
            filter.put("#h", hArray);
            
            requestArray.put(filter);
            
            String requestMessage = requestArray.toString();
            Log.d(TAG, "Sending subscription request: " + requestMessage);
            
            if (webSocket != null) {
                webSocket.send(requestMessage);
            }
        } catch (JSONException e) {
            Log.e(TAG, "Failed to create subscription request", e);
        }
    }

    /**
     * Handle incoming WebSocket messages
     */
    private void handleMessage(String message) {
        try {
            JSONArray jsonArray = new JSONArray(message);
            String messageType = jsonArray.getString(0);
            
            if ("EVENT".equals(messageType)) {
                // Received an event, only wake app if process is not running
                Log.d(TAG, "Received EVENT");
                if (!isAppProcessRunning()) {
                    Log.d(TAG, "App process not running, activating");
                    activateApp();
                } else {
                    Log.d(TAG, "App process already running, skipping activation");
                }
            } else if ("EOSE".equals(messageType)) {
                // End of stored events
                Log.d(TAG, "End of stored events");
            } else if ("NOTICE".equals(messageType)) {
                String notice = jsonArray.getString(1);
                Log.d(TAG, "Relay notice: " + notice);
            } else if ("CLOSED".equals(messageType)) {
                Log.d(TAG, "Subscription closed");
            } else if ("AUTH".equals(messageType)) {
                // Handle AUTH challenge
                String challenge = jsonArray.getString(1);
                Log.d(TAG, "Received AUTH challenge: " + challenge);
                handleAuthChallenge(challenge);
            } else if ("OK".equals(messageType)) {
                // Handle OK response, check if it's AUTH response
                if (jsonArray.length() >= 3) {
                    String eventId = jsonArray.getString(1);
                    boolean status = jsonArray.getBoolean(2);
                    String okMessage = jsonArray.length() > 3 ? jsonArray.getString(3) : "";
                    Log.d(TAG, "Received OK: eventId=" + eventId + ", status=" + status + ", message=" + okMessage);
                    // If this is AUTH OK response and successful, resend subscription request
                    if (status && authEventId != null && authEventId.equals(eventId)) {
                        Log.d(TAG, "AUTH successful, resending subscription request");
                        authEventId = null;
                        pendingAuthChallenge = null;
                        regenerateSubscriptionId = true;
                        sendSubscriptionRequest();
                    }
                }
            }
        } catch (JSONException e) {
            Log.e(TAG, "Failed to parse message: " + message, e);
        }
    }

    /**
     * Handle AUTH challenge by creating and sending AUTH response
     * If privatekey is not available, retry after a delay
     */
    private void handleAuthChallenge(String challenge) {
        Log.d(TAG, "Handling AUTH challenge: challenge=" + challenge + ", relay=" + serverRelay);
        
        // Store challenge for retry
        pendingAuthChallenge = challenge;
        
        // Get private key from Android Keystore (stored in private file)
        String privkey = getPrivateKey();
        if (privkey == null || privkey.isEmpty()) {
            Log.w(TAG, "Private key not found in Android Keystore file, will retry after delay");
            Log.w(TAG, "Private key may not have been stored yet. Retrying in 2 seconds...");
            
            // Cancel any existing retry
            if (authRetryRunnable != null) {
                authRetryHandler.removeCallbacks(authRetryRunnable);
            }
            
            // Retry after 2 seconds
            authRetryRunnable = new Runnable() {
                @Override
                public void run() {
                    if (pendingAuthChallenge != null) {
                        Log.d(TAG, "Retrying AUTH challenge handling");
                        handleAuthChallenge(pendingAuthChallenge);
                    }
                }
            };
            authRetryHandler.postDelayed(authRetryRunnable, 2000);
            return;
        }
        
        // Clear pending challenge and retry runnable
        pendingAuthChallenge = null;
        if (authRetryRunnable != null) {
            authRetryHandler.removeCallbacks(authRetryRunnable);
            authRetryRunnable = null;
        }
        
        try {
            // Create AUTH event
            String authJson = createAuthEvent(challenge, serverRelay, pubkey, privkey);
            if (authJson != null && !authJson.isEmpty()) {
                Log.d(TAG, "Created AUTH event, sending to relay");
                sendAuthResponse(authJson);
            } else {
                Log.e(TAG, "Failed to create AUTH event");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error handling AUTH challenge", e);
        }
    }

    /**
     * Create AUTH event for NIP-42
     * Uses Jackson ObjectMapper for JSON serialization (matching nostr-java)
     * Format: ["AUTH", {"id": "...", "pubkey": "...", "created_at": ..., "kind": 22242, "tags": [["relay", "..."], ["challenge", "..."]], "content": "", "sig": "..."}]
     * Reference: nostr-java NIP42.createCanonicalAuthenticationEvent() and CanonicalAuthenticationMessage
     */
    private String createAuthEvent(String challenge, String relay, String pubkey, String privkey) {
        try {
            // Get current timestamp in seconds
            long createdAt = System.currentTimeMillis() / 1000;
            
            // Create tags: [["relay", relay], ["challenge", challenge]]
            // Using JSONArray for calculateEventId compatibility, then convert to Jackson format
            JSONArray tags = new JSONArray();
            JSONArray relayTag = new JSONArray();
            relayTag.put("relay");
            relayTag.put(relay);
            tags.put(relayTag);
            JSONArray challengeTag = new JSONArray();
            challengeTag.put("challenge");
            challengeTag.put(challenge);
            tags.put(challengeTag);
            
            // Calculate event ID: SHA256 of [0, pubkey, created_at, kind, tags, content]
            // This must be done before creating the final event JSON
            String eventId = calculateEventId(pubkey.toLowerCase(), createdAt, 22242, tags, "");
            if (eventId == null) {
                Log.e(TAG, "Failed to calculate event ID");
                return null;
            }
            
            // Sign the event ID with private key
            String signature = signEventId(eventId, privkey);
            if (signature == null || signature.isEmpty()) {
                Log.e(TAG, "Failed to sign event ID");
                return null;
            }
            
            // Create event JSON using Jackson (matching nostr-java format)
            ObjectNode eventNode = JSON_NODE_FACTORY.objectNode();
            eventNode.put("id", eventId);
            eventNode.put("pubkey", pubkey.toLowerCase());
            eventNode.put("created_at", createdAt);
            eventNode.put("kind", 22242);
            
            // Convert tags to Jackson ArrayNode format
            ArrayNode tagsNode = JSON_NODE_FACTORY.arrayNode();
            for (int i = 0; i < tags.length(); i++) {
                JSONArray tagArray = tags.getJSONArray(i);
                ArrayNode tagNode = JSON_NODE_FACTORY.arrayNode();
                for (int j = 0; j < tagArray.length(); j++) {
                    tagNode.add(tagArray.getString(j));
                }
                tagsNode.add(tagNode);
            }
            eventNode.set("tags", tagsNode);
            eventNode.put("content", "");
            eventNode.put("sig", signature);
            
            // Create AUTH message: ["AUTH", event]
            // Reference: nostr-java CanonicalAuthenticationMessage.encode()
            ArrayNode authArray = JSON_NODE_FACTORY.arrayNode();
            authArray.add("AUTH");
            authArray.add(eventNode);
            
            // Serialize to JSON string using Jackson
            String authJson = JSON_MAPPER.writeValueAsString(authArray);
            
            // Store event ID for OK response matching
            authEventId = eventId;
            
            Log.d(TAG, "Created AUTH event JSON: " + authJson);
            return authJson;
        } catch (JsonProcessingException e) {
            Log.e(TAG, "Failed to serialize AUTH event", e);
            return null;
        } catch (JSONException e) {
            Log.e(TAG, "Failed to create AUTH event", e);
            return null;
        }
    }

    /**
     * Calculate event ID: SHA256 of [0, pubkey, created_at, kind, tags, content]
     * Uses Jackson ObjectMapper for serialization (matching nostr-java EventSerializer)
     * Reference: nostr-java EventSerializer.serialize() and computeEventId()
     */
    private String calculateEventId(String pubkey, long createdAt, int kind, JSONArray tags, String content) {
        try {
            // Ensure pubkey is lowercase (matching nostr-java and Flutter)
            String pubkeyLower = pubkey.toLowerCase();
            
            // Create array node: [0, pubkey, created_at, kind, tags, content]
            // Reference: nostr-java EventSerializer.serialize() using JsonNodeFactory
            ArrayNode arrayNode = JSON_NODE_FACTORY.arrayNode();
            arrayNode.add(0); // Protocol version
            arrayNode.add(pubkeyLower);
            arrayNode.add(createdAt);
            arrayNode.add(kind);
            
            // Convert JSONArray tags to Jackson ArrayNode
            // Tags format: [["relay","..."],["challenge","..."]]
            ArrayNode tagsNode = JSON_NODE_FACTORY.arrayNode();
            for (int i = 0; i < tags.length(); i++) {
                JSONArray tagArray = tags.getJSONArray(i);
                ArrayNode tagNode = JSON_NODE_FACTORY.arrayNode();
                for (int j = 0; j < tagArray.length(); j++) {
                    Object tagValue = tagArray.get(j);
                    if (tagValue instanceof String) {
                        tagNode.add((String) tagValue);
                    } else if (tagValue instanceof Number) {
                        tagNode.add(((Number) tagValue).longValue());
                    } else {
                        tagNode.add(tagValue.toString());
                    }
                }
                tagsNode.add(tagNode);
            }
            arrayNode.add(tagsNode);
            arrayNode.add(content);
            
            // Serialize to JSON string using Jackson (matching nostr-java)
            // Reference: nostr-java EventSerializer: MAPPER.writeValueAsString(arrayNode)
            String serialized = JSON_MAPPER.writeValueAsString(arrayNode);
            
            // Debug: Log serialized JSON to compare with nostr-java/Flutter
            Log.d(TAG, "Event ID calculation - serialized JSON: " + serialized);
            
            // SHA256 hash of UTF-8 encoded string
            // Reference: nostr-java EventSerializer.computeEventId()
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(serialized.getBytes(StandardCharsets.UTF_8));
            
            // Convert to hex string (lowercase)
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) {
                    hexString.append('0');
                }
                hexString.append(hex);
            }
            
            String eventId = hexString.toString();
            Log.d(TAG, "Calculated event ID: " + eventId);
            return eventId;
        } catch (JsonProcessingException e) {
            Log.e(TAG, "Failed to serialize event for ID calculation", e);
            return null;
        } catch (Exception e) {
            Log.e(TAG, "Failed to calculate event ID", e);
            return null;
        }
    }

    /**
     * Sign event ID with private key using Schnorr signature (BIP340)
     * Reference: nostr-java Identity.sign() and Schnorr.sign()
     * 
     * Process:
     * 1. Event ID is already a SHA256 hash (64 hex chars = 32 bytes)
     * 2. Convert event ID hex string to 32-byte array
     * 3. Generate random 32-byte aux parameter (BIP340 requirement)
     * 4. Sign the 32-byte event ID hash with private key and aux
     * 
     * Note: The event ID itself is already a hash, so we sign the hash bytes directly
     */
    private String signEventId(String eventId, String privkey) {
        try {
            if (secp256k1 == null) {
                Log.e(TAG, "Secp256k1 not initialized");
                return null;
            }
            
            // Convert event ID hex string to 32-byte array
            // Event ID is already a SHA256 hash (64 hex chars = 32 bytes)
            byte[] eventIdBytes = hexStringToByteArray(eventId);
            if (eventIdBytes.length != 32) {
                Log.e(TAG, "Event ID must be 32 bytes (64 hex chars), got: " + eventIdBytes.length);
                return null;
            }
            
            // Convert private key hex string to 32-byte array
            byte[] privkeyBytes = hexStringToByteArray(privkey);
            if (privkeyBytes.length != 32) {
                Log.e(TAG, "Private key must be 32 bytes (64 hex chars), got: " + privkeyBytes.length);
                return null;
            }
            
            // Generate random 32-byte aux parameter (BIP340 requirement)
            // Reference: nostr-java Identity.generateAuxRand() -> NostrUtil.createRandomByteArray(32)
            SecureRandom secureRandom = new SecureRandom();
            byte[] aux = new byte[32];
            secureRandom.nextBytes(aux);
            
            // Sign the 32-byte event ID hash using Schnorr with aux parameter
            // Reference: nostr-java Schnorr.sign(msg, secKey, auxRand)
            byte[] signature = secp256k1.signSchnorr(eventIdBytes, privkeyBytes, aux);
            
            if (signature == null) {
                Log.e(TAG, "Signature is null");
                return null;
            }
            
            // Signature should be 64 bytes (R || s)
            if (signature.length != 64) {
                Log.e(TAG, "Signature must be 64 bytes, got: " + signature.length);
                return null;
            }
            
            // Convert signature to hex string (lowercase)
            String sigHex = byteArrayToHexString(signature);
            Log.d(TAG, "Signed event ID, signature length: " + sigHex.length() + " chars (expected 128)");
            return sigHex;
        } catch (Exception e) {
            Log.e(TAG, "Failed to sign event ID", e);
            return null;
        }
    }

    /**
     * Convert hex string to byte array
     */
    private byte[] hexStringToByteArray(String hex) {
        int len = hex.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                    + Character.digit(hex.charAt(i + 1), 16));
        }
        return data;
    }

    /**
     * Convert byte array to hex string
     */
    private String byteArrayToHexString(byte[] bytes) {
        StringBuilder hexString = new StringBuilder();
        for (byte b : bytes) {
            String hex = Integer.toHexString(0xff & b);
            if (hex.length() == 1) {
                hexString.append('0');
            }
            hexString.append(hex);
        }
        return hexString.toString();
    }

    /**
     * Get private key from Android Keystore (decrypted from private file)
     */
    private String getPrivateKey() {
        String privkey = KeystoreHelper.getPrivateKey(this);
        if (privkey == null || privkey.isEmpty()) {
            Log.e(TAG, "Private key not found in Android Keystore file");
            Log.e(TAG, "This may happen if Service was restarted by system before Flutter app stored the private key");
            return null;
        }
        Log.d(TAG, "Private key retrieved successfully from Android Keystore");
        return privkey;
    }

    /**
     * Send AUTH response to relay
     */
    private void sendAuthResponse(String authJson) {
        if (webSocket != null && authJson != null && !authJson.isEmpty()) {
            Log.d(TAG, "Sending AUTH response: " + authJson);
            webSocket.send(authJson);
        }
    }

    /**
     * Schedule reconnection
     */
    private void scheduleReconnect() {
        // Don't schedule reconnect if already connecting or reconnecting
        if (isConnecting || isReconnecting) {
            Log.d(TAG, "Already connecting/reconnecting, skipping schedule reconnect");
            return;
        }
        
        if (reconnectRunnable != null) {
            reconnectHandler.removeCallbacks(reconnectRunnable);
        }
        
        isReconnecting = true;
        reconnectRunnable = new Runnable() {
            @Override
            public void run() {
                Log.d(TAG, "Attempting to reconnect...");
                isReconnecting = false; // Reset flag before connecting
                connectToRelay();
            }
        };
        
        reconnectHandler.postDelayed(reconnectRunnable, RECONNECT_DELAY_MS);
    }

    /**
     * Disconnect from relay
     */
    private void disconnectFromRelay() {
        if (webSocket != null) {
            try {
                webSocket.close(1000, "Service stopping");
            } catch (Exception e) {
                Log.e(TAG, "Error closing WebSocket", e);
            }
            webSocket = null;
        }
    }

    /**
     * Generate random hex string
     */
    private String generateRandomHex(int length) {
        Random random = new Random();
        StringBuilder sb = new StringBuilder();
        String chars = "0123456789abcdef";
        for (int i = 0; i < length; i++) {
            sb.append(chars.charAt(random.nextInt(chars.length())));
        }
        return sb.toString();
    }

    /**
     * Show notification when push notification is received
     * User can click notification to open the app
     */
    private void activateApp() {
        try {
            // Create a fresh Intent for MainActivity
            Intent intent = new Intent(this, MainActivity.class);
            intent.setAction(Intent.ACTION_MAIN);
            intent.addCategory(Intent.CATEGORY_LAUNCHER);
            intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            
            // Create PendingIntent for notification
            int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_ONE_SHOT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                PUSH_NOTIFICATION_ID,
                intent,
                flags
            );
            
            // Show notification that will launch the app when clicked
            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null) {
                NotificationCompat.Builder builder = new NotificationCompat.Builder(this, PUSH_NOTIFICATION_CHANNEL_ID)
                    .setContentTitle(getString(R.string.push_notification_title))
                    .setContentText(getString(R.string.push_notification_text))
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentIntent(pendingIntent)
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                    .setDefaults(Notification.DEFAULT_SOUND | Notification.DEFAULT_VIBRATE)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC);
                
                notificationManager.notify(PUSH_NOTIFICATION_ID, builder.build());
                Log.d(TAG, "Push notification shown");
            } else {
                Log.e(TAG, "NotificationManager is null");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to show notification", e);
        }
    }

    /**
     * Check whether app has Activity in foreground
     * Returns true only if there's an Activity visible to the user
     * Returns false if only Service is running (app was killed)
     */
    private boolean isAppProcessRunning() {
        ActivityManager activityManager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        if (activityManager == null) return false;
        List<ActivityManager.RunningAppProcessInfo> runningApps = activityManager.getRunningAppProcesses();
        if (runningApps == null) return false;
        String packageName = getPackageName();
        for (ActivityManager.RunningAppProcessInfo processInfo : runningApps) {
            if (processInfo.processName.equals(packageName)) {
                // Check if process has Activity in foreground
                // IMPORTANCE_FOREGROUND means there's an Activity visible to user
                // IMPORTANCE_SERVICE or other values mean only Service is running
                int importance = processInfo.importance;
                Log.d(TAG, "Process found, importance: " + importance + 
                    " (IMPORTANCE_FOREGROUND=" + ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND + ")");
                return importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND;
            }
        }
        Log.d(TAG, "Process not found in running apps");
        return false;
    }

    private void persistConfig() {
        if (serverRelay == null && deviceId == null && pubkey == null) return;
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        prefs.edit()
                .putString(KEY_SERVER_RELAY, serverRelay)
                .putString(KEY_DEVICE_ID, deviceId)
                .putString(KEY_PUBKEY, pubkey)
                .apply();
    }

    private void loadConfigFromPrefs() {
        SharedPreferences prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
        if (serverRelay == null || serverRelay.isEmpty()) {
            serverRelay = prefs.getString(KEY_SERVER_RELAY, null);
        }
        if (deviceId == null || deviceId.isEmpty()) {
            deviceId = prefs.getString(KEY_DEVICE_ID, null);
        }
        if (pubkey == null || pubkey.isEmpty()) {
            pubkey = prefs.getString(KEY_PUBKEY, null);
        }
        // Note: privatekey is loaded on-demand in getPrivateKey() method
        // We don't store it in instance variable for security reasons
    }
}
