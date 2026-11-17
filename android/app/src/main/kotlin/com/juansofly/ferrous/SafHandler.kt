package com.juansofly.ferrous

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.provider.OpenableColumns
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
        const val REQUEST_CODE_OPEN_FILE = 1002
        
        private val SUPPORTED_EXTENSIONS = listOf("pdf", "epub", "cbz", "cbr", "docx", "txt", "mobi", "azw", "azw3")
        private const val PREFS_NAME = "saf_prefs"
        private const val PREFS_KEY_URIS = "persisted_uris"
        private const val PREFS_KEY_URI_MODES = "persisted_uri_modes"
        private const val BOOKS_DIR = "books"
        private const val SAF_CACHE_DIR = "saf_cache"
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
            "pickFiles" -> {
                val mode = call.argument<String>("mode")
                pendingPickMode = if (mode == MODE_IMPORTED) MODE_IMPORTED else MODE_LINKED
                pendingResult = result
                openFilePicker()
            }
            "releasePersistedUri" -> {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    releasePersistableUriPermission(uriString)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "URI required", null)
                }
            }
            "deleteExternalDocument" -> {
                val uriString = call.argument<String>("uri")
                if (uriString != null) {
                    scope.launch(Dispatchers.IO) {
                        try {
                            val uri = Uri.parse(uriString)
                            val deleted = DocumentsContract.deleteDocument(activity.contentResolver, uri)
                            withContext(Dispatchers.Main) {
                                result.success(deleted)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("DELETE_DOC_ERROR", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGS", "URI required", null)
                }
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
            "getPersistedFolderDetails" -> {
                scope.launch {
                    try {
                        val persistedUris = getPersistedFolderUris()
                        val uriModes = getPersistedUriModes()
                        val details = persistedUris.map { uri ->
                            val uriStr = uri.toString()
                            val mode = uriModes[uriStr] ?: MODE_IMPORTED
                            var displayName: String? = null
                            try {
                                val doc = DocumentFile.fromTreeUri(activity, uri)
                                displayName = doc?.name
                            } catch (_: Exception) {}
                            mapOf(
                                "uri" to uriStr,
                                "mode" to mode,
                                "displayName" to (displayName ?: ""),
                                "isValid" to hasValidPermission(uri)
                            )
                        }
                        result.success(details)
                    } catch (e: Exception) {
                        result.error("DETAILS_ERROR", e.message, null)
                    }
                }
            }
            "rescanFolder" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("INVALID_ARGS", "URI required", null)
                    return
                }
                val uri = Uri.parse(uriString)
                val uriModes = getPersistedUriModes()
                val mode = call.argument<String>("mode") ?: uriModes[uriString] ?: MODE_LINKED
                scope.launch {
                    try {
                        val hasPermission = hasValidPermission(uri)
                        if (!hasPermission) {
                            result.error("PERMISSION_REVOKED", "Permission revoked or folder no longer accessible", null)
                            return@launch
                        }
                        val books = when (mode) {
                            MODE_IMPORTED -> copyFilesFromUri(uri)
                            else -> scanFilesFromUri(uri)
                        }
                        result.success(books)
                    } catch (e: Exception) {
                        result.error("RESCAN_ERROR", e.message, null)
                    }
                }
            }
            "updateFolderMode" -> {
                val uriString = call.argument<String>("uri")
                val mode = call.argument<String>("mode")
                if (uriString != null && mode != null) {
                    saveUriMode(Uri.parse(uriString), mode)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "URI and mode required", null)
                }
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
                val force = call.argument<Boolean>("force") ?: false
                scope.launch {
                    try {
                        val path = copyUriToCache(Uri.parse(uriString), suggestedName, force)
                        result.success(path)
                    } catch (e: Exception) {
                        result.error("COPY_URI_ERROR", e.message, null)
                    }
                }
            }
            "getNativeLibraryDir" -> {
                result.success(activity.applicationInfo.nativeLibraryDir)
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
            "cleanupCache" -> {
                scope.launch {
                    try {
                        cleanupSafCache()
                        result.success(true)
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
     * Opens the system document picker using ACTION_OPEN_DOCUMENT.
     */
    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/pdf",
                    "application/epub+zip",
                    "text/plain",
                    "application/x-mobipocket-ebook",
                    "application/vnd.amazon.ebook",
                    "application/octet-stream"
                )
            )
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        activity.startActivityForResult(intent, REQUEST_CODE_OPEN_FILE)
    }
    
    /**
     * Called from MainActivity.onActivityResult() to process folder or file selection.
     */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_CODE_OPEN_FOLDER && requestCode != REQUEST_CODE_OPEN_FILE) return
        
        val result = pendingResult
        pendingResult = null
        
        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.success(emptyList<Map<String, Any?>>())
            return
        }

        if (requestCode == REQUEST_CODE_OPEN_FOLDER) {
            val treeUri = data.data
            if (treeUri == null) {
                result?.success(emptyList<Map<String, Any?>>())
                return
            }
            
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
        } else if (requestCode == REQUEST_CODE_OPEN_FILE) {
            val uris = mutableListOf<Uri>()
            val clipData = data.clipData
            if (clipData != null) {
                for (i in 0 until clipData.itemCount) {
                    clipData.getItemAt(i)?.uri?.let { uris.add(it) }
                }
            } else if (data.data != null) {
                uris.add(data.data!)
            }

            if (uris.isEmpty()) {
                result?.success(emptyList<Map<String, Any?>>())
                return
            }

            val mode = pendingPickMode
            scope.launch {
                try {
                    val books = processPickedFileUris(uris, mode)
                    result?.success(books)
                } catch (e: Exception) {
                    result?.error("PICK_FILES_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * Processes individually picked file URIs with quota tracking and fallback.
     */
    private suspend fun processPickedFileUris(
        uris: List<Uri>,
        requestedMode: String
    ): List<Map<String, Any?>> = withContext(Dispatchers.IO) {
        val resultBooks = mutableListOf<Map<String, Any?>>()
        val maxPersistedUris = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) 500 else 120
        var currentCount = activity.contentResolver.persistedUriPermissions.size

        for (uri in uris) {
            try {
                val meta = getUriMetadata(uri)
                val displayName = meta.first ?: "document"
                val extension = displayName.substringAfterLast('.', "").lowercase()

                if (extension !in SUPPORTED_EXTENSIONS) {
                    continue
                }

                var effectiveMode = requestedMode
                if (effectiveMode == MODE_LINKED && currentCount >= maxPersistedUris) {
                    effectiveMode = MODE_IMPORTED
                }

                if (effectiveMode == MODE_LINKED) {
                    try {
                        val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        activity.contentResolver.takePersistableUriPermission(uri, takeFlags)
                        savePersistedUri(uri, MODE_LINKED)
                        currentCount++

                        resultBooks.add(
                            mapOf(
                                "sourceType" to MODE_LINKED,
                                "uri" to uri.toString(),
                                "displayName" to displayName,
                                "size" to meta.second,
                                "lastModified" to meta.third,
                                "format" to extension,
                            )
                        )
                    } catch (e: SecurityException) {
                        // Fallback to MODE_IMPORTED if quota or permission fails
                        val importedRef = copySingleDocumentToBooks(uri, displayName, extension)
                        if (importedRef != null) {
                            resultBooks.add(importedRef)
                        }
                    }
                } else {
                    val importedRef = copySingleDocumentToBooks(uri, displayName, extension)
                    if (importedRef != null) {
                        resultBooks.add(importedRef)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        resultBooks
    }

    private fun getUriMetadata(uri: Uri): Triple<String?, Long, Long> {
        var name: String? = null
        var size: Long = 0L
        var mtime: Long = 0L
        try {
            activity.contentResolver.query(
                uri,
                arrayOf(
                    OpenableColumns.DISPLAY_NAME,
                    OpenableColumns.SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED
                ),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                    val mtimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                    if (nameIdx != -1) name = cursor.getString(nameIdx)
                    if (sizeIdx != -1) size = cursor.getLong(sizeIdx)
                    if (mtimeIdx != -1) mtime = cursor.getLong(mtimeIdx)
                }
            }
        } catch (_: Exception) {}

        if (name == null) {
            try {
                val doc = DocumentFile.fromSingleUri(activity, uri)
                name = doc?.name
                if (size == 0L) size = doc?.length() ?: 0L
                if (mtime == 0L) mtime = doc?.lastModified() ?: 0L
            } catch (_: Exception) {}
        }
        return Triple(name, size, mtime)
    }

    private fun copySingleDocumentToBooks(
        uri: Uri,
        displayName: String,
        extension: String
    ): Map<String, Any?>? {
        try {
            val destDir = getBooksDirectory()
            val finalDest = getUniqueFile(destDir, displayName)
            val tempFile = File(destDir, "${finalDest.name}.tmp_${System.currentTimeMillis()}")
            activity.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            if (tempFile.length() == 0L) {
                tempFile.delete()
                return null
            }
            tempFile.copyTo(finalDest, overwrite = true)
            tempFile.delete()

            return mapOf(
                "sourceType" to MODE_IMPORTED,
                "filePath" to finalDest.absolutePath,
                "sourceUri" to uri.toString(),
                "displayName" to displayName,
                "size" to finalDest.length(),
                "lastModified" to finalDest.lastModified(),
                "format" to extension,
            )
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    fun releasePersistableUriPermission(uriString: String) {
        try {
            val uri = Uri.parse(uriString)
            if (DocumentsContract.isTreeUri(uri)) return
            val hasDirectGrant = activity.contentResolver.persistedUriPermissions.any { it.uri == uri }
            if (hasDirectGrant) {
                removePersistedUri(uri)
            }
        } catch (e: Exception) {
            e.printStackTrace()
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
                                    "sourceUri" to file.uri.toString(),
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
                                "sourceUri" to file.uri.toString(),
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
     * Uses a caching mechanism based on URI hash, size, and last modified time.
     */
    private suspend fun copyUriToCache(
        uri: Uri,
        suggestedName: String?,
        force: Boolean = false
    ): String =
        withContext(Dispatchers.IO) {
            // Validate permission first
            if (!hasValidPermission(uri)) {
                throw SecurityException(
                    "Permission denied for URI. The file may have been moved or the app was reinstalled. " +
                    "Please re-add the folder containing this book."
                )
            }

            // Get metadata for cache key
            var size = 0L
            var mtime = 0L
            
            try {
                activity.contentResolver.query(
                    uri,
                    arrayOf(
                        android.provider.OpenableColumns.SIZE,
                        android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED
                    ),
                    null, null, null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val sizeIdx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                        val mtimeIdx = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                        if (sizeIdx != -1) size = cursor.getLong(sizeIdx)
                        if (mtimeIdx != -1) mtime = cursor.getLong(mtimeIdx)
                    }
                }
            } catch (e: Exception) {
                // Metadata query failed, fallback to fresh copy every time by using random key
                mtime = System.currentTimeMillis()
            }

            val cacheDir = File(activity.cacheDir, SAF_CACHE_DIR)
            if (!cacheDir.exists()) cacheDir.mkdirs()

            val cacheKey = "${uri.toString().hashCode().toUInt()}_${size}_$mtime"
            val safeName = sanitizeFileName(suggestedName ?: "linked")
            val extension = safeName.substringAfterLast('.', "")
            val suffix = if (extension.isNotEmpty()) ".$extension" else ""
            
            // Check cache
            val cachedFile = File(cacheDir, "$cacheKey$suffix")
            val isSizeMatch = if (size > 0L) cachedFile.length() == size else cachedFile.length() > 0
            if (!force && cachedFile.exists() && cachedFile.length() > 0 && isSizeMatch) {
                // Cache hit! Update mtime to prevent early cleanup
                cachedFile.setLastModified(System.currentTimeMillis())
                return@withContext cachedFile.absolutePath
            }

            // Cache miss — copy to atomic temporary file first to prevent concurrent readers from seeing 0-byte/truncated files
            val tempFile = File(cacheDir, "$cacheKey.tmp_${System.currentTimeMillis()}")
            try {
                if (force && cachedFile.exists()) {
                    cachedFile.delete()
                }
                val input = activity.contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("Unable to open URI stream. The file may no longer exist.")
                input.use { stream ->
                    FileOutputStream(tempFile).use { output ->
                        stream.copyTo(output)
                    }
                }
                if (tempFile.length() == 0L) {
                    tempFile.delete()
                    throw IllegalStateException("Copied 0 bytes from URI: stream is empty or still syncing.")
                }
                if (cachedFile.exists()) {
                    cachedFile.delete()
                }
                if (!tempFile.renameTo(cachedFile)) {
                    tempFile.copyTo(cachedFile, overwrite = true)
                    tempFile.delete()
                }
            } catch (e: Exception) {
                if (tempFile.exists()) tempFile.delete()
                throw e
            }
            
            cachedFile.absolutePath
        }

    /**
     * Cleans up the SAF cache based on age and total size.
     */
    fun cleanupSafCache(
        maxAgeMs: Long = 7 * 24 * 60 * 60 * 1000L, // 7 days
        maxSizeMB: Int = 500
    ) {
        val cacheDir = File(activity.cacheDir, SAF_CACHE_DIR)
        if (!cacheDir.exists()) return

        val files = cacheDir.listFiles() ?: return
        val now = System.currentTimeMillis()

        // Phase 1: Delete files older than maxAge
        files.filter { now - it.lastModified() > maxAgeMs }
             .forEach { it.delete() }

        // Phase 2: If still too big, delete oldest first
        val remaining = cacheDir.listFiles()?.toList() ?: return
        val sorted = remaining.sortedBy { it.lastModified() }
        var totalSize = sorted.sumOf { it.length() }
        val maxBytes = maxSizeMB * 1024L * 1024L

        for (file in sorted) {
            if (totalSize <= maxBytes) break
            totalSize -= file.length()
            file.delete()
        }
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
