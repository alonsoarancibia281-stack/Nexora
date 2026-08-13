package ai.nexora.nexora_markets_ai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Floating readout drawn on top of whatever app is in front.
 *
 * The point is the Binance app: the user watches the chart there and keeps
 * Nexora's call for the running five-minute candle in the corner of the
 * screen. The overlay does not read what is underneath it — the analysis comes
 * from the same Binance market feed Nexora already receives — and it places no
 * orders. What it does do is shout when a position the user armed has gone
 * against them, which is the moment they are least likely to be looking here.
 *
 * It runs as a foreground service because that is what keeps the process (and
 * therefore the council, the countdown and the websocket) alive once Nexora
 * itself is no longer the app in front.
 */
class OverlayService : Service() {

    private lateinit var windows: WindowManager
    private lateinit var params: WindowManager.LayoutParams
    private var panel: LinearLayout? = null

    private lateinit var background: GradientDrawable
    private lateinit var headline: TextView
    private lateinit var probability: TextView
    private lateinit var detail: TextView
    private lateinit var countdown: TextView
    private lateinit var guardLine: TextView
    private lateinit var actionButton: TextView

    private var alarmShown = false

    private val main = Handler(Looper.getMainLooper())
    private val ticker = object : Runnable {
        override fun run() {
            drawCountdown()
            main.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windows = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startForeground(NOTIFICATION_ID, notification(Reading.empty))
        attachPanel()
        instance = this
        isRunning = true
        draw()
        main.post(ticker)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        draw()
        return START_STICKY
    }

    override fun onDestroy() {
        main.removeCallbacks(ticker)
        panel?.let { view -> runCatching { windows.removeView(view) } }
        panel = null
        instance = null
        isRunning = false
        super.onDestroy()
    }

    // -------------------------------------------------------------------------
    // The panel
    // -------------------------------------------------------------------------

    private fun attachPanel() {
        background = GradientDrawable().apply {
            cornerRadius = dp(18f).toFloat()
            setColor(SURFACE)
            setStroke(dp(1f), BORDER)
        }

        val view = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14f), dp(11f), dp(14f), dp(12f))
            this.background = this@OverlayService.background
            elevation = dp(6f).toFloat()
        }

        // Everything above the button is the drag handle; a plain tap on it
        // brings Nexora back to the front.
        val handle = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        val topRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        headline = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 19f)
            setTextColor(RISE)
            includeFontPadding = false
            typeface = Typeface.DEFAULT_BOLD
        }
        probability = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(INK_SOFT)
            includeFontPadding = false
            setPadding(dp(8f), 0, 0, 0)
        }
        topRow.addView(headline)
        topRow.addView(probability)

        detail = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextColor(INK_FAINT)
            includeFontPadding = false
            setPadding(0, dp(3f), 0, 0)
        }

        countdown = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(INK)
            includeFontPadding = false
            typeface = Typeface.MONOSPACE
            setPadding(0, dp(5f), 0, 0)
        }

        guardLine = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            setTextColor(INK_SOFT)
            includeFontPadding = false
            setPadding(0, dp(5f), 0, 0)
        }

        handle.addView(topRow)
        handle.addView(detail)
        handle.addView(countdown)
        handle.addView(guardLine)
        handle.setOnTouchListener(DragListener())

        actionButton = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f)
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(12f), dp(8f), dp(12f), dp(8f))
            background = pill(PRIMARY)
            setOnClickListener { onActionTapped() }
        }
        val buttonRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(9f), 0, 0)
            addView(
                actionButton,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }

        view.addView(handle)
        view.addView(buttonRow)

        params = WindowManager.LayoutParams(
            dp(196f),
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12f)
            y = dp(96f)
        }

        runCatching { windows.addView(view, params) }
        panel = view
    }

    private fun pill(color: Int): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dp(30f).toFloat()
        setColor(color)
    }

    /** Drag to move, tap to come back to Nexora. */
    private inner class DragListener : View.OnTouchListener {
        private var startX = 0
        private var startY = 0
        private var touchX = 0f
        private var touchY = 0f
        private var moved = false

        override fun onTouch(view: View, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (abs(dx) > dp(6f) || abs(dy) > dp(6f)) moved = true
                    params.x = startX + dx.roundToInt()
                    params.y = startY + dy.roundToInt()
                    panel?.let { runCatching { windows.updateViewLayout(it, params) } }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) openNexora()
                    return true
                }
            }
            return false
        }
    }

    /**
     * The button arms the protection, clears it, or acknowledges the alarm —
     * whichever the current state calls for. Flutter owns that decision, so the
     * tap is parked here and collected on the next update; the label flips
     * immediately so the tap does not feel ignored.
     */
    private fun onActionTapped() {
        pendingAction = "toggle"
        actionButton.text = "…"
        if (latest.guard == Guard.TRIGGERED) {
            alarmShown = false
            latest = latest.copy(guard = Guard.OFF)
            draw()
        }
    }

    private fun openNexora() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return
        startActivity(intent)
    }

    // -------------------------------------------------------------------------
    // Rendering
    // -------------------------------------------------------------------------

    private fun draw() {
        if (panel == null) return
        val reading = latest
        val alarm = reading.guard == Guard.TRIGGERED

        headline.text = if (alarm) "CIERRA AHORA" else reading.headline
        headline.setTextColor(
            when {
                alarm -> Color.WHITE
                !reading.hasReading -> PRIMARY
                reading.up -> RISE
                else -> FALL
            },
        )

        background.setColor(if (alarm) FALL else SURFACE)
        background.setStroke(dp(1f), if (alarm) FALL else BORDER)

        probability.text =
            if (reading.hasReading && !alarm) "${"%.1f".format(reading.probability)}%" else ""
        probability.setTextColor(if (alarm) Color.WHITE else INK_SOFT)

        detail.text = reading.detail
        detail.visibility = if (reading.detail.isEmpty()) View.GONE else View.VISIBLE
        detail.setTextColor(if (alarm) ALARM_SOFT else INK_FAINT)

        countdown.setTextColor(if (alarm) Color.WHITE else INK)

        guardLine.text = reading.guardDetail
        guardLine.visibility =
            if (reading.guardDetail.isEmpty()) View.GONE else View.VISIBLE
        guardLine.setTextColor(if (alarm) ALARM_SOFT else INK_SOFT)

        actionButton.text = reading.actionLabel
        actionButton.visibility =
            if (reading.actionLabel.isEmpty()) View.GONE else View.VISIBLE
        actionButton.background = pill(if (alarm) Color.WHITE else PRIMARY)
        actionButton.setTextColor(if (alarm) FALL else Color.WHITE)

        if (alarm && !alarmShown) {
            alarmShown = true
            alert(reading)
        } else if (!alarm) {
            alarmShown = false
        }

        drawCountdown()
    }

    private fun drawCountdown() {
        if (panel == null) return
        val endsAt = latest.roundEndsAt
        if (endsAt <= 0L) {
            countdown.text = "--:--"
            return
        }
        val left = ((endsAt - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
        countdown.text = "%02d:%02d".format(left / 60, left % 60)
    }

    /** Vibrate and raise the notification: the user is looking at Binance. */
    private fun alert(reading: Reading) {
        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        val pattern = longArrayOf(0, 220, 120, 220)
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(VibrationEffect.createWaveform(pattern, -1))
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, -1)
            }
        }
        runCatching {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, notification(reading))
        }
    }

    // -------------------------------------------------------------------------
    // Plumbing
    // -------------------------------------------------------------------------

    private fun notification(reading: Reading): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Superposición de Nexora",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) }
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }

        val tap = packageManager.getLaunchIntentForPackage(packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pending = tap?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val alarm = reading.guard == Guard.TRIGGERED
        return builder
            .setContentTitle(
                if (alarm) "Cierra la operación" else "Nexora sobre Binance",
            )
            .setContentText(
                if (alarm) {
                    reading.guardDetail.ifEmpty { "El mercado se puso en contra." }
                } else {
                    "Veredicto de la vela de 5 minutos en pantalla"
                },
            )
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setOngoing(true)
            .apply { pending?.let { setContentIntent(it) } }
            .build()
    }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun dp(value: Float): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        value,
        resources.displayMetrics,
    ).roundToInt()

    companion object {
        private const val CHANNEL_ID = "nexora_overlay"
        private const val NOTIFICATION_ID = 4711

        // Styleguide tokens, kept in sync with LiquidPalette.
        private val PRIMARY = Color.parseColor("#DF5830")
        private val SURFACE = Color.parseColor("#FFFFFF")
        private val BORDER = Color.parseColor("#DFE2E4")
        private val INK = Color.parseColor("#1E1B19")
        private val INK_SOFT = Color.parseColor("#6B6560")
        private val INK_FAINT = Color.parseColor("#9A938C")
        private val RISE = Color.parseColor("#12876A")
        private val FALL = Color.parseColor("#C93B3B")
        private val ALARM_SOFT = Color.parseColor("#FBEAEA")

        @Volatile
        var latest: Reading = Reading.empty

        @Volatile
        var isRunning: Boolean = false
            private set

        /** Set by the panel button, drained by Flutter on the next update. */
        @Volatile
        private var pendingAction: String = ""

        private var instance: OverlayService? = null

        /** Pushes a fresh reading into the running panel, if there is one. */
        fun render(reading: Reading) {
            latest = reading
            instance?.let { service -> service.main.post { service.draw() } }
        }

        /** Hands Flutter whatever the user tapped, once. */
        fun consumeAction(): String {
            val action = pendingAction
            pendingAction = ""
            return action
        }
    }
}
