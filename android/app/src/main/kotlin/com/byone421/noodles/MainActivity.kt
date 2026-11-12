package com.byone421.noodles

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var exportPath: String? = null
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "noodles/data_transfer")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "请先完成当前文件选择", null)
                    return@setMethodCallHandler
                }
                val intent: Intent
                val request: Int
                when (call.method) {
                    "pickFile" -> {
                        intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                        }
                        request = 9101
                    }
                    "pickImageFolder" -> {
                        intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        request = 9102
                    }
                    "exportFile" -> {
                        val path = call.argument<String>("path")
                        if (path == null || !File(path).isFile ||
                            !File(path).canonicalPath.startsWith(cacheDir.canonicalPath + File.separator)) {
                            result.error("file", "导出文件不存在", null)
                            return@setMethodCallHandler
                        }
                        exportPath = path
                        intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "万物备份.json")
                        }
                        request = 9103
                    }
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                pending = result
                try { startActivityForResult(intent, request) }
                catch (e: Exception) { pending = null; result.error("picker", "无法打开系统文件选择器", null) }
            }
    }

    @Deprecated("Activity result compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode !in 9101..9103) return
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(null)
            return
        }
        worker.execute {
            val staging = File(cacheDir, "transfer_${System.nanoTime()}")
            try {
                val response: Any = when (requestCode) {
                    9101 -> {
                        staging.mkdirs()
                        val file = File(staging, "source")
                        copyDocument(uri, file, 100L * 1024 * 1024)
                        mapOf("path" to file.path, "name" to displayName(uri))
                    }
                    9102 -> {
                        staging.mkdirs()
                        val root = DocumentsContract.getTreeDocumentId(uri)
                        val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, root)
                        val files = linkedMapOf<String, String>()
                        var manifest: JSONObject? = null
                        var total = 0L
                        contentResolver.query(children, arrayOf(
                            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                            DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
                            while (cursor.moveToNext()) {
                                val name = cursor.getString(1)
                                val mime = cursor.getString(2)
                                if (name == "image_manifest.json") {
                                    val manifestUri = DocumentsContract.buildDocumentUriUsingTree(uri, cursor.getString(0))
                                    val file = File(staging, "manifest.json")
                                    copyDocument(manifestUri, file, 2L * 1024 * 1024)
                                    manifest = JSONObject(file.readText(Charsets.UTF_8))
                                    file.delete()
                                    continue
                                }
                                if (mime == DocumentsContract.Document.MIME_TYPE_DIR ||
                                    !(mime.startsWith("image/") || name.substringAfterLast('.', "").lowercase()
                                        in listOf("jpg", "jpeg", "png", "webp", "heic", "gif", "bmp"))) continue
                                check(files.size < 1000) { "图片超过 1000 张，请分批选择" }
                                val child = DocumentsContract.buildDocumentUriUsingTree(uri, cursor.getString(0))
                                val file = File(staging, "${files.size}.image")
                                total += copyDocument(child, file, 20L * 1024 * 1024)
                                check(total <= 100L * 1024 * 1024) { "图片总量超过 100 MB，请分批导入" }
                                check(!files.containsKey(name)) { "图片文件名重复" }
                                files[name] = file.path
                            }
                        } ?: error("无法读取图片目录")
                        manifest?.let { mapping ->
                            val keys = mapping.keys()
                            val originals = linkedMapOf<String, String>()
                            while (keys.hasNext()) {
                                val original = keys.next()
                                files[mapping.getString(original)]?.let { originals[original] = it }
                            }
                            files.putAll(originals)
                        }
                        files
                    }
                    else -> {
                        val file = File(exportPath ?: error("没有可导出的文件"))
                        contentResolver.openOutputStream(uri, "wt")?.use { output ->
                            file.inputStream().use { it.copyTo(output) }
                        } ?: error("无法写入所选位置")
                        true
                    }
                }
                runOnUiThread { pending = null; result.success(response) }
            } catch (e: Exception) {
                staging.deleteRecursively()
                runOnUiThread { pending = null; result.error("transfer", e.message ?: "文件读写失败", null) }
            }
        }
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return "导入文件"
    }

    private fun copyDocument(uri: Uri, file: File, limit: Long): Long {
        var size = 0L
        contentResolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { output ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    size += count
                    check(size <= limit) { "所选文件过大" }
                    output.write(buffer, 0, count)
                }
            }
        } ?: error("无法读取所选文件")
        return size
    }
}
