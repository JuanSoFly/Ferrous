package com.antigravity.reader.reader_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream

/**
 * Handles Storage Access Framework operations for Android 10+ file access.
 * 
 * This handler:
 * 1. Opens the SAF folder picker (ACTION_OPEN_DOCUMENT_TREE)
 * 2. Persists URI permissions for future access
 * 3. Copies supported ebook files to internal app storage
 * 4. Returns paths to copied files that Rust can access
 */
class SafHandler(private val activity: MainActivity) {
    
    companion object {
        const val CHANNEL = "com.antigravity.reader/saf"
        const val REQUEST_CODE_OPEN_FOLDER = 1001
        
        private val SUPPORTED_EXTENSIONS = listOf("pdf", "epub", "cbz", "docx")
        private const val PREFS_NAME = "saf_prefs"
        private const val PREFS_KEY_URIS = "persisted_uris"
        private const val BOOKS_DIR = "books"
    }
    
    private var pendingResult: MethodChannel.Result? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    /**
     * Handle method calls from Flutter via platform channel.
     */
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> {
                pendingResult = result
                openFolderPicker()
            }
            "rescanFolders" -> {
                scope.launch {
                    try {
                        val paths = rescanPersistedFolders()
                        result.success(paths)
                    } catch (e: Exception) {
                        result.error("RESCAN_ERROR", e.message, null)
                    }
                }
            }
            "getPersistedFolders" -> {
                val folders = getPersistedFolderUris().map { it.toString() }
                result.success(folders)
            }
            "removePersistedFolder" -> {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    removePersistedUri(Uri.parse(uriString))
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "URI required", null)
                }
            }
            else -> result.notImplemented()
        }
    }
    
    /**
     * Opens the system folder picker using ACTION_OPEN_DOCUMENT_TREE.
     */
    private fun openFolderPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
            )
        }
        activity.startActivityForResult(intent, REQUEST_CODE_OPEN_FOLDER)
    }
    
    /**
     * Called from MainActivity.onActivityResult() to process the folder selection.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE_OPEN_FOLDER) return
        
        val result = pendingResult
        pendingResult = null
        
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(emptyList<String>())
            return
        }
        
        val treeUri = data.data!!
        
        // Persist the permission so we can access this folder in the future
        try {
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                           Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.takePersistableUriPermission(treeUri, takeFlags)
            savePersistedUri(treeUri)
        } catch (e: Exception) {
            result?.error("PERMISSION_ERROR", "Failed to persist permission: ${e.message}", null)
            return
        }
        
        // Copy files in background
        scope.launch {
            try {
                val copiedPaths = copyFilesFromUri(treeUri)
                result?.success(copiedPaths)
            } catch (e: Exception) {
                result?.error("COPY_ERROR", "Failed to copy files: ${e.message}", null)
            }
        }
    }
    
    /**
     * Copies all supported ebook files from a SAF tree URI to internal storage.
     * Returns list of internal file paths.
     */
    private suspend fun copyFilesFromUri(treeUri: Uri): List<String> = withContext(Dispatchers.IO) {
        val copiedPaths = mutableListOf<String>()
        val booksDir = getBooksDirectory()
        
        val documentFile = DocumentFile.fromTreeUri(activity, treeUri)
        if (documentFile == null || !documentFile.exists()) {
            return@withContext copiedPaths
        }
        
        // Recursively scan for ebooks
        scanAndCopyFiles(documentFile, booksDir, copiedPaths)
        
        copiedPaths
    }
    
    /**
     * Recursively scans a DocumentFile directory and copies supported files.
     */
    private fun scanAndCopyFiles(
        documentFile: DocumentFile,
        destDir: File,
        copiedPaths: MutableList<String>
    ) {
        for (file in documentFile.listFiles()) {
            if (file.isDirectory) {
                // Recurse into subdirectories
                scanAndCopyFiles(file, destDir, copiedPaths)
            } else if (file.isFile) {
                val name = file.name ?: continue
                val extension = name.substringAfterLast('.', "").lowercase()
                
                if (extension in SUPPORTED_EXTENSIONS) {
                    try {
                        val destFile = File(destDir, name)
                        
                        // Skip if already copied (same name and size)
                        if (destFile.exists() && destFile.length() == file.length()) {
                            copiedPaths.add(destFile.absolutePath)
                            continue
                        }
                        
                        // Handle duplicate filenames
                        val finalDest = getUniqueFile(destDir, name)
                        
                        // Copy file
                        activity.contentResolver.openInputStream(file.uri)?.use { input ->
                            FileOutputStream(finalDest).use { output ->
                                input.copyTo(output)
                            }
                        }
                        
                        copiedPaths.add(finalDest.absolutePath)
                    } catch (e: Exception) {
                        // Log and continue with other files
                        e.printStackTrace()
                    }
                }
            }
        }
    }
    
    /**
     * Returns a unique filename if the file already exists.
     */
    private fun getUniqueFile(dir: File, name: String): File {
        var file = File(dir, name)
        if (!file.exists()) return file
        
        val baseName = name.substringBeforeLast('.')
        val extension = name.substringAfterLast('.', "")
        var counter = 1
        
        while (file.exists()) {
            val newName = if (extension.isNotEmpty()) {
                "${baseName}_$counter.$extension"
            } else {
                "${baseName}_$counter"
            }
            file = File(dir, newName)
            counter++
        }
        
        return file
    }
    
    /**
     * Rescans all previously persisted folder URIs for new books.
     */
    private suspend fun rescanPersistedFolders(): List<String> = withContext(Dispatchers.IO) {
        val allPaths = mutableListOf<String>()
        val persistedUris = getPersistedFolderUris()
        
        for (uri in persistedUris) {
            try {
                // Check if we still have permission
                val hasPermission = activity.contentResolver.persistedUriPermissions
                    .any { it.uri == uri && it.isReadPermission }
                
                if (hasPermission) {
                    val paths = copyFilesFromUri(uri)
                    allPaths.addAll(paths)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        
        allPaths
    }
    
    /**
     * Gets the internal books directory, creating it if needed.
     */
    private fun getBooksDirectory(): File {
        val dir = File(activity.filesDir, BOOKS_DIR)
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }
    
    // --- SharedPreferences helpers for persisted URIs ---
    
    private fun getPrefs() = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    
    private fun savePersistedUri(uri: Uri) {
        val prefs = getPrefs()
        val existing = prefs.getStringSet(PREFS_KEY_URIS, mutableSetOf()) ?: mutableSetOf()
        val updated = existing.toMutableSet()
        updated.add(uri.toString())
        prefs.edit().putStringSet(PREFS_KEY_URIS, updated).apply()
    }
    
    private fun removePersistedUri(uri: Uri) {
        val prefs = getPrefs()
        val existing = prefs.getStringSet(PREFS_KEY_URIS, mutableSetOf()) ?: mutableSetOf()
        val updated = existing.toMutableSet()
        updated.remove(uri.toString())
        prefs.edit().putStringSet(PREFS_KEY_URIS, updated).apply()
        
        // Also release the system permission
        try {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                       Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.releasePersistableUriPermission(uri, flags)
        } catch (e: Exception) {
            // Ignore if already released
        }
    }
    
    private fun getPersistedFolderUris(): List<Uri> {
        val prefs = getPrefs()
        val uriStrings = prefs.getStringSet(PREFS_KEY_URIS, emptySet()) ?: emptySet()
        return uriStrings.mapNotNull { 
            try { Uri.parse(it) } catch (e: Exception) { null }
        }
    }
    
    /**
     * Clean up coroutine scope when no longer needed.
     */
    fun dispose() {
        scope.cancel()
    }
}
