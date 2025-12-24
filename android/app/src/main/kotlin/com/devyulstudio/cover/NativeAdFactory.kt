package com.devyulstudio.cover

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class NativeAdFactory(private val context: Context) : GoogleMobileAdsPlugin.NativeAdFactory {
    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.native_ad, null) as NativeAdView

        // 다크모드 감지
        val isDarkMode = (context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

        // 색상 설정
        val backgroundColor = if (isDarkMode) Color.parseColor("#1C1C1E") else Color.WHITE
        val primaryTextColor = if (isDarkMode) Color.WHITE else Color.parseColor("#DE000000")
        val secondaryTextColor = if (isDarkMode) Color.parseColor("#B3FFFFFF") else Color.parseColor("#8A000000")
        val mediaBackgroundColor = if (isDarkMode) Color.parseColor("#262629") else Color.parseColor("#F2F2F7")

        // 배경색 적용
        adView.setBackgroundColor(backgroundColor)

        // MediaView
        val mediaView = adView.findViewById<MediaView>(R.id.ad_media)
        mediaView.setBackgroundColor(mediaBackgroundColor)
        // cornerRadius 적용
        val mediaDrawable = GradientDrawable().apply {
            setColor(mediaBackgroundColor)
            cornerRadius = 8 * context.resources.displayMetrics.density
        }
        mediaView.background = mediaDrawable
        adView.mediaView = mediaView

        // Headline
        val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
        headlineView.text = nativeAd.headline
        headlineView.setTextColor(primaryTextColor)
        adView.headlineView = headlineView

        // Body
        val bodyView = adView.findViewById<TextView>(R.id.ad_body)
        bodyView.text = nativeAd.body
        bodyView.setTextColor(secondaryTextColor)
        adView.bodyView = bodyView

        // Icon
        val iconView = adView.findViewById<ImageView>(R.id.ad_icon)
        nativeAd.icon?.let {
            iconView.setImageDrawable(it.drawable)
            iconView.visibility = View.VISIBLE
        } ?: run {
            iconView.visibility = View.GONE
        }
        // cornerRadius 적용
        iconView.clipToOutline = true
        adView.iconView = iconView

        // Ad attribution
        val adAttribution = adView.findViewById<TextView>(R.id.ad_attribution)
        adAttribution.text = "Ad"

        // Call To Action Button
        val ctaButton = adView.findViewById<Button>(R.id.ad_call_to_action)
        nativeAd.callToAction?.let { cta ->
            ctaButton.text = cta
            ctaButton.visibility = View.VISIBLE
            // Primary 색상 (파란색) 배경
            val ctaDrawable = GradientDrawable().apply {
                setColor(Color.parseColor("#2196F3"))
                cornerRadius = 6 * context.resources.displayMetrics.density
            }
            ctaButton.background = ctaDrawable
            ctaButton.setTextColor(Color.WHITE)
        } ?: run {
            ctaButton.visibility = View.GONE
        }
        adView.callToActionView = ctaButton

        adView.setNativeAd(nativeAd)
        return adView
    }
}
