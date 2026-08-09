package dev.lore.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors

internal class AndroidLibraryAccessController(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val preferences = activity.getSharedPreferences(PREFERENCES_NAME, Activity.MODE_PRIVATE)
    private var pendingResult: MethodChannel.Result? = null
    private var pendingUri: Uri? = null
    private var pendingBaseUri: Uri? = null
    private var pendingName: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "restoreLibraryDirectory" -> restore(result)
            "selectLibraryDirectory" -> select(result)
            "createLibraryDirectory" -> create(result, call)
            "commitLibraryDirectory" -> commit(result)
            "discardLibraryDirectorySelection" -> {
                discardPending()
                result.success(null)
            }
            "clearLibraryDirectory" -> {
                clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_LIBRARY_DIRECTORY) return false
        val result = pendingResult ?: return true
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            clearPendingCreateState()
            result.success(null)
            return true
        }
        val baseUri = data.data!!
        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        val alreadyGranted = activity.contentResolver.persistedUriPermissions.any {
            it.uri == baseUri && it.isReadPermission && it.isWritePermission
        }
        if (!alreadyGranted) {
            try {
                activity.contentResolver.takePersistableUriPermission(baseUri, flags)
            } catch (error: SecurityException) {
                clearPendingCreateState()
                result.error("access_denied", "无法保留所选目录的访问权限。", null)
                return true
            }
        }

        val name = pendingName
        if (name == null) {
            pendingBaseUri = baseUri
            pendingUri = baseUri
            result.success(accessValue(baseUri))
            return true
        }

        val rootDocUri = DocumentsContract.buildDocumentUriUsingTree(
            baseUri,
            DocumentsContract.getTreeDocumentId(baseUri),
        )
        try {
            val created = DocumentsContract.createDocument(
                activity.contentResolver,
                rootDocUri,
                Document.MIME_TYPE_DIR,
                name,
            )
            if (created == null) {
                rollbackPendingCreate(baseUri, alreadyGranted)
                result.error("already_exists", "同名目录已存在。", null)
                return true
            }
            val tokenUri = DocumentsContract.buildTreeDocumentUri(
                created.authority,
                DocumentsContract.getDocumentId(created),
            )
            pendingBaseUri = baseUri
            pendingUri = tokenUri
            result.success(accessValue(tokenUri, name))
        } catch (error: Exception) {
            rollbackPendingCreate(baseUri, alreadyGranted)
            val code = when (error) {
                is SecurityException -> "permission_denied"
                is java.io.FileNotFoundException -> "not_writable"
                else -> "io"
            }
            result.error(code, "无法在所选位置创建书库目录。", null)
        }
        return true
    }

    fun dispose() {
        pendingResult?.success(null)
        pendingResult = null
        channel.setMethodCallHandler(null)
    }

    private fun restore(result: MethodChannel.Result) {
        val value = preferences.getString(URI_KEY, null)
        if (value == null) {
            result.success(null)
            return
        }
        val baseUri = Uri.parse(value)
        val granted = activity.contentResolver.persistedUriPermissions.any {
            it.uri == baseUri && it.isReadPermission && it.isWritePermission
        }
        if (!granted) {
            preferences.edit()
                .remove(URI_KEY)
                .remove(LIBRARY_URI_KEY)
                .apply()
            result.error("access_denied", "书库目录授权已失效，请重新选择。", null)
            return
        }
        // 兼容旧版本单 key（treeUri）安装：此时 token 即授权树本身。
        val token = preferences.getString(LIBRARY_URI_KEY, null)
            ?.let { Uri.parse(it) }
            ?: baseUri
        result.success(accessValue(token, displayName(token)))
    }

    private fun select(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("selection_in_progress", "正在选择书库目录。", null)
            return
        }
        pendingName = null
        discardPending()
        pendingResult = result
        launchTreePicker()
    }

    private fun create(result: MethodChannel.Result, call: MethodCall) {
        if (pendingResult != null) {
            result.error("selection_in_progress", "正在选择书库目录。", null)
            return
        }
        val name = call.argument<String>("name")?.trim().orEmpty()
        if (!isValidLibraryName(name)) {
            result.error("invalid_name", "书库名称无效。", null)
            return
        }
        discardPending()
        pendingName = name
        pendingResult = result
        launchTreePicker()
    }

    private fun launchTreePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_LIBRARY_DIRECTORY)
    }

    private fun isValidLibraryName(name: String): Boolean {
        return name.isNotEmpty() &&
            name != "." &&
            name != ".." &&
            !name.contains('/') &&
            !name.contains('\\') &&
            name.length <= 255
    }

    private fun commit(result: MethodChannel.Result) {
        val baseUri = pendingBaseUri
        val uri = pendingUri
        if (baseUri == null || uri == null) {
            result.error("access_denied", "没有等待提交的目录授权。", null)
            return
        }
        preferences.edit()
            .putString(URI_KEY, baseUri.toString())
            .putString(LIBRARY_URI_KEY, uri.toString())
            .apply()
        pendingBaseUri = null
        pendingUri = null
        pendingName = null
        result.success(null)
    }

    private fun discardPending() {
        val uri = pendingBaseUri ?: pendingUri ?: return
        release(uri)
        pendingUri = null
        pendingBaseUri = null
        pendingName = null
    }

    private fun clear() {
        discardPending()
        preferences.getString(URI_KEY, null)?.let { release(Uri.parse(it)) }
        preferences.edit()
            .remove(URI_KEY)
            .remove(LIBRARY_URI_KEY)
            .apply()
    }

    private fun release(uri: Uri) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
        }
    }

    private fun clearPendingCreateState() {
        pendingName = null
        pendingBaseUri = null
        pendingUri = null
    }

    private fun rollbackPendingCreate(baseUri: Uri, alreadyGranted: Boolean) {
        if (!alreadyGranted) {
            release(baseUri)
        }
        clearPendingCreateState()
    }

    private fun accessValue(uri: Uri, displayPath: String? = null) = mapOf(
        "token" to uri.toString(),
        "displayPath" to (displayPath ?: uri.lastPathSegment.orEmpty()),
    )

    private fun displayName(uri: Uri): String? {
        return try {
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                uri,
                DocumentsContract.getTreeDocumentId(uri),
            )
            activity.contentResolver.query(
                documentUri,
                arrayOf(Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL_NAME = "dev.lore.app/android_library_access"
        private const val PREFERENCES_NAME = "lore.library.access"
        private const val URI_KEY = "treeUri"
        private const val LIBRARY_URI_KEY = "libraryTreeUri"
        private const val REQUEST_LIBRARY_DIRECTORY = 4172
    }
}

internal class AndroidLibraryStorageController(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private val store = SafDocumentStore(activity)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        runSaf(result) {
            when (call.method) {
                "getCapabilities" -> mapOf(
                    "atomicReplace" to false,
                    "move" to true,
                    "rename" to true,
                    "caseSensitive" to true,
                )
                "list" -> store.list(call.token(), call.path())
                "stat" -> store.stat(call.token(), call.path())
                "readBytes" -> store.readBytes(call.token(), call.path())
                "createDirectory" -> {
                    store.createDirectory(call.token(), call.path())
                    null
                }
                "createFile" -> {
                    store.createFile(call.token(), call.path(), call.bytes())
                    null
                }
                "replaceFile" -> store.replaceFile(
                    call.token(),
                    call.path(),
                    call.argument<String>("expectedRevision")
                        ?: throw SafFailure("invalid_location", "缺少 revision。"),
                    call.bytes(),
                )
                "move" -> {
                    store.move(
                        call.token(),
                        call.argument<String>("source").orEmpty(),
                        call.argument<String>("target").orEmpty(),
                    )
                    null
                }
                "copy" -> {
                    store.copy(
                        call.token(),
                        call.argument<String>("source").orEmpty(),
                        call.argument<String>("target").orEmpty(),
                    )
                    null
                }
                "delete" -> {
                    store.delete(call.token(), call.path())
                    null
                }
                else -> throw NotImplementedError(call.method)
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private fun runSaf(result: MethodChannel.Result, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                activity.runOnUiThread { result.success(value) }
            } catch (error: NotImplementedError) {
                activity.runOnUiThread { result.notImplemented() }
            } catch (error: SafFailure) {
                activity.runOnUiThread { result.error(error.code, error.message, null) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("io", error.message ?: "Android 文件操作失败。", null)
                }
            }
        }
    }

    private fun MethodCall.token(): String =
        argument<String>("token") ?: throw SafFailure("access_denied", "缺少书库授权。")

    private fun MethodCall.path(): String = argument<String>("path").orEmpty()

    private fun MethodCall.bytes(): ByteArray =
        argument<ByteArray>("bytes") ?: throw SafFailure("invalid_location", "缺少文件内容。")

    companion object {
        private const val CHANNEL_NAME = "dev.lore.app/android_library_storage"
    }
}

private class SafDocumentStore(private val activity: Activity) {
    private val resolver get() = activity.contentResolver

    fun list(token: String, path: String): List<Map<String, Any?>> {
        val directory = resolve(token, path)
        if (!directory.isDirectory) throw SafFailure("invalid_location", "目标不是目录。")
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            directory.uri,
            directory.documentId,
        )
        val result = mutableListOf<Map<String, Any?>>()
        resolver.query(childrenUri, PROJECTION, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val child = nodeFromCursor(directory.uri, cursor)
                val childPath = if (path.isEmpty()) child.name else "$path/${child.name}"
                result.add(entryValue(childPath, child))
            }
        }
        return result
    }

    fun stat(token: String, path: String): Map<String, Any?>? {
        return try {
            val node = resolve(token, path)
            entryValue(path, node)
        } catch (error: SafFailure) {
            if (error.code == "not_found") null else throw error
        }
    }

    fun readBytes(token: String, path: String): ByteArray {
        val node = resolve(token, path)
        if (node.isDirectory) throw SafFailure("invalid_location", "目标不是文件。")
        return resolver.openInputStream(node.uri)?.use { it.readBytes() }
            ?: throw SafFailure("not_found", "文件不存在。")
    }

    fun createDirectory(token: String, path: String) {
        create(token, path, Document.MIME_TYPE_DIR, null)
    }

    fun createFile(token: String, path: String, bytes: ByteArray) {
        val uri = create(token, path, "application/octet-stream", bytes)
        verifyBytes(uri, bytes)
    }

    fun replaceFile(
        token: String,
        path: String,
        expectedRevision: String,
        bytes: ByteArray,
    ): Map<String, Any?> {
        val node = resolve(token, path)
        val current = revision(node.uri)
        if (current != expectedRevision) {
            return mapOf("success" to false, "currentRevision" to current)
        }
        resolver.openOutputStream(node.uri, "rwt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw SafFailure("not_writable", "无法写入文件。")
        verifyBytes(node.uri, bytes)
        return mapOf("success" to true, "revision" to sha256(bytes))
    }

    fun move(token: String, sourcePath: String, targetPath: String) {
        validatePath(sourcePath)
        validatePath(targetPath)
        val source = resolve(token, sourcePath)
        val sourceParentPath = parentPath(sourcePath)
        val targetParentPath = parentPath(targetPath)
        val targetName = name(targetPath)
        ensureMissing(token, targetPath)
        val sourceParent = resolve(token, sourceParentPath)
        val targetParent = resolve(token, targetParentPath)
        if (sourceParent.documentId == targetParent.documentId) {
            try {
                DocumentsContract.renameDocument(resolver, source.uri, targetName)
                    ?: throw SafFailure("io", "文档提供者拒绝重命名。")
                return
            } catch (_: Exception) {
                copy(token, sourcePath, targetPath)
                delete(token, sourcePath)
                return
            }
        }
        if (source.name != targetName) {
            copy(token, sourcePath, targetPath)
            delete(token, sourcePath)
            return
        }
        try {
            DocumentsContract.moveDocument(
                resolver,
                source.uri,
                sourceParent.uri,
                targetParent.uri,
            ) ?: throw SafFailure("io", "文档提供者拒绝移动文件。")
        } catch (_: Exception) {
            copy(token, sourcePath, targetPath)
            delete(token, sourcePath)
        }
    }

    fun copy(token: String, sourcePath: String, targetPath: String) {
        val source = resolve(token, sourcePath)
        ensureMissing(token, targetPath)
        val targetParent = resolve(token, parentPath(targetPath))
        copyNode(source, targetParent, name(targetPath))
    }

    fun delete(token: String, path: String) {
        val node = resolve(token, path)
        if (!DocumentsContract.deleteDocument(resolver, node.uri)) {
            throw SafFailure("io", "文档提供者拒绝删除文件。")
        }
    }

    private fun create(token: String, path: String, mimeType: String, bytes: ByteArray?): Uri {
        validatePath(path)
        ensureMissing(token, path)
        val parent = resolve(token, parentPath(path))
        val uri = DocumentsContract.createDocument(resolver, parent.uri, mimeType, name(path))
            ?: throw SafFailure("not_writable", "文档提供者拒绝创建文件。")
        if (bytes != null) {
            resolver.openOutputStream(uri, "rwt")?.use { it.write(bytes) }
                ?: throw SafFailure("not_writable", "无法写入新文件。")
        }
        return uri
    }

    private fun copyNode(source: SafNode, targetParent: SafNode, targetName: String): SafNode {
        if (!source.isDirectory) {
            val bytes = resolver.openInputStream(source.uri)?.use { it.readBytes() }
                ?: throw SafFailure("not_found", "源文件不存在。")
            val uri = DocumentsContract.createDocument(
                resolver,
                targetParent.uri,
                source.mimeType,
                targetName,
            ) ?: throw SafFailure("not_writable", "无法复制文件。")
            resolver.openOutputStream(uri, "rwt")?.use { it.write(bytes) }
                ?: throw SafFailure("not_writable", "无法写入复制文件。")
            verifyBytes(uri, bytes)
            return queryNode(targetParent.uri, DocumentsContract.getDocumentId(uri))
        }
        val directoryUri = DocumentsContract.createDocument(
            resolver,
            targetParent.uri,
            Document.MIME_TYPE_DIR,
            targetName,
        ) ?: throw SafFailure("not_writable", "无法复制目录。")
        val directory = queryNode(targetParent.uri, DocumentsContract.getDocumentId(directoryUri))
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            source.uri,
            source.documentId,
        )
        resolver.query(childrenUri, PROJECTION, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val child = nodeFromCursor(source.uri, cursor)
                copyNode(child, directory, child.name)
            }
        }
        return directory
    }

    private fun resolve(token: String, path: String): SafNode {
        validatePath(path, allowRoot = true)
        val treeUri = Uri.parse(token)
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        var current = queryNode(treeUri, rootId)
        if (path.isEmpty()) return current
        for (segment in path.split('/')) {
            current = findChild(current, segment)
                ?: throw SafFailure("not_found", "文件或目录不存在。")
        }
        return current
    }

    private fun findChild(parent: SafNode, name: String): SafNode? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            parent.uri,
            parent.documentId,
        )
        resolver.query(childrenUri, PROJECTION, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val child = nodeFromCursor(parent.uri, cursor)
                if (child.name == name) return child
            }
        }
        return null
    }

    private fun queryNode(treeUri: Uri, documentId: String): SafNode {
        val uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
        resolver.query(uri, PROJECTION, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return nodeFromCursor(treeUri, cursor)
        }
        throw SafFailure("not_found", "文档不存在。")
    }

    private fun nodeFromCursor(treeUri: Uri, cursor: android.database.Cursor): SafNode {
        val documentId = cursor.getString(0)
        val name = cursor.getString(1)
        val mimeType = cursor.getString(2)
        val size = if (cursor.isNull(3)) null else cursor.getLong(3)
        val flags = cursor.getLong(4)
        return SafNode(
            uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId),
            documentId = documentId,
            name = name,
            mimeType = mimeType,
            size = size,
            flags = flags,
        )
    }

    private fun entryValue(path: String, node: SafNode): Map<String, Any?> = mapOf(
        "path" to path,
        "type" to if (node.isDirectory) "directory" else "file",
        "size" to node.size,
        "revision" to if (node.isDirectory) null else revision(node.uri),
    )

    private fun ensureMissing(token: String, path: String) {
        if (stat(token, path) != null) throw SafFailure("already_exists", "目标名称已存在。")
    }

    private fun verifyBytes(uri: Uri, bytes: ByteArray) {
        if (revision(uri) != sha256(bytes)) {
            throw SafFailure("io", "写入后的文件校验失败。")
        }
    }

    private fun revision(uri: Uri): String {
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw SafFailure("not_found", "文件不存在。")
        return sha256(bytes)
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }

    private fun validatePath(path: String, allowRoot: Boolean = false) {
        if (path.isEmpty() && allowRoot) return
        if (path.isEmpty() || path.startsWith('/') || path.contains('\\')) {
            throw SafFailure("invalid_location", "书库路径无效。")
        }
        if (path.split('/').any { it.isEmpty() || it == "." || it == ".." }) {
            throw SafFailure("invalid_location", "书库路径无效。")
        }
    }

    private fun parentPath(path: String): String = path.substringBeforeLast('/', "")
    private fun name(path: String): String = path.substringAfterLast('/')

    companion object {
        private val PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_SIZE,
            Document.COLUMN_FLAGS,
        )
    }
}

private data class SafNode(
    val uri: Uri,
    val documentId: String,
    val name: String,
    val mimeType: String,
    val size: Long?,
    val flags: Long,
) {
    val isDirectory: Boolean get() = mimeType == Document.MIME_TYPE_DIR
}

private class SafFailure(val code: String, override val message: String) : Exception(message)
