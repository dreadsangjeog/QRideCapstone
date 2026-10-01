package com.qride.demo

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the rental GPS listener on the foreground-service Flutter engine.
 *
 * That engine is not the activity engine. The activity can be stopped with the
 * screen off while this listener keeps running inside the rental service.
 */
class QRideApplication : Application() {
    private var rideGps: RideGpsBridge? = null

    override fun onCreate() {
        super.onCreate()
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(
            object : FlutterForegroundTaskLifecycleListener {
                override fun onEngineCreate(flutterEngine: FlutterEngine?) {
                    val engine = flutterEngine ?: return
                    rideGps?.dispose()
                    rideGps = RideGpsBridge(
                        applicationContext,
                        engine.dartExecutor.binaryMessenger,
                    )
                }

                override fun onTaskStart(starter: FlutterForegroundTaskStarter) {}

                override fun onTaskRepeatEvent() {}

                override fun onTaskDestroy() {}

                override fun onEngineWillDestroy() {
                    rideGps?.dispose()
                    rideGps = null
                }
            },
        )
    }
}
