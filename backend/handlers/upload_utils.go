package handlers

import (
	"bytes"
	"io"
	"mime/multipart"
	"net/http"
	"path/filepath"
	"strings"
)

// SniffAndResolveContentType reads the initial bytes of a multipart file to determine its MIME type,
// rewinds the stream to the beginning, and returns the resolved content type and the proper extension.
func SniffAndResolveContentType(file *multipart.FileHeader, src multipart.File) (string, string, error) {
	headerBytes := make([]byte, 512)
	n, _ := io.ReadFull(src, headerBytes)
	if n > 0 {
		headerBytes = headerBytes[:n]
	} else {
		headerBytes = []byte{}
	}

	// Rewind the reader so subsequent uploads get the entire file
	if seeker, ok := src.(io.Seeker); ok {
		if _, err := seeker.Seek(0, io.SeekStart); err != nil {
			return "", "", err
		}
	}

	contentType := strings.TrimSpace(file.Header.Get("Content-Type"))
	// If the client sent octet-stream or empty, detect it from file content
	if contentType == "" || contentType == "application/octet-stream" {
		contentType = DetectImageContentType(headerBytes, file.Filename)
	}

	extension := GetExtensionForContentType(contentType, file.Filename)
	return contentType, extension, nil
}

// DetectImageContentType inspects magic bytes and filename extension to determine the image MIME type.
func DetectImageContentType(data []byte, filename string) string {
	// Magic bytes checks
	if len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
		return "image/jpeg"
	}
	if len(data) >= 8 && bytes.Equal(data[:8], []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}) {
		return "image/png"
	}
	if len(data) >= 12 && string(data[0:4]) == "RIFF" && string(data[8:12]) == "WEBP" {
		return "image/webp"
	}
	if len(data) >= 4 && string(data[0:4]) == "%PDF" {
		return "application/pdf"
	}

	// Fallback to http.DetectContentType
	if len(data) > 0 {
		sniffed := http.DetectContentType(data)
		if sniffed != "application/octet-stream" && strings.HasPrefix(sniffed, "image/") {
			return sniffed
		}
	}

	// Fallback to filename extension
	ext := strings.ToLower(filepath.Ext(filename))
	switch ext {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".webp":
		return "image/webp"
	case ".pdf":
		return "application/pdf"
	}

	// Default for camera selfies/photos
	return "image/jpeg"
}

// GetExtensionForContentType returns the canonical file extension for a given MIME type.
func GetExtensionForContentType(contentType, currentFilename string) string {
	ext := strings.ToLower(filepath.Ext(currentFilename))
	switch contentType {
	case "image/jpeg":
		if ext == ".jpeg" || ext == ".jpg" {
			return ext
		}
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "application/pdf":
		return ".pdf"
	default:
		if ext != "" {
			return ext
		}
		return ".jpg"
	}
}
