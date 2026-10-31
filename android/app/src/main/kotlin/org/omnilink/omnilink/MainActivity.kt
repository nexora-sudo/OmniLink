package org.omnilink.omnilink

import android.app.Activity
import android.content.Intent
import android.os.StatFs
import android.os.Build
import android.os.Environment
import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingExport: MethodChannel.Result? = null
    private var exportSource: File? = null
    private var publicResult: MethodChannel.Result? = null
    private var publicSource: File? = null
    private var publicGallery = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.omnilink/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePublic" -> {
                        if (publicResult != null) {
                            result.error("BUSY", "Aguarde o salvamento atual.", null)
                        } else {
                            try {
                                val source = File(requireNotNull(call.argument<String>("path")))
                                require(source.isFile) { "Arquivo não encontrado." }
                                publicSource = source
                                publicGallery = call.argument<Boolean>("gallery") == true
                                publicResult = result
                                if (Build.VERSION.SDK_INT < 29 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 6102)
                                } else { savePublicFile() }
                            } catch (e: Exception) {
                                publicResult = null; publicSource = null
                                result.error("SAVE", e.message, null)
                            }
                        }
                    }
                    "freeBytes" -> {
                        try {
                            val path = call.argument<String>("path") ?: filesDir.path
                            result.success(StatFs(path).availableBytes)
                        } catch (e: Exception) { result.error("STORAGE", e.message, null) }
                    }
                    "exportFile" -> {
                        if (pendingExport != null) {
                            result.error("BUSY", "Uma exportação já está aberta.", null)
                        } else {
                            try {
                                val source = File(requireNotNull(call.argument<String>("path")))
                                require(source.isFile) { "Arquivo não encontrado." }
                                pendingExport = result
                                exportSource = source
                                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    type = "application/octet-stream"
                                    putExtra(Intent.EXTRA_TITLE, source.name)
                                }
                                startActivityForResult(intent, 6101)
                            } catch (e: Exception) {
                                pendingExport = null; exportSource = null
                                result.error("EXPORT", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != 6102) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            savePublicFile()
        } else {
            publicResult?.error("PERMISSION", "Permissão negada. Você ainda pode usar Salvar em…", null)
            publicResult = null; publicSource = null
        }
    }

    private fun savePublicFile() {
        val result = publicResult ?: return
        val source = publicSource ?: return
        val gallery = publicGallery
        Thread {
            try {
                val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(source.extension.lowercase()) ?: "application/octet-stream"
                require(!gallery || mime.startsWith("image/") || mime.startsWith("video/")) { "Este formato não pode ser salvo na galeria. Use Downloads ou Salvar em…" }
                val folder = if (!gallery) Environment.DIRECTORY_DOWNLOADS else if (mime.startsWith("video/")) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                val location: String
                if (Build.VERSION.SDK_INT >= 29) {
                    val collection = if (!gallery) MediaStore.Downloads.EXTERNAL_CONTENT_URI else if (mime.startsWith("video/")) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
                        put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, "$folder/OmniLink")
                        put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val uri = requireNotNull(contentResolver.insert(collection, values)) { "Não foi possível criar o destino." }
                    try {
                        contentResolver.openOutputStream(uri, "w").use { output ->
                            requireNotNull(output)
                            source.inputStream().use { it.copyTo(output, 262144) }
                        }
                        val published = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                        check(contentResolver.update(uri, published, null, null) == 1) { "Não foi possível publicar o arquivo." }
                        location = "$folder/OmniLink"
                    } catch (e: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw e
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val directory = File(Environment.getExternalStoragePublicDirectory(folder), "OmniLink")
                    check(directory.isDirectory || directory.mkdirs()) { "Não foi possível criar a pasta." }
                    var target = File(directory, source.name)
                    var number = 1
                    while (!target.createNewFile()) {
                        target = File(directory, "${source.nameWithoutExtension} (${number++})${if (source.extension.isEmpty()) "" else ".${source.extension}"}")
                    }
                    try { source.inputStream().use { input -> target.outputStream().use { input.copyTo(it, 262144) } } }
                    catch (e: Exception) { target.delete(); throw e }
                    MediaScannerConnection.scanFile(this, arrayOf(target.path), arrayOf(mime), null)
                    location = target.path
                }
                runOnUiThread { publicResult = null; publicSource = null; result.success(location) }
            } catch (e: Exception) {
                runOnUiThread { publicResult = null; publicSource = null; result.error("SAVE", e.message, null) }
            }
        }.start()
    }

    @Deprecated("Activity result bridge for the Flutter platform channel")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 6101) return
        val result = pendingExport ?: return
        val source = exportSource
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || source == null || uri == null) {
            pendingExport = null; exportSource = null
            result.success(null)
            return
        }
        Thread {
            try {
                contentResolver.openOutputStream(uri, "w").use { output ->
                    requireNotNull(output) { "Não foi possível abrir o destino." }
                    source.inputStream().use { it.copyTo(output, 262144) }
                }
                runOnUiThread {
                    pendingExport = null; exportSource = null
                    result.success(null)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    pendingExport = null; exportSource = null
                    result.error("EXPORT", e.message, null)
                }
            }
        }.start()
    }
}
