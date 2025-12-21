package com.juansofly.ferrous

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import org.json.JSONObject

/**
 * Handles Storage Access Framework operations for Android 10+ file access.
 * 
 * This handler:
 * 1. Opens the SAF folder picker (ACTION_OPEN_DOCUMENT_TREE)
 * 2. Persists URI permissions for future access
 * 3. Links or imports supported ebook files
 * 4. Returns book refs (URIs for linked, paths for imported)
 */
class SafHandler(private val activity: MainActivity) {
    
    companion object {
        const val CHANNEL = "com.juansofly.ferrous/saf"
        const val REQUEST_CODE_OPEN_FOLDER = 1001
        
        private val SUPPORTED_EXTENSIONS = listOf("pdf", "epub", "cbz", "docx")
        private const val PREFS_NAME = "saf_prefs"
        private const val PREFS_KEY_URIS = "persisted_uris"
        private const val PREFS_KEY_URI_MODES = "persisted_uri_modes"
        private const val BOOKS_DIR = "books"
        private const val MODE_LINKED = "linked"
        private const val MODE_IMPORTED = "imported"
    }
    
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPickMode: String = MODE_LINKED
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    
    /**
     * Handle method calls from Flutter via platform channel.
     */
    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> {
                val mode = call.argument<String>("mode")
                pendingPickMode = if (mode == MODE_IMPORTED) MODE_IMPORTED else MODE_LINKED
                pendingResult = result
                openFolderPicker()
            }
            "rescanFolders" -> {
                scope.launch {
                    try {
                        val books = rescanPersistedFolders()
                        result.success(books)
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
            "copyUriToCache" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("INVALID_ARGS", "URI required", null)
                    return
                }
                val suggestedName = call.argument<String>("suggestedName")
                scope.launch {
                    try {
                        val path = copyUriToCache(Uri.parse(uriString), suggestedName)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("COPY_URI_ERROR", e.message, null)
                    }
                }
            }
            "validateUriPermission" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("INVALID_ARGS", "URI required", null)
                    return
                }
                val hasPermission = hasValidPermission(Uri.parse(uriString))
                result.success(hasPermission)
            }
            "cleanupStalePermissions" -> {
                scope.launch {
                    try {
                        val removedCount = cleanupStalePermissions()
                        result.success(removedCount)
                    } catch (e: Exception) {
                        result.error("CLEANUP_ERROR", e.message, null)
                    }
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
            result?.success(emptyList<Map<String, Any?>>())
            return
        }
        
        val treeUri = data.data!!
        
        // Persist the permission so we can access this folder in the future
        try {
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or 
                           Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            activity.contentResolver.takePersistableUriPermission(treeUri, takeFlags)
            savePersistedUri(treeUri, pendingPickMode)
        } catch (e: Exception) {
            result?.error("PERMISSION_ERROR", "Failed to persist permission: ${e.message}", null)
            return
        }
        
        val mode = pendingPickMode

        // Scan or copy files in background
        scope.launch {
            try {
                val books = when (mode) {
                    MODE_IMPORTED -> copyFilesFromUri(treeUri)
                    else -> scanFilesFromUri(treeUri)
                }
                result?.success(books)
            } catch (e: Exception) {
                result?.error("SCAN_ERROR", "Failed to scan files: ${e.message}", null)
            }
        }
    }
    
    /**
     * Checks if we have a valid persisted permission for the given URI.
     */
    private fun hasValidPermission(uri: Uri): Boolean {
        // Check if URI or any parent tree URI has valid persisted permission
        val permissions = activity.contentResolver.persistedUriPermissions
        
        // Direct match
        if (permissions.any { it.uri == uri && it.isReadPermission }) {
            return true
        }
        
        // Check if this is a document URI under a persisted tree
        val uriString = uri.toString()
        for (perm in permissions) {
            if (perm.isReadPermission) {
                val treeUriString = perm.uri.toString()
                // SAF tree URIs use /tree/ and document URIs under them use /tree/.../document/
                if (uriString.startsWith(treeUriString.replace("/tree/", "/tree/")) ||
                    uriString.contains(perm.uri.lastPathSegment ?: "")) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /**
     * Removes stale URIs from preferences that no longer have valid permissions.
     * Returns the number of removed entries.
     */
    private suspend fun cleanupStalePermissions(): Int = withContext(Dispatchers.IO) {
        var removedCount = 0
        val prefs = getPrefs()
        val existingUris = prefs.getStringSet(PREFS_KEY_URIS, emptySet()) ?: emptySet()
        val validPermissions = activity.contentResolver.persistedUriPermissions
            .filter { it.isReadPermission }
            .map { it.uri.toString() }
            .toSet()
        
        val staleUris = existingUris.filter { uriStr -> 
            !validPermissions.contains(uriStr)
        }
        
        if (staleUris.isNotEmpty()) {
            val updated = existingUris.toMutableSet()
            staleUris.forEach { 
                updated.remove(it)
                removedCount++
            }
            prefs.edit().putStringSet(PREFS_KEY_URIS, updated).apply()
            
            // Also clean up modes
            val modes = JSONObject(prefs.getString(PREFS_KEY_URI_MODES, "{}"))
            staleUris.forEach { modes.remove(it) }
            prefs.edit().putString(PREFS_KEY_URI_MODES, modes.toString()).apply()
        }
        
        removedCount
    }
    
    /**
     * Copies all supported ebook files from a SAF tree URI to internal storage.
     * Returns list of imported book refs.
     */
    private suspend fun copyFilesFromUri(treeUri: Uri): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val copiedBooks = mutableListOf<Map<String, Any?>>()
        val booksDir = getBooksDirectory()
        
        val documentFile = DocumentFile.fromTreeUri(activity, treeUri)
        if (documentFile == null || !documentFile.exists()) {
            return@withContext copiedBooks
        }
        
        // Recursively scan for ebooks
        scanAndCopyFiles(documentFile, booksDir, copiedBooks)
        
        copiedBooks
    }

    /**
     * Recursively scans a DocumentFile directory and copies supported files.
     */
    private fun scanAndCopyFiles(
        documentFile: DocumentFile,
        destDir: File,
        copiedBooks: MutableList<Map<String, Any?>>
    ) {
        for (file in documentFile.listFiles()) {
            if (file.isDirectory) {
                // Recurse into subdirectories
                scanAndCopyFiles(file, destDir, copiedBooks)
            } else if (file.isFile) {
                val name = file.name ?: continue
                val extension = name.substringAfterLast('.', "").lowercase()
                
                if (extension in SUPPORTED_EXTENSIONS) {
                    try {
                        val destFile = File(destDir, name)
                        
                        // Skip if already copied (same name and size)
                        if (destFile.exists() && destFile.length() == file.length()) {
                            copiedBooks.add(
                                mapOf(
                                    "sourceType" to MODE_IMPORTED,
                                    "filePath" to destFile.absolutePath,
                                    "displayName" to name,
                                    "size" to destFile.length(),
                                    "lastModified" to destFile.lastModified(),
                                    "format" to extension,
                                )
                            )
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
                        
                        copiedBooks.add(
                            mapOf(
                                "sourceType" to MODE_IMPORTED,
                                "filePath" to finalDest.absolutePath,
                                "displayName" to name,
                                "size" to finalDest.length(),
                                "lastModified" to finalDest.lastModified(),
                                "format" to extension,
                            )
                        )
                    } catch (e: Exception) {
                        // Log and continue with other files
                        e.printStackTrace()
                    }
                }
            }
        }
    }

    /**
     * Scans a SAF tree URI and returns linked book refs without copying.
     */
    private suspend fun scanFilesFromUri(treeUri: Uri): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val linkedBooks = mutableListOf<Map<String, Any?>>()
        val documentFile = DocumentFile.fromTreeUri(activity, treeUri)
        if (documentFile == null || !documentFile.exists()) {
            return@withContext linkedBooks
        }
        scanAndCollectLinkedFiles(documentFile, linkedBooks)
        linkedBooks
    }

    /**
     * Recursively scans a DocumentFile directory and collects supported files as URIs.
     */
    private fun scanAndCollectLinkedFiles(
        documentFile: DocumentFile,
        linkedBooks: MutableList<Map<String, Any?>>
    ) {
        for (file in documentFile.listFiles()) {
            if (file.isDirectory) {
                scanAndCollectLinkedFiles(file, linkedBooks)
            } else if (file.isFile) {
                val name = file.name ?: continue
                val extension = name.substringAfterLast('.', "").lowercase()
                if (extension in SUPPORTED_EXTENSIONS) {
                    linkedBooks.add(
                        mapOf(
                            "sourceType" to MODE_LINKED,
                            "uri" to file.uri.toString(),
                            "displayName" to name,
                            "size" to file.length(),
                            "lastModified" to file.lastModified(),
                            "format" to extension,
                        )
                    )
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
     * Automatically cleans up stale permissions.
     */
    private suspend fun rescanPersistedFolders(): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        // First, clean up any stale permissions
        cleanupStalePermissions()
        
        val allBooks = mutableListOf<Map<String, Any?>>()
        val persistedUris = getPersistedFolderUris()
        val uriModes = getPersistedUriModes()
        
        for (uri in persistedUris) {
            try {
                // Check if we still have permission
                val hasPermission = activity.contentResolver.persistedUriPermissions
                    .any { it.uri == uri && it.isReadPermission }
                
                if (hasPermission) {
                    val mode = uriModes[uri.toString()] ?: MODE_IMPORTED
                    val books = when (mode) {
                        MODE_IMPORTED -> copyFilesFromUri(uri)
                        else -> scanFilesFromUri(uri)
                    }
                    allBooks.addAll(books)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        
        allBooks
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
    
    private fun savePersistedUri(uri: Uri, mode: String) {
        val prefs = getPrefs()
        val existing = prefs.getStringSet(PREFS_KEY_URIS, mutableSetOf()) ?: mutableSetOf()
        val updated = existing.toMutableSet()
        updated.add(uri.toString())
        prefs.edit().putStringSet(PREFS_KEY_URIS, updated).apply()
        saveUriMode(uri, mode)
    }
    
    private fun removePersistedUri(uri: Uri) {
        val prefs = getPrefs()
        val existing = prefs.getStringSet(PREFS_KEY_URIS, mutableSetOf()) ?: mutableSetOf()
        val updated = existing.toMutableSet()
        updated.remove(uri.toString())
        prefs.edit().putStringSet(PREFS_KEY_URIS, updated).apply()
        removeUriMode(uri)
        
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

    private fun saveUriMode(uri: Uri, mode: String) {
        val prefs = getPrefs()
        val modes = JSONObject(prefs.getString(PREFS_KEY_URI_MODES, "{}"))
        modes.put(uri.toString(), mode)
        prefs.edit().putString(PREFS_KEY_URI_MODES, modes.toString()).apply()
    }

    private fun removeUriMode(uri: Uri) {
        val prefs = getPrefs()
        val modes = JSONObject(prefs.getString(PREFS_KEY_URI_MODES, "{}"))
        modes.remove(uri.toString())
        prefs.edit().putString(PREFS_KEY_URI_MODES, modes.toString()).apply()
    }

    private fun getPersistedUriModes(): Map<String, String> {
        val prefs = getPrefs()
        val raw = prefs.getString(PREFS_KEY_URI_MODES, "{}") ?: "{}"
        val obj = JSONObject(raw)
        val map = mutableMapOf<String, String>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = obj.optString(key, MODE_IMPORTED)
        }
        return map
    }

    /**
     * Copies a single SAF URI into cache and returns the temp file path.
     * Validates permission before attempting to copy.
     */
    private suspend fun copyUriToCache(uri: Uri, suggestedName: String?): String =
        withContext(Dispatchers.IO) {
            // Validate permission first
            if (!hasValidPermission(uri)) {
                throw SecurityException(
                    "Permission denied for URI. The file may have been moved or the app was reinstalled. " +
                    "Please re-add the folder containing this book."
                )
            }
            
            val safeName = sanitizeFileName(suggestedName ?: "linked")
            val extension = safeName.substringAfterLast('.', "")
            val suffix = if (extension.isNotEmpty()) ".$extension" else ""
            val tempFile = File.createTempFile("linked_", suffix, activity.cacheDir)
            
            try {
                val input = activity.contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Unable to open URI stream. The file may no longer exist.")
                input.use { stream ->
                    FileOutputStream(tempFile).use { output ->
                        stream.copyTo(output)
                    }
                }
            } catch (e: SecurityException) {
                tempFile.delete()
                throw SecurityException(
                    "Permission denied for URI. Please re-add the folder containing this book."
                )
            }
            
            tempFile.absolutePath
        }

    private fun sanitizeFileName(name: String): String {
        return name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
    }
    
    /**
     * Clean up coroutine scope when no longer needed.
     */
    fun dispose() {
        scope.cancel()
    }
}
