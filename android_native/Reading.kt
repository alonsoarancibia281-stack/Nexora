package ai.nexora.nexora_markets_ai

import io.flutter.plugin.common.MethodCall

/** Mirrors the Dart `OverlayGuard`. */
enum class Guard { OFF, ARMED, TRIGGERED;

    companion object {
        fun of(index: Int?): Guard = when (index) {
            1 -> ARMED
            2 -> TRIGGERED
            else -> OFF
        }
    }
}

/**
 * One snapshot of the council's verdict, as the floating readout shows it.
 *
 * [roundEndsAt] is already expressed on the device clock, so the overlay can
 * keep counting down on its own while Flutter is backgrounded and throttled.
 */
data class Reading(
    val headline: String,
    val detail: String,
    val probability: Double,
    val up: Boolean,
    val hasReading: Boolean,
    val roundEndsAt: Long,
    val guard: Guard,
    val guardDetail: String,
    val actionLabel: String,
) {
    companion object {
        val empty = Reading(
            headline = "ANALIZANDO",
            detail = "",
            probability = 50.0,
            up = true,
            hasReading = false,
            roundEndsAt = 0L,
            guard = Guard.OFF,
            guardDetail = "",
            actionLabel = "",
        )

        fun from(call: MethodCall): Reading = Reading(
            headline = call.argument<String>("headline") ?: empty.headline,
            detail = call.argument<String>("detail") ?: "",
            probability = call.argument<Double>("probability") ?: 50.0,
            up = call.argument<Boolean>("up") ?: true,
            hasReading = call.argument<Boolean>("hasReading") ?: false,
            roundEndsAt = call.argument<Number>("roundEndsAt")?.toLong() ?: 0L,
            guard = Guard.of(call.argument<Number>("guard")?.toInt()),
            guardDetail = call.argument<String>("guardDetail") ?: "",
            actionLabel = call.argument<String>("actionLabel") ?: "",
        )
    }
}
