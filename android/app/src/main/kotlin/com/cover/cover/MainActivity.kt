package com.cover.cover

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import com.cover.cover.NativeAdFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register the native ad factory with the same factoryId used in Dart code
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "list",
            NativeAdFactory(this)
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Unregister when the activity is destroyed
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "list")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

