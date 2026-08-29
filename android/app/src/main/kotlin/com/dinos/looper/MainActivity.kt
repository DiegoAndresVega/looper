package com.dinos.looper

import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one thing this app needs from the platform and Flutter does not ship:
 * how much room is left on the device.
 *
 * It is a handful of lines rather than a package on purpose — a new native
 * dependency has to survive the versions this project pins by force, and this
 * answer is one call to StatFs.
 */
class MainActivity : FlutterActivity() {
    private val channel = "looper/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeBytes" -> result.success(freeBytes())
                    else -> result.notImplemented()
                }
            }
    }

    private fun freeBytes(): Long? = try {
        val path = filesDir ?: return null
        val stat = StatFs(path.absolutePath)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            stat.availableBlocksLong * stat.blockSizeLong
        } else {
            @Suppress("DEPRECATION")
            stat.availableBlocks.toLong() * stat.blockSize.toLong()
        }
    } catch (e: Exception) {
        null
    }
}
