package ai.nexora.nexora_markets_ai

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity plus the bridge for the floating readout.
 *
 * This file is copied over the wrapper the CI generates with `flutter create`,
 * so it is the one place where the Android side of Nexora lives.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(canDrawOverlay())

            // Android never lets an app grant itself the overlay permission;
            // all we can do is take the user to the screen that does.
            "requestPermission" -> {
                if (!canDrawOverlay()) openOverlaySettings()
                result.success(canDrawOverlay())
            }

            "start" -> {
                if (!canDrawOverlay()) {
                    result.success(false)
                    return
                }
                OverlayService.latest = Reading.from(call)
                val intent = Intent(this, OverlayService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(intent)
                } else {
                    startService(intent)
                }
                result.success(true)
            }

            // Returns whatever the user tapped on the panel since the last
            // update, so Flutter — which owns the protection logic — can act on
            // it without a channel pointing the other way.
            "update" -> {
                OverlayService.render(Reading.from(call))
                result.success(OverlayService.consumeAction())
            }

            "stop" -> {
                stopService(Intent(this, OverlayService::class.java))
                result.success(true)
            }

            "isRunning" -> result.success(OverlayService.isRunning)

            else -> result.notImplemented()
        }
    }

    private fun canDrawOverlay(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private companion object {
        const val CHANNEL = "ai.nexora/overlay"
    }
}
