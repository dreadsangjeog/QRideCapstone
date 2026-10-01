package com.qride.demo

import android.annotation.SuppressLint
import android.os.Build
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Keeps GPS_PROVIDER subscribed for the rental foreground-service isolate.
 *
 * A one-shot fused request returns the cached point and then unsubscribes, so
 * the pin stops moving once QRide is backgrounded. This listener stays
 * registered until the ride ends, including while the screen is locked.
 * [setMaxUpdateDelayMillis] is 0 so Android does not batch those fixes until
 * the screen turns back on.
 */
class RideGpsBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val channel = EventChannel(messenger, CHANNEL)
    private val locationManager =
        context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var events: EventChannel.EventSink? = null
    private var listener: LocationListener? = null
    private val oneShotListeners = mutableListOf<LocationListener>()

    init {
        channel.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopUpdates()
        this.events = events
        if (!hasLocationPermission()) {
            events.error("permission", "Location permission is not granted", null)
            return
        }

        val provider = when {
            locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ->
                LocationManager.GPS_PROVIDER
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) ->
                LocationManager.NETWORK_PROVIDER
            else -> null
        }
        if (provider == null) {
            events.error("gps_off", "GPS is turned off", null)
            return
        }

        val gpsListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                emit(location)
            }

            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

            override fun onProviderEnabled(provider: String) {}

            override fun onProviderDisabled(provider: String) {}
        }
        listener = gpsListener
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                requestUpdatesModern(provider, gpsListener)
            } else {
                requestUpdatesLegacy(provider, gpsListener)
            }
            emitNewestLastKnown()
            requestFastFirstFix(provider)
        } catch (e: SecurityException) {
            Log.e(TAG, "GPS listen failed", e)
            events.error("permission", e.message, null)
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "GPS provider missing", e)
            events.error("gps_off", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stopUpdates()
    }

    fun dispose() {
        stopUpdates()
        channel.setStreamHandler(null)
    }

    @SuppressLint("MissingPermission")
    @Suppress("NewApi")
    private fun requestUpdatesModern(provider: String, gpsListener: LocationListener) {
        val request = android.location.LocationRequest.Builder(INTERVAL_MS)
            .setQuality(android.location.LocationRequest.QUALITY_HIGH_ACCURACY)
            .setMinUpdateIntervalMillis(MIN_INTERVAL_MS)
            .setMinUpdateDistanceMeters(0f)
            // 0 keeps fixes flowing while the screen is off instead of batching them.
            .setMaxUpdateDelayMillis(0L)
            .build()
        locationManager.requestLocationUpdates(
            provider,
            request,
            context.mainExecutor,
            gpsListener,
        )
        Log.d(TAG, "Listening on $provider")
    }

    @SuppressLint("MissingPermission")
    private fun requestUpdatesLegacy(provider: String, gpsListener: LocationListener) {
        locationManager.requestLocationUpdates(
            provider,
            INTERVAL_MS,
            0f,
            gpsListener,
            Looper.getMainLooper(),
        )
        Log.d(TAG, "Listening on $provider")
    }

    private fun emit(location: Location) {
        val sink = events ?: return
        val headingOk = location.hasBearing()
        val speedOk = location.hasSpeed()
        sink.success(
            mapOf(
                "lat" to location.latitude,
                "lng" to location.longitude,
                "accuracy" to location.accuracy.toDouble(),
                "altitude" to location.altitude,
                "heading" to location.bearing.toDouble(),
                "heading_ok" to headingOk,
                "speed" to location.speed.toDouble(),
                "speed_ok" to speedOk,
                "time" to location.time,
            ),
        )
    }

    /**
     * GPS_PROVIDER's first satellite fix is often ~30–40s. The map the rider
     * already has open is on the fused provider, so that cached point (and one
     * quick network/fused update) is what puts the pin on the admin map.
     */
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
        if (newest != null) emit(newest)
    }

    @SuppressLint("MissingPermission")
    private fun requestFastFirstFix(primary: String) {
        val extras = mutableListOf<String>()
        if (primary != LocationManager.NETWORK_PROVIDER &&
            locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        ) {
            extras.add(LocationManager.NETWORK_PROVIDER)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            primary != LocationManager.FUSED_PROVIDER &&
            locationManager.isProviderEnabled(LocationManager.FUSED_PROVIDER)
        ) {
            extras.add(LocationManager.FUSED_PROVIDER)
        }
        for (name in extras) {
            val once = object : LocationListener {
                override fun onLocationChanged(location: Location) {
                    emit(location)
                    try {
                        locationManager.removeUpdates(this)
                    } catch (_: SecurityException) {
                    }
                    oneShotListeners.remove(this)
                }

                @Deprecated("Deprecated in Java")
                override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

                override fun onProviderEnabled(provider: String) {}

                override fun onProviderDisabled(provider: String) {}
            }
            oneShotListeners.add(once)
            try {
                locationManager.requestLocationUpdates(
                    name,
                    0L,
                    0f,
                    once,
                    Looper.getMainLooper(),
                )
            } catch (e: Exception) {
                oneShotListeners.remove(once)
                Log.w(TAG, "fast first fix on $name failed", e)
            }
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

    private fun stopUpdates() {
        listener?.let { locationManager.removeUpdates(it) }
        listener = null
        for (once in oneShotListeners.toList()) {
            try {
                locationManager.removeUpdates(once)
            } catch (_: Exception) {
            }
        }
        oneShotListeners.clear()
        events = null
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

    companion object {
        const val CHANNEL = "com.qride.demo/ride_gps"
        private const val TAG = "QRideGps"
        private const val INTERVAL_MS = 2000L
        private const val MIN_INTERVAL_MS = 1000L
    }
}
