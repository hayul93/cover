import Foundation
import google_mobile_ads
import GoogleMobileAds
import UIKit

class ListTileNativeAdFactory: FLTNativeAdFactory {
    func createNativeAd(
        _ nativeAd: GADNativeAd,
        customOptions: [AnyHashable : Any]? = nil
    ) -> GADNativeAdView? {
        let nibView = Bundle.main.loadNibNamed("ListTileNativeAdView", owner: nil, options: nil)?.first
        guard let nativeAdView = nibView as? GADNativeAdView else {
            return nil
        }

        // 다크모드 감지
        let isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark

        // 다크모드에 따른 색상 설정
        let backgroundColor = isDarkMode ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) : UIColor.white
        let primaryTextColor = isDarkMode ? UIColor.white : UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.87)
        let secondaryTextColor = isDarkMode ? UIColor(white: 1.0, alpha: 0.7) : UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.54)
        let mediaBackgroundColor = isDarkMode ? UIColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0) : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)

        // 배경색 적용
        nativeAdView.backgroundColor = backgroundColor

        // MediaView 설정
        if let mediaView = nativeAdView.mediaView {
            mediaView.backgroundColor = mediaBackgroundColor
            mediaView.contentMode = .scaleAspectFill
            mediaView.clipsToBounds = true
            mediaView.layer.cornerRadius = 8
        }

        // Icon
        if let iconView = nativeAdView.iconView as? UIImageView {
            iconView.image = nativeAd.icon?.image
            iconView.layer.cornerRadius = 8
            iconView.clipsToBounds = true
        }
        nativeAdView.iconView?.isHidden = nativeAd.icon == nil

        // Headline
        if let headlineLabel = nativeAdView.headlineView as? UILabel {
            headlineLabel.text = nativeAd.headline
            headlineLabel.textColor = primaryTextColor
        }
        nativeAdView.headlineView?.isHidden = nativeAd.headline == nil

        // Body
        if let bodyLabel = nativeAdView.bodyView as? UILabel {
            bodyLabel.text = nativeAd.body
            bodyLabel.textColor = secondaryTextColor
        }
        nativeAdView.bodyView?.isHidden = nativeAd.body == nil

        // Call To Action
        if let ctaButton = nativeAdView.callToActionView as? UIButton {
            ctaButton.setTitle(nativeAd.callToAction, for: .normal)
            ctaButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 12)
            ctaButton.layer.cornerRadius = 6
            ctaButton.clipsToBounds = true
            // Primary 색상 (파란색)
            ctaButton.backgroundColor = UIColor(red: 0.129, green: 0.588, blue: 0.953, alpha: 1.0)
            ctaButton.setTitleColor(.white, for: .normal)
            ctaButton.isUserInteractionEnabled = false
        }
        nativeAdView.callToActionView?.isHidden = nativeAd.callToAction == nil

        nativeAdView.nativeAd = nativeAd

        return nativeAdView
    }
}
