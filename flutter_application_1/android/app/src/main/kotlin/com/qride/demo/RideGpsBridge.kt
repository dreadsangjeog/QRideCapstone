package com.qride.demo

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Granularity
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest as GmsLocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/**
 * GPS listener for the rental foreground-service isolate.
 *
 * Play Services fused location is the listener that keeps delivering after the
 * screen has been off for a few minutes. The raw GPS provider goes quiet on
 * many phones around then, and a new request started while the screen is still
 * off is ignored. This registration is therefore left in place for the whole
 * ride. Dart may drop and reopen its event subscription; that must not remove
 * the fused request. A fresh request is made only from [rebind], which the app
 * calls while QRide is on screen.
 */
class RideGpsBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val channel = EventChannel(messenger, CHANNEL)
    private val methods = MethodChannel(messenger, METHOD_CHANNEL)
    private val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private val gpsThread = HandlerThread("qride-ride-gps").apply { start() }
    private val gpsHandler = Handler(gpsThread.looper)
    private val gpsExecutor = Executor { command -> gpsHandler.post(command) }
    private val lock = Any()

    @Volatile
    private var events: EventChannel.EventSink? = null

    @Volatile
    private var tracking = false

    private val listeners = mutableListOf<LocationListener>()
    private var fusedClient: FusedLocationProviderClient? = null
    private var usingFused = false
    private var legacyOn = false
    private var wakeLock: PowerManager.WakeLock? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var nudgeToken: CancellationTokenSource? = null
    private var pending: Map<String, Any>? = null

    @Volatile
    private var lastPreciseAt = 0L

    @Volatile
    private var lastAnyAt = 0L

    @Volatile
    private var lastDeliveredAt = 0L

    @Volatile
    private var lastNudgeAt = 0L

    private val fusedCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            onExternalFix(location)
        }
    }

    private val watch = object : Runnable {
        override fun run() {
            if (!tracking) return
            acquireWakeLock()
            val now = SystemClock.elapsedRealtime()
            val sinceAny = now - lastAnyAt
            val sinceDelivered = now - lastDeliveredAt
            // Do not remove the fused request here. A replacement started
            // while the screen is off is ignored, and the old one is already
            // gone, so the pin stays frozen after QRide is opened.
            if ((sinceDelivered > NUDGE_AFTER_MS || sinceAny > NUDGE_AFTER_MS) &&
                now - lastNudgeAt > NUDGE_AFTER_MS
            ) {
                lastNudgeAt = now
                nudge()
            }
            gpsHandler.postDelayed(this, WATCH_MS)
        }
    }

    init {
        channel.setStreamHandler(this)
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "nudge" -> {
                    nudge()
                    result.success(null)
                }
                "rebind" -> {
                    rebind()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        this.events = events
        if (!hasLocationPermission()) {
            events.error("permission", "Location permission is not granted", null)
            return
        }
        if (!tracking) {
            val now = SystemClock.elapsedRealtime()
            lastAnyAt = now
            lastDeliveredAt = now
            acquireWakeLock()
            startTracking()
            if (!tracking) {
                events.error("gps_off", "GPS is turned off", null)
                return
            }
            registerGnss()
            emitNewestLastKnown()
            gpsHandler.removeCallbacks(watch)
            gpsHandler.postDelayed(watch, WATCH_MS)
            Log.d(TAG, if (usingFused) "Listening on fused" else "Listening on legacy")
        } else {
            acquireWakeLock()
        }
        pending?.let { payload ->
            mainHandler.post {
                if (this.events === events) {
                    try {
                        events.success(payload)
                    } catch (error: Exception) {
                        Log.w(TAG, "GPS event dropped", error)
                    }
                }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        // The Flutter subscription can drop while the phone is locked. Removing
        // the fused request here is what made GPS stay dead after QRide opened.
        events = null
    }

    fun dispose() {
        synchronized(lock) {
            events = null
            pending = null
            gpsHandler.removeCallbacks(watch)
            stopProviders()
            releaseWakeLock()
        }
        channel.setStreamHandler(null)
        methods.setMethodCallHandler(null)
        gpsThread.quitSafely()
    }

    /**
     * Opens a new fused request. Only call this while QRide is on screen.
     * A request started with the screen off is dropped.
     */
    @SuppressLint("MissingPermission")
    private fun rebind() {
        if (!hasLocationPermission()) return
        synchronized(lock) {
            stopProviders()
            startTracking()
            registerGnss()
            acquireWakeLock()
            if (tracking) {
                gpsHandler.removeCallbacks(watch)
                gpsHandler.postDelayed(watch, WATCH_MS)
            }
        }
        Log.d(TAG, "Rebound ride GPS")
    }

    fun onExternalFix(location: Location) {
        synchronized(lock) {
            onFix(location)
        }
    }

    @SuppressLint("MissingPermission")
    private fun startTracking() {
        if (tracking) return
        if (startFused()) {
            usingFused = true
            tracking = true
            return
        }
        if (startLegacy()) {
            legacyOn = true
            tracking = true
        }
    }

    @SuppressLint("MissingPermission")
    private fun startFused(): Boolean {
        return try {
            val client = LocationServices.getFusedLocationProviderClient(context)
            val request = fusedRequest()
            client.requestLocationUpdates(request, gpsExecutor, fusedCallback)
                .addOnFailureListener { error ->
                    Log.w(TAG, "Fused updates rejected", error)
                    gpsHandler.post {
                        synchronized(lock) {
                            if (usingFused && !legacyOn) {
                                val current = fusedClient
                                try {
                                    current?.removeLocationUpdates(fusedCallback)
                                } catch (_: Exception) {
                                }
                                try {
                                    current?.removeLocationUpdates(locationPendingIntent())
                                } catch (_: Exception) {
                                }
                                fusedClient = null
                                usingFused = false
                                if (startLegacy()) {
                                    legacyOn = true
                                    tracking = true
                                }
                            }
                        }
                    }
                }
            try {
                client.requestLocationUpdates(request, locationPendingIntent())
            } catch (error: Exception) {
                Log.w(TAG, "Fused delivery intent rejected", error)
            }
            fusedClient = client
            true
        } catch (error: Exception) {
            Log.w(TAG, "Fused location unavailable", error)
            false
        }
    }

    private fun fusedRequest(): GmsLocationRequest {
        val builder = GmsLocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, INTERVAL_MS)
            .setMinUpdateIntervalMillis(MIN_INTERVAL_MS)
            .setMaxUpdateDelayMillis(INTERVAL_MS)
            .setMinUpdateDistanceMeters(0f)
            .setWaitForAccurateLocation(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setGranularity(Granularity.GRANULARITY_FINE)
        }
        return builder.build()
    }

    private fun locationPendingIntent(): PendingIntent {
        val intent = Intent(context, RideGpsReceiver::class.java).apply {
            action = ACTION_LOCATION
            setPackage(context.packageName)
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getBroadcast(context, PI_REQUEST, intent, flags)
    }

    @SuppressLint("MissingPermission")
    private fun startLegacy(): Boolean {
        val providers = liveProviders()
        if (providers.isEmpty()) return false
        for (provider in providers) {
            listen(provider)
        }
        return listeners.isNotEmpty()
    }

    @SuppressLint("MissingPermission")
    private fun listen(provider: String) {
        val gpsListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                onExternalFix(location)
            }

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

            override fun onProviderEnabled(provider: String) {}

            override fun onProviderDisabled(provider: String) {}
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                (provider == LocationManager.GPS_PROVIDER ||
                    provider == LocationManager.FUSED_PROVIDER)
            ) {
                locationManager.requestLocationUpdates(
                    provider,
                    highAccuracyRequest(),
                    gpsExecutor,
                    gpsListener,
                )
            } else {
                locationManager.requestLocationUpdates(
                    provider,
                    INTERVAL_MS,
                    0f,
                    gpsListener,
                    gpsThread.looper,
                )
            }
            listeners.add(gpsListener)
        } catch (error: SecurityException) {
            Log.e(TAG, "GPS listen failed on $provider", error)
        } catch (error: IllegalArgumentException) {
            Log.w(TAG, "GPS provider missing: $provider", error)
            try {
                locationManager.requestLocationUpdates(
                    provider,
                    INTERVAL_MS,
                    0f,
                    gpsListener,
                    gpsThread.looper,
                )
                listeners.add(gpsListener)
            } catch (fallback: Exception) {
                Log.w(TAG, "GPS legacy listen failed on $provider", fallback)
            }
        }
    }

    /**
     * One fresh high-accuracy point. Does not remove the ride listener.
     */
    @SuppressLint("MissingPermission")
    private fun nudge() {
        if (!hasLocationPermission()) return
        acquireWakeLock()
        val client = fusedClient
        if (client != null && usingFused) {
            nudgeToken?.cancel()
            val token = CancellationTokenSource()
            nudgeToken = token
            client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, token.token)
                .addOnSuccessListener(gpsExecutor) { location ->
                    if (location != null) onExternalFix(location)
                }
            return
        }
        nudgeLegacy()
    }

    @SuppressLint("MissingPermission")
    private fun nudgeLegacy() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val providers = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            providerEnabled(LocationManager.FUSED_PROVIDER)
        ) {
            providers.add(LocationManager.FUSED_PROVIDER)
        }
        if (providerEnabled(LocationManager.GPS_PROVIDER)) {
            providers.add(LocationManager.GPS_PROVIDER)
        }
        for (provider in providers) {
            try {
                locationManager.getCurrentLocation(
                    provider,
                    null,
                    gpsExecutor,
                ) { location ->
                    if (location != null) onExternalFix(location)
                }
            } catch (error: Exception) {
                Log.w(TAG, "nudge $provider failed", error)
            }
        }
    }

    private fun onFix(location: Location) {
        lastAnyAt = SystemClock.elapsedRealtime()
        emit(location)
    }

    private fun emit(location: Location) {
        if (location.latitude == 0.0 && location.longitude == 0.0) return
        // A cell-tower point must not replace a recent GPS fix. After a
        // minute with no tight fix, only a moderately accurate point may
        // move the pin, and the Dart gate still rejects an impossible jump.
        val accurate = location.hasAccuracy() && location.accuracy <= 50f
        val now = SystemClock.elapsedRealtime()
        if (accurate) {
            lastPreciseAt = now
        } else if (lastPreciseAt != 0L && now - lastPreciseAt < 60_000L) {
            return
        } else if (!location.hasAccuracy() || location.accuracy > 80f) {
            return
        }
        val ageMs = System.currentTimeMillis() - location.time
        if (location.time > 0 && ageMs in -5_000..15_000) {
            lastDeliveredAt = now
        }
        val payload = mapOf(
            "lat" to location.latitude,
            "lng" to location.longitude,
            "accuracy" to location.accuracy.toDouble(),
            "altitude" to location.altitude,
            "heading" to location.bearing.toDouble(),
            "heading_ok" to location.hasBearing(),
            "speed" to location.speed.toDouble(),
            "speed_ok" to location.hasSpeed(),
            "time" to location.time,
        )
        pending = payload
        if (events == null) return
        mainHandler.post {
            try {
                events?.success(payload)
            } catch (error: Exception) {
                Log.w(TAG, "GPS event dropped", error)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun emitNewestLastKnown() {
        val newest = lastKnownProviders()
            .mapNotNull { name ->
                try {
                    locationManager.getLastKnownLocation(name)
                } catch (_: SecurityException) {
                    null
                }
            }
            .filter { it.latitude != 0.0 || it.longitude != 0.0 }
            .maxByOrNull { it.time }
        if (newest != null) onFix(newest)
    }

    private fun liveProviders(): List<String> {
        val names = mutableListOf<String>()
        if (providerEnabled(LocationManager.GPS_PROVIDER)) {
            names.add(LocationManager.GPS_PROVIDER)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            providerEnabled(LocationManager.FUSED_PROVIDER)
        ) {
            names.add(LocationManager.FUSED_PROVIDER)
        }
        if (providerEnabled(LocationManager.NETWORK_PROVIDER)) {
            names.add(LocationManager.NETWORK_PROVIDER)
        }
        return names
    }

    private fun providerEnabled(name: String): Boolean {
        return try {
            locationManager.isProviderEnabled(name)
        } catch (_: Exception) {
            false
        }
    }

    private fun lastKnownProviders(): List<String> {
        val names = mutableListOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER,
            LocationManager.PASSIVE_PROVIDER,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            names.add(LocationManager.FUSED_PROVIDER)
        }
        return names
    }

    @SuppressLint("MissingPermission")
    private fun registerGnss() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (gnssCallback != null) return
        val callback = object : GnssStatus.Callback() {}
        try {
            @Suppress("DEPRECATION")
            locationManager.registerGnssStatusCallback(callback, gpsHandler)
            gnssCallback = callback
        } catch (error: Exception) {
            Log.w(TAG, "GNSS status unavailable", error)
        }
    }

    private fun unregisterGnss() {
        val callback = gnssCallback ?: return
        gnssCallback = null
        try {
            locationManager.unregisterGnssStatusCallback(callback)
        } catch (_: Exception) {
        }
    }

    private fun stopProviders() {
        tracking = false
        usingFused = false
        legacyOn = false
        nudgeToken?.cancel()
        nudgeToken = null
        unregisterGnss()
        val client = fusedClient
        if (client != null) {
            try {
                client.removeLocationUpdates(fusedCallback)
            } catch (_: Exception) {
            }
            try {
                client.removeLocationUpdates(locationPendingIntent())
            } catch (_: Exception) {
            }
        }
        fusedClient = null
        for (listener in listeners.toList()) {
            try {
                locationManager.removeUpdates(listener)
            } catch (_: Exception) {
            }
        }
        listeners.clear()
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val held = wakeLock
        if (held != null && held.isHeld) return
        val lock = held ?: pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "QRide:RideGps",
        ).also {
            it.setReferenceCounted(false)
            wakeLock = it
        }
        lock.acquire()
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: RuntimeException) {
        }
        wakeLock = null
    }

    private fun hasLocationPermission(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    @androidx.annotation.RequiresApi(Build.VERSION_CODES.S)
    private fun highAccuracyRequest(): android.location.LocationRequest {
        return android.location.LocationRequest.Builder(INTERVAL_MS)
            .setQuality(android.location.LocationRequest.QUALITY_HIGH_ACCURACY)
            .setMinUpdateIntervalMillis(MIN_INTERVAL_MS)
            .setMaxUpdateDelayMillis(INTERVAL_MS)
            .setMinUpdateDistanceMeters(0f)
            .build()
    }

    companion object {
        const val CHANNEL = "com.qride.demo/ride_gps"
        const val METHOD_CHANNEL = "com.qride.demo/ride_gps_ctl"
        const val ACTION_LOCATION = "com.qride.demo.action.RIDE_LOCATION"
        private const val TAG = "QRideGps"
        private const val PI_REQUEST = 9021
        private const val INTERVAL_MS = 2000L
        private const val MIN_INTERVAL_MS = 1000L
        private const val WATCH_MS = 10_000L
        private const val NUDGE_AFTER_MS = 20_000L
    }
}

/** Receives fused fixes when the process is idle and the callback is deferred. */
class RideGpsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val location = LocationResult.extractResult(intent)?.lastLocation ?: return
        val app = context.applicationContext as? QRideApplication ?: return
        app.deliverRideFix(location)
    }
}
