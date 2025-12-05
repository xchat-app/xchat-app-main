package com.oxchat.lite;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import android.util.Log;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Helper class for storing/retrieving private key using Android Keystore
 * Private key is encrypted and stored in app's private file directory, not in SharedPreferences
 */
public class KeystoreHelper {
    private static final String TAG = "KeystoreHelper";
    private static final String KEYSTORE_PROVIDER = "AndroidKeyStore";
    private static final String KEY_ALIAS = "push_service_privkey_key";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int GCM_IV_LENGTH = 12;
    private static final int GCM_TAG_LENGTH = 128;
    private static final String PRIVKEY_FILE_NAME = "encrypted_privkey.dat";

    /**
     * Get or create the secret key for encryption
     */
    private static SecretKey getOrCreateSecretKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER);
        keyStore.load(null);

        SecretKey secretKey;
        if (keyStore.containsAlias(KEY_ALIAS)) {
            // Key already exists, retrieve it
            KeyStore.SecretKeyEntry secretKeyEntry = (KeyStore.SecretKeyEntry) keyStore.getEntry(KEY_ALIAS, null);
            secretKey = secretKeyEntry.getSecretKey();
        } else {
            // Create new key
            KeyGenerator keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER);
            KeyGenParameterSpec keyGenParameterSpec = new KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build();
            keyGenerator.init(keyGenParameterSpec);
            secretKey = keyGenerator.generateKey();
        }

        return secretKey;
    }

    /**
     * Get the file path for storing encrypted private key
     */
    private static File getPrivkeyFile(Context context) {
        return new File(context.getFilesDir(), PRIVKEY_FILE_NAME);
    }

    /**
     * Store private key encrypted in app's private file directory (encrypted with Android Keystore)
     * Not stored in SharedPreferences for better security
     */
    public static boolean storePrivateKey(Context context, String plaintext) {
        if (plaintext == null || plaintext.isEmpty()) {
            return false;
        }

        try {
            SecretKey secretKey = getOrCreateSecretKey();
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, secretKey);

            // Encrypt the data
            byte[] encryptedBytes = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            byte[] iv = cipher.getIV();

            // Combine IV and encrypted data
            byte[] combined = new byte[iv.length + encryptedBytes.length];
            System.arraycopy(iv, 0, combined, 0, iv.length);
            System.arraycopy(encryptedBytes, 0, combined, iv.length, encryptedBytes.length);

            // Encode to Base64 and save to file
            String encryptedData = Base64.encodeToString(combined, Base64.DEFAULT);
            File privkeyFile = getPrivkeyFile(context);
            Log.d(TAG, "Storing private key to file: " + privkeyFile.getAbsolutePath());
            try (FileOutputStream fos = new FileOutputStream(privkeyFile)) {
                fos.write(encryptedData.getBytes(StandardCharsets.UTF_8));
            }

            Log.d(TAG, "Private key encrypted and stored in private file, size: " + privkeyFile.length() + " bytes");
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to encrypt and store private key", e);
            // Delete file if encryption failed
            File privkeyFile = getPrivkeyFile(context);
            if (privkeyFile.exists()) {
                privkeyFile.delete();
            }
            return false;
        }
    }

    /**
     * Retrieve private key from app's private file directory (decrypted using Android Keystore)
     */
    public static String getPrivateKey(Context context) {
        File privkeyFile = getPrivkeyFile(context);
        Log.d(TAG, "Looking for private key file at: " + privkeyFile.getAbsolutePath());
        if (!privkeyFile.exists()) {
            Log.d(TAG, "Private key file not found at: " + privkeyFile.getAbsolutePath());
            return null;
        }
        Log.d(TAG, "Private key file found, size: " + privkeyFile.length() + " bytes");

        try {
            // Read encrypted data from file
            byte[] fileData;
            try (FileInputStream fis = new FileInputStream(privkeyFile)) {
                fileData = new byte[(int) privkeyFile.length()];
                fis.read(fileData);
            }
            String encryptedData = new String(fileData, StandardCharsets.UTF_8);

            // Decode from Base64
            byte[] combined = Base64.decode(encryptedData, Base64.DEFAULT);

            // Extract IV and encrypted data
            byte[] iv = new byte[GCM_IV_LENGTH];
            byte[] encryptedBytes = new byte[combined.length - GCM_IV_LENGTH];
            System.arraycopy(combined, 0, iv, 0, GCM_IV_LENGTH);
            System.arraycopy(combined, GCM_IV_LENGTH, encryptedBytes, 0, encryptedBytes.length);

            // Decrypt
            SecretKey secretKey = getOrCreateSecretKey();
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            GCMParameterSpec gcmParameterSpec = new GCMParameterSpec(GCM_TAG_LENGTH, iv);
            cipher.init(Cipher.DECRYPT_MODE, secretKey, gcmParameterSpec);
            byte[] decryptedBytes = cipher.doFinal(encryptedBytes);

            return new String(decryptedBytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            Log.e(TAG, "Failed to decrypt private key", e);
            return null;
        }
    }

    /**
     * Clear private key from file system
     */
    public static void clearPrivateKey(Context context) {
        File privkeyFile = getPrivkeyFile(context);
        if (privkeyFile.exists()) {
            // Overwrite file with zeros before deleting
            try (FileOutputStream fos = new FileOutputStream(privkeyFile)) {
                byte[] zeros = new byte[(int) privkeyFile.length()];
                java.util.Arrays.fill(zeros, (byte) 0);
                fos.write(zeros);
            } catch (IOException e) {
                Log.e(TAG, "Failed to overwrite file", e);
            }
            privkeyFile.delete();
            Log.d(TAG, "Private key file deleted");
        }
    }

    /**
     * Delete the encryption key from Android Keystore and clear private key file (for cleanup)
     */
    public static boolean deleteKey(Context context) {
        try {
            KeyStore keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER);
            keyStore.load(null);
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS);
            }
            clearPrivateKey(context);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Failed to delete key", e);
        }
        return false;
    }
}

