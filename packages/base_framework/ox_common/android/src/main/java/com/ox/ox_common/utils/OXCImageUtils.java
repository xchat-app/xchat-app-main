package com.ox.ox_common.utils;

import android.graphics.Bitmap;

public class OXCImageUtils {
    
    public static String detectImageFormat(byte[] data) {
        if (data.length < 8) {
            return null;
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if (data[0] == (byte) 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 &&
            data[4] == 0x0D && data[5] == 0x0A && data[6] == 0x1A && data[7] == 0x0A) {
            return "png";
        }

        // JPEG: FF D8 FF
        if (data[0] == (byte) 0xFF && data[1] == (byte) 0xD8 && data[2] == (byte) 0xFF) {
            return "jpeg";
        }

        // WebP: 52 49 46 46 ... 57 45 42 50
        if (data.length >= 12 && data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
            data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) {
            return "webp";
        }

        // BMP: 42 4D
        if (data[0] == 0x42 && data[1] == 0x4D) {
            return "bmp";
        }

        // GIF: 47 49 46 38 (GIF8)
        if (data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x38) {
            return "gif";
        }

        // TIFF: 49 49 2A 00 (little-endian) or 4D 4D 00 2A (big-endian)
        if ((data[0] == 0x49 && data[1] == 0x49 && data[2] == 0x2A && data[3] == 0x00) ||
            (data[0] == 0x4D && data[1] == 0x4D && data[2] == 0x00 && data[3] == 0x2A)) {
            return "tiff";
        }

        return null; // Unsupported format
    }
    
    public static String getFileExtension(String format) {
        if (format == null) return ".png";
        
        switch (format.toLowerCase()) {
            case "jpeg":
            case "jpg":
                return ".jpg";
            case "png":
                return ".png";
            case "webp":
                return ".webp";
            case "bmp":
                return ".bmp";
            case "gif":
                return ".gif";
            case "tiff":
            case "tif":
                return ".tiff";
            default:
                return ".png"; // Default fallback
        }
    }

    public static Bitmap.CompressFormat getCompressFormat(String format) {
        if (format == null) return null;
        
        switch (format.toLowerCase()) {
            case "jpeg":
            case "jpg":
                return Bitmap.CompressFormat.JPEG;
            case "webp":
                return Bitmap.CompressFormat.WEBP;
            case "png":
                return Bitmap.CompressFormat.PNG;
            case "bmp":
            case "gif":
            case "tiff":
            case "tif":
                // These formats are not directly supported by Bitmap.compress
                // We'll fallback to PNG
                return null;
            default:
                return null;
        }
    }
}
