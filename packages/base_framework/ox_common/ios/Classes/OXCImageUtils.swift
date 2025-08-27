//
//  OXCImageUtils.swift
//  ox_common
//
//  Created by w on 2025/1/27.
//

import UIKit

/// Unified image utility class for ox_common
class OXCImageUtils {
    
    /// Detect image format from binary data using magic bytes
    /// - Parameter data: Image binary data
    /// - Returns: Detected image format string, or nil if format is not supported
    static func detectImageFormat(from data: Data) -> String? {
        guard data.count >= 8 else { return nil }
        
        let bytes = [UInt8](data)
        
        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 &&
           bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A {
            return "png"
        }
        
        // JPEG: FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "jpeg"
        }
        
        // WebP: 52 49 46 46 ... 57 45 42 50
        if data.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "webp"
        }
        
        // BMP: 42 4D
        if bytes[0] == 0x42 && bytes[1] == 0x4D {
            return "bmp"
        }
        
        // GIF: 47 49 46 38 (GIF8)
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
            return "gif"
        }
        
        // TIFF: 49 49 2A 00 (little-endian) or 4D 4D 00 2A (big-endian)
        if (bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
           (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A) {
            return "tiff"
        }
        
        return nil // Unsupported format
    }
    
    /// Get file extension for detected image format
    /// - Parameter format: Image format string
    /// - Returns: File extension with dot prefix
    static func getFileExtension(for format: String) -> String {
        switch format.lowercased() {
        case "jpeg", "jpg":
            return ".jpg"
        case "png":
            return ".png"
        case "webp":
            return ".webp"
        case "bmp":
            return ".bmp"
        case "gif":
            return ".gif"
        case "tiff", "tif":
            return ".tiff"
        default:
            return ".png" // Default fallback
        }
    }
    
    /// Check if the detected format is supported for clipboard operations
    /// - Parameter format: Image format string
    /// - Returns: True if format is supported
    static func isFormatSupportedForClipboard(_ format: String) -> Bool {
        let supportedFormats = ["png", "jpeg", "jpg", "webp", "bmp", "gif", "tiff", "tif"]
        return supportedFormats.contains(format.lowercased())
    }
}
