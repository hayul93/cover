package com.cover.cover

import android.content.Context
import android.view.LayoutInflater
import android.widget.ImageView
import android.widget.TextView
import com.cover.cover.R
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class NativeAdFactory(private val context: Context) : GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        // Inflate the custom layout we added under res/layout/native_ad.xml
        val adView = LayoutInflater.from(context).inflate(R.layout.native_ad, null) as NativeAdView

        // Icon
        val iconView = adView.findViewById<ImageView>(R.id.native_ad_icon)
        nativeAd.icon?.let { iconView.setImageDrawable(it.drawable) }
        adView.iconView = iconView

        // Headline
        val headlineView = adView.findViewById<TextView>(R.id.native_ad_headline)
        headlineView.text = nativeAd.headline
        adView.headlineView = headlineView

        // Body
        val bodyView = adView.findViewById<TextView>(R.id.native_ad_body)
        bodyView.text = nativeAd.body
        adView.bodyView = bodyView

        // Call to Action
        val ctaView = adView.findViewById<android.widget.Button>(R.id.native_ad_call_to_action)
        ctaView.text = nativeAd.callToAction
        adView.callToActionView = ctaView

        // Register the native ad with the view
        adView.setNativeAd(nativeAd)
        return adView
    }
}
