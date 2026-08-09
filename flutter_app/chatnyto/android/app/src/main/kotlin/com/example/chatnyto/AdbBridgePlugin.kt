package com.example.chatnyto

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.atomic.AtomicInteger

/**
 * Two ways of running a shell command that this app cannot do on its own.
 *
 * Shizuku is a service the user starts with adb or root; once running it
 * will execute commands with shell privileges for apps it has granted
 * permission to. That is what makes a phone able to debug itself with no
 * computer in the room.
 *
 * Termux is a terminal with a real adb binary in it, including the USB host
 * support an ordinary app has no way to get. Talking to it means asking its
 * RunCommandService, which will only listen if the user has turned on
 * `allow-external-apps` in Termux's own properties file — a deliberate act,
 * and the right one to require.
 *
 * Everything here answers with a reason rather than an exception when the
 * other app is absent, because "not installed" is the ordinary case.
 */
class AdbBridgePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "chatnyto/adb_bridge"

        private const val SHIZUKU_REQUEST_CODE = 4713
        private const val TERMUX_PACKAGE = "com.termux"
        private const val TERMUX_SERVICE = "com.termux.app.RunCommandService"
        private const val TERMUX_ACTION = "com.termux.RUN_COMMAND"
        private const val TERMUX_RESULT = "com.example.chatnyto.TERMUX_RESULT"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val nextExecution = AtomicInteger(1)
    private val awaiting = HashMap<Int, MethodChannel.Result>()

    private var permissionResult: MethodChannel.Result? = null

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode != SHIZUKU_REQUEST_CODE) return@OnRequestPermissionResultListener
            val pending = permissionResult
            permissionResult = null
            pending?.success(grantResult == PackageManager.PERMISSION_GRANTED)
        }

    /**
     * Termux hands output back through a PendingIntent rather than on the
     * call, so the reply arrives here, minutes later if the command is slow.
     * Each one carries the id it was started with.
     */
    private val termuxReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val bundle = intent?.getBundleExtra("result") ?: return
            val id = intent.getIntExtra("chatnyto_execution", 0)
            val pending = awaiting.remove(id) ?: return
            val stdout = bundle.getString("stdout") ?: ""
            val stderr = bundle.getString("stderr") ?: ""
            val code = bundle.getInt("exitCode", -1)
            val text = buildString {
                append(stdout)
                if (stderr.isNotBlank()) {
                    if (isNotEmpty()) append('\n')
                    append(stderr)
                }
                if (code != 0 && isEmpty()) append("Exited with $code.")
            }
            mainHandler.post { pending.success(text) }
        }
    }

    fun attach() {
        try {
            Shizuku.addRequestPermissionResultListener(permissionListener)
        } catch (_: Throwable) {
            // Shizuku's own classes throw when the manager is not installed.
        }
        val filter = IntentFilter(TERMUX_RESULT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(termuxReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(termuxReceiver, filter)
        }
    }

    fun detach() {
        try {
            Shizuku.removeRequestPermissionResultListener(permissionListener)
        } catch (_: Throwable) {
        }
        try {
            context.unregisterReceiver(termuxReceiver)
        } catch (_: Throwable) {
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shizukuState" -> result.success(shizukuState())
            "shizukuRequest" -> requestShizuku(result)
            "shizukuRun" -> runWithShizuku(call.argument<String>("command") ?: "", result)
            "termuxAvailable" -> result.success(termuxInstalled())
            "termuxRun" -> runInTermux(
                call.argument<String>("path") ?: "",
                call.argument<List<String>>("arguments") ?: emptyList(),
                result,
            )
            else -> result.notImplemented()
        }
    }

    // ----------------------------------------------------------- shizuku

    private fun shizukuState(): String = try {
        when {
            !Shizuku.pingBinder() -> "notRunning"
            Shizuku.isPreV11() -> "notRunning"
            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED -> "granted"
            else -> "denied"
        }
    } catch (_: Throwable) {
        // Thrown when the Shizuku manager is not installed at all.
        "missing"
    }

    private fun requestShizuku(result: MethodChannel.Result) {
        try {
            if (!Shizuku.pingBinder()) {
                result.success(false)
                return
            }
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                result.success(true)
                return
            }
            if (Shizuku.shouldShowRequestPermissionRationale()) {
                // The user has refused before and asked not to be asked again.
                result.success(false)
                return
            }
            permissionResult = result
            Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
        } catch (error: Throwable) {
            result.success(false)
        }
    }

    /**
     * Runs a command through Shizuku.
     *
     * `newProcess` is not part of Shizuku's published API — it is marked
     * restricted so that ordinary apps do not reach for it casually — but it
     * is the only entry point that starts a process with shell privileges,
     * and it is what every adb-less tool uses. Reflection rather than a
     * direct call so that a Shizuku version without it fails with a message
     * instead of refusing to link.
     */
    private fun runWithShizuku(command: String, result: MethodChannel.Result) {
        if (command.isBlank()) {
            result.success("")
            return
        }
        Thread {
            val text = try {
                if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                    "Shizuku has not granted permission to this app."
                } else {
                    val method = Shizuku::class.java.getDeclaredMethod(
                        "newProcess",
                        Array<String>::class.java,
                        Array<String>::class.java,
                        String::class.java,
                    )
                    method.isAccessible = true
                    val process = method.invoke(
                        null,
                        arrayOf("sh", "-c", command),
                        null,
                        null,
                    )
                    readProcess(process)
                }
            } catch (error: Throwable) {
                "Shizuku could not run that: ${error.message}"
            }
            mainHandler.post { result.success(text) }
        }.start()
    }

    /** Reads stdout and stderr off whatever object Shizuku handed back. */
    private fun readProcess(process: Any?): String {
        if (process == null) return "Shizuku returned nothing."
        val type = process.javaClass
        val out = type.getMethod("getInputStream").invoke(process) as java.io.InputStream
        val err = type.getMethod("getErrorStream").invoke(process) as java.io.InputStream
        val stdout = BufferedReader(InputStreamReader(out)).readText()
        val stderr = BufferedReader(InputStreamReader(err)).readText()
        try {
            type.getMethod("waitFor").invoke(process)
        } catch (_: Throwable) {
        }
        return if (stderr.isBlank()) stdout else "$stdout\n$stderr".trim()
    }

    // ------------------------------------------------------------ termux

    private fun termuxInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    } catch (_: Throwable) {
        false
    }

    private fun runInTermux(
        path: String,
        arguments: List<String>,
        result: MethodChannel.Result,
    ) {
        if (!termuxInstalled()) {
            result.error("no_termux", "Termux is not installed.", null)
            return
        }
        val id = nextExecution.getAndIncrement()
        awaiting[id] = result

        val callback = Intent(TERMUX_RESULT).apply {
            setPackage(context.packageName)
            putExtra("chatnyto_execution", id)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_MUTABLE
            } else {
                0
            }
        val pending = PendingIntent.getBroadcast(context, id, callback, flags)

        val intent = Intent().apply {
            setClassName(TERMUX_PACKAGE, TERMUX_SERVICE)
            action = TERMUX_ACTION
            putExtra("com.termux.RUN_COMMAND_PATH", path)
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arguments.toTypedArray())
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", "0")
            putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pending)
        }
        try {
            context.startService(intent)
        } catch (error: Throwable) {
            awaiting.remove(id)
            result.error(
                "termux_refused",
                "Termux would not take the command. Set allow-external-apps=true " +
                    "in ~/.termux/termux.properties and restart it.",
                null,
            )
            return
        }
        // Termux answers through the broadcast above; if it never does, the
        // Dart side is left waiting, so time the wait out here instead.
        mainHandler.postDelayed({
            val pendingResult = awaiting.remove(id) ?: return@postDelayed
            pendingResult.success("Termux did not answer. Is allow-external-apps on?")
        }, 30_000)
    }

    private fun Bundle.stringOr(key: String, fallback: String) =
        getString(key) ?: fallback
}
