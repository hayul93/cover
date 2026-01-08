import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ko'),
  ];

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      // App
      'appName': 'Cover',
      'appDescription': 'Protect your privacy - Blur in 3 seconds',

      // Home
      'home': 'Home',
      'selectImage': 'Select Image',
      'gallery': 'Gallery',
      'camera': 'Camera',
      'recentEdits': 'Recent Edits',
      'noRecentEdits': 'No recent edits',

      // Editor
      'edit': 'Edit',
      'blur': 'Blur',
      'mosaic': 'Mosaic',
      'sticker': 'Sticker',
      'eraser': 'Eraser',
      'crop': 'Crop',
      'undo': 'Undo',
      'redo': 'Redo',
      'save': 'Save',
      'share': 'Share',
      'done': 'Done',
      'cancel': 'Cancel',
      'reset': 'Reset',

      // Tools
      'brushSize': 'Brush Size',
      'intensity': 'Intensity',
      'pixelSize': 'Pixel Size',

      // Stickers
      'emoji': 'Emoji',
      'shapes': 'Shapes',
      'text': 'Text',
      'deleteSticker': 'Delete',
      'addSticker': 'Add Sticker',
      'addText': 'Add Text',

      // Editor
      'fill': 'Fill',
      'original': 'Original',
      'edited': 'Edited',
      'hideTools': 'Hide Tools',
      'showTools': 'Show Tools',
      'mode': 'Mode',
      'size': 'Size',
      'compareOriginal': 'Compare',
      'originalSize': 'Fit',
      'imageCropped': 'Image cropped',
      'saved': 'Saved',
      'processingFailed': 'Processing failed',
      'rotateFailed': 'Rotate failed',
      'cropFailed': 'Crop failed',
      'saveError': 'Save error',
      'shareError': 'Share error',
      'enterText': 'Enter Text',
      'enterTextHint': 'Enter your text',
      'add': 'Add',
      'textColor': 'Text',
      'backgroundColor': 'BG',

      // Colors
      'black': 'Black',
      'yellow': 'Yellow',
      'green': 'Green',
      'pink': 'Pink',
      'cyan': 'Cyan',

      // Crop
      'cropImage': 'Crop Image',
      'rotate': 'Rotate',
      'aspectRatio': 'Aspect Ratio',

      // Save/Share
      'saving': 'Saving...',
      'savedToGallery': 'Saved to gallery',
      'saveFailed': 'Save failed',
      'shareImage': 'Share Image',
      'processing': 'Processing...',

      // Settings
      'settings': 'Settings',
      'appearance': 'Appearance',
      'darkMode': 'Dark Mode',
      'darkModeDesc': 'Use dark theme',
      'language': 'Language',
      'languageDesc': 'App display language',
      'support': 'Support',
      'rateApp': 'Rate App',
      'rateAppDesc': 'Leave a review on Store',
      'privacyPolicy': 'Privacy Policy',
      'termsOfService': 'Terms of Service',
      'openSourceLicenses': 'Open Source Licenses',
      'appInfo': 'App Info',
      'version': 'Version',

      // Purchase
      'removeAds': 'Remove Ads',
      'removeAdsDesc': 'Remove all ads permanently',
      'removeAdsFullDesc': 'One-time purchase for permanent ad-free experience',
      'restore': 'Restore Purchase',
      'restoreDesc': 'Restore previous purchase',
      'purchase': 'Purchase',
      'purchased': 'Purchased',
      'lifetime': 'Lifetime',
      'oneTimePurchase': 'One-time purchase',
      'purchaseSuccess': 'Purchase successful!',
      'purchaseFailed': 'Purchase failed',
      'purchaseCancelled': 'Purchase cancelled',
      'restoreSuccess': 'Purchase restored!',
      'restoreFailed': 'No purchase to restore',
      'restoreError': 'Restore error',
      'adsRemoved': 'Ads have been removed',
      'cannotLoadProduct': 'Cannot load product info',
      'noAdsOnSave': 'No ads when saving/sharing',
      'fastSave': 'Fast save experience',
      'permanent': 'Permanent',
      'purchaseRemoveAds': 'Purchase Ad Removal',
      'oneTimePurchaseNote': 'One-time payment removes ads permanently',

      // Permissions
      'permissionRequired': 'Permission Required',
      'cameraPermission': 'Camera permission is required to take photos',
      'galleryPermission': 'Gallery permission is required to select photos',
      'storagePermission': 'Storage permission is required to save photos',
      'goToSettings': 'Go to Settings',

      // Errors
      'error': 'Error',
      'errorOccurred': 'An error occurred',
      'tryAgain': 'Try Again',
      'noImageSelected': 'No image selected',
      'imageLoadFailed': 'Failed to load image',
      'cameraError': 'Cannot access camera',
      'cannotOpenStore': 'Cannot open store',

      // Dialogs
      'confirm': 'Confirm',
      'discardChanges': 'Discard Changes?',
      'discardChangesDesc': 'Your changes will be lost.',
      'discard': 'Discard',
      'keep': 'Keep Editing',

      // Ads
      'watchAdToSave': 'Watch ad to save',
      'adLoading': 'Loading ad...',
      'adNotReady': 'Ad not ready. Try again.',
      'nativeAdLabel': 'Ad',
      'nativeAdSponsored': 'Sponsored',

      // Languages
      'english': 'English',
      'korean': '한국어',
      'systemDefault': 'System Default',

      // Onboarding
      'onboardingWelcomeTitle': 'Easy Privacy Protection',
      'onboardingWelcomeDesc': 'Protect sensitive information\nin photos with a simple touch',
      'onboardingBlurTitle': 'Blur & Mosaic',
      'onboardingBlurDesc': 'Easily hide personal info,\nfaces, and sensitive areas',
      'onboardingTextStickerTitle': 'Text & Stickers',
      'onboardingTextStickerDesc': 'Add text and stickers\nfor more creative editing',
      'onboardingSaveShareTitle': 'Save & Share',
      'onboardingSaveShareDesc': 'Save edited images to gallery\nand share directly',
      'skip': 'Skip',
      'next': 'Next',
      'getStarted': 'Get Started',
    },
    'ko': {
      // App
      'appName': 'Cover',
      'appDescription': '개인정보를 안전하게 - 3초만에 블러 처리',

      // Home
      'home': '홈',
      'selectImage': '이미지 선택',
      'gallery': '갤러리',
      'camera': '카메라',
      'recentEdits': '최근 편집',
      'noRecentEdits': '최근 편집 내역이 없습니다',

      // Editor
      'edit': '편집',
      'blur': '블러',
      'mosaic': '모자이크',
      'sticker': '스티커',
      'eraser': '지우개',
      'crop': '자르기',
      'undo': '실행 취소',
      'redo': '다시 실행',
      'save': '저장',
      'share': '공유',
      'done': '완료',
      'cancel': '취소',
      'reset': '초기화',

      // Tools
      'brushSize': '브러시 크기',
      'intensity': '강도',
      'pixelSize': '픽셀 크기',

      // Stickers
      'emoji': '이모지',
      'shapes': '도형',
      'text': '텍스트',
      'deleteSticker': '삭제',
      'addSticker': '스티커 추가',
      'addText': '텍스트 추가',

      // Editor
      'fill': '채우기',
      'original': '원본',
      'edited': '편집',
      'hideTools': '도구 숨기기',
      'showTools': '도구 보기',
      'mode': '모드',
      'size': '크기',
      'compareOriginal': '원본 비교',
      'originalSize': '원래 크기',
      'imageCropped': '이미지가 잘렸습니다',
      'saved': '저장되었습니다',
      'processingFailed': '처리 실패',
      'rotateFailed': '회전 실패',
      'cropFailed': '자르기 실패',
      'saveError': '저장 오류',
      'shareError': '공유 오류',
      'enterText': '텍스트 입력',
      'enterTextHint': '텍스트를 입력하세요',
      'add': '추가',
      'textColor': '글자',
      'backgroundColor': '배경',

      // Colors
      'black': '검정',
      'yellow': '노랑',
      'green': '초록',
      'pink': '분홍',
      'cyan': '하늘',

      // Crop
      'cropImage': '이미지 자르기',
      'rotate': '회전',
      'aspectRatio': '비율',

      // Save/Share
      'saving': '저장 중...',
      'savedToGallery': '갤러리에 저장되었습니다',
      'saveFailed': '저장 실패',
      'shareImage': '이미지 공유',
      'processing': '처리 중...',

      // Settings
      'settings': '설정',
      'appearance': '화면',
      'darkMode': '다크 모드',
      'darkModeDesc': '어두운 테마 사용',
      'language': '언어',
      'languageDesc': '앱 표시 언어',
      'support': '지원',
      'rateApp': '앱 리뷰 작성',
      'rateAppDesc': '스토어에 리뷰 남기기',
      'privacyPolicy': '개인정보 처리방침',
      'termsOfService': '이용약관',
      'openSourceLicenses': '오픈소스 라이선스',
      'appInfo': '앱 정보',
      'version': '버전',

      // Purchase
      'removeAds': '광고 제거',
      'removeAdsDesc': '모든 광고를 영구적으로 제거',
      'removeAdsFullDesc': '한 번 구매로 영구적으로 광고 없이 사용하세요',
      'restore': '구매 복원',
      'restoreDesc': '이전 구매 복원',
      'purchase': '구매하기',
      'purchased': '구매 완료',
      'lifetime': '평생',
      'oneTimePurchase': '1회 구매',
      'purchaseSuccess': '구매 완료!',
      'purchaseFailed': '구매 실패',
      'purchaseCancelled': '구매가 취소되었습니다',
      'restoreSuccess': '구매가 복원되었습니다!',
      'restoreFailed': '복원할 구매 내역이 없습니다',
      'restoreError': '복원 오류',
      'adsRemoved': '광고가 제거되었습니다',
      'cannotLoadProduct': '상품 정보를 불러올 수 없습니다',
      'noAdsOnSave': '저장/공유 시 광고 제거',
      'fastSave': '빠른 저장 경험',
      'permanent': '영구 적용',
      'purchaseRemoveAds': '광고 제거 구매하기',
      'oneTimePurchaseNote': '한 번 결제로 영구적으로 광고가 제거됩니다',

      // Permissions
      'permissionRequired': '권한 필요',
      'cameraPermission': '사진 촬영을 위해 카메라 권한이 필요합니다',
      'galleryPermission': '사진 선택을 위해 갤러리 권한이 필요합니다',
      'storagePermission': '사진 저장을 위해 저장소 권한이 필요합니다',
      'goToSettings': '설정으로 이동',

      // Errors
      'error': '오류',
      'errorOccurred': '오류가 발생했습니다',
      'tryAgain': '다시 시도',
      'noImageSelected': '이미지가 선택되지 않았습니다',
      'imageLoadFailed': '이미지를 불러오지 못했습니다',
      'cameraError': '카메라를 사용할 수 없습니다',
      'cannotOpenStore': '스토어를 열 수 없습니다',

      // Dialogs
      'confirm': '확인',
      'discardChanges': '변경사항을 버리시겠습니까?',
      'discardChangesDesc': '변경사항이 저장되지 않습니다.',
      'discard': '버리기',
      'keep': '계속 편집',

      // Ads
      'watchAdToSave': '광고를 보고 저장하기',
      'adLoading': '광고 로딩 중...',
      'adNotReady': '광고가 준비되지 않았습니다. 다시 시도해주세요.',
      'nativeAdLabel': '광고',
      'nativeAdSponsored': '스폰서',

      // Languages
      'english': 'English',
      'korean': '한국어',
      'systemDefault': '시스템 기본값',

      // Onboarding
      'onboardingWelcomeTitle': '간편한 개인정보 보호',
      'onboardingWelcomeDesc': '터치 한 번으로 사진 속\n민감한 정보를 보호하세요',
      'onboardingBlurTitle': '블러 & 모자이크',
      'onboardingBlurDesc': '개인정보, 얼굴, 민감한 부분을\n쉽게 가릴 수 있어요',
      'onboardingTextStickerTitle': '텍스트 & 스티커',
      'onboardingTextStickerDesc': '텍스트와 스티커로\n더 창의적인 편집이 가능해요',
      'onboardingSaveShareTitle': '저장 & 공유',
      'onboardingSaveShareDesc': '편집한 이미지를 갤러리에 저장하고\n바로 공유하세요',
      'skip': '건너뛰기',
      'next': '다음',
      'getStarted': '시작하기',
    },
  };

  String get(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }

  // Convenience getters
  String get appName => get('appName');
  String get appDescription => get('appDescription');
  String get home => get('home');
  String get selectImage => get('selectImage');
  String get gallery => get('gallery');
  String get camera => get('camera');
  String get recentEdits => get('recentEdits');
  String get noRecentEdits => get('noRecentEdits');
  String get edit => get('edit');
  String get blur => get('blur');
  String get mosaic => get('mosaic');
  String get sticker => get('sticker');
  String get eraser => get('eraser');
  String get crop => get('crop');
  String get undo => get('undo');
  String get redo => get('redo');
  String get save => get('save');
  String get share => get('share');
  String get done => get('done');
  String get cancel => get('cancel');
  String get reset => get('reset');
  String get brushSize => get('brushSize');
  String get intensity => get('intensity');
  String get pixelSize => get('pixelSize');
  String get emoji => get('emoji');
  String get shapes => get('shapes');
  String get deleteSticker => get('deleteSticker');
  String get cropImage => get('cropImage');
  String get rotate => get('rotate');
  String get aspectRatio => get('aspectRatio');
  String get saving => get('saving');
  String get savedToGallery => get('savedToGallery');
  String get saveFailed => get('saveFailed');
  String get shareImage => get('shareImage');
  String get processing => get('processing');
  String get settings => get('settings');
  String get appearance => get('appearance');
  String get darkMode => get('darkMode');
  String get darkModeDesc => get('darkModeDesc');
  String get language => get('language');
  String get languageDesc => get('languageDesc');
  String get support => get('support');
  String get rateApp => get('rateApp');
  String get rateAppDesc => get('rateAppDesc');
  String get privacyPolicy => get('privacyPolicy');
  String get termsOfService => get('termsOfService');
  String get openSourceLicenses => get('openSourceLicenses');
  String get appInfo => get('appInfo');
  String get version => get('version');
  String get removeAds => get('removeAds');
  String get removeAdsDesc => get('removeAdsDesc');
  String get restore => get('restore');
  String get restoreDesc => get('restoreDesc');
  String get purchase => get('purchase');
  String get purchased => get('purchased');
  String get lifetime => get('lifetime');
  String get oneTimePurchase => get('oneTimePurchase');
  String get purchaseSuccess => get('purchaseSuccess');
  String get purchaseFailed => get('purchaseFailed');
  String get restoreSuccess => get('restoreSuccess');
  String get restoreFailed => get('restoreFailed');
  String get adsRemoved => get('adsRemoved');
  String get permissionRequired => get('permissionRequired');
  String get cameraPermission => get('cameraPermission');
  String get galleryPermission => get('galleryPermission');
  String get storagePermission => get('storagePermission');
  String get goToSettings => get('goToSettings');
  String get error => get('error');
  String get errorOccurred => get('errorOccurred');
  String get tryAgain => get('tryAgain');
  String get noImageSelected => get('noImageSelected');
  String get imageLoadFailed => get('imageLoadFailed');
  String get confirm => get('confirm');
  String get discardChanges => get('discardChanges');
  String get discardChangesDesc => get('discardChangesDesc');
  String get discard => get('discard');
  String get keep => get('keep');
  String get watchAdToSave => get('watchAdToSave');
  String get adLoading => get('adLoading');
  String get adNotReady => get('adNotReady');
  String get nativeAdLabel => get('nativeAdLabel');
  String get nativeAdSponsored => get('nativeAdSponsored');
  String get english => get('english');
  String get korean => get('korean');
  String get systemDefault => get('systemDefault');

  // Editor getters
  String get text => get('text');
  String get addSticker => get('addSticker');
  String get addText => get('addText');
  String get fill => get('fill');
  String get original => get('original');
  String get edited => get('edited');
  String get hideTools => get('hideTools');
  String get showTools => get('showTools');
  String get mode => get('mode');
  String get size => get('size');
  String get compareOriginal => get('compareOriginal');
  String get originalSize => get('originalSize');
  String get imageCropped => get('imageCropped');
  String get saved => get('saved');
  String get processingFailed => get('processingFailed');
  String get rotateFailed => get('rotateFailed');
  String get cropFailed => get('cropFailed');
  String get saveError => get('saveError');
  String get shareError => get('shareError');
  String get enterText => get('enterText');
  String get enterTextHint => get('enterTextHint');
  String get add => get('add');
  String get textColor => get('textColor');
  String get backgroundColor => get('backgroundColor');

  // Onboarding getters
  String get onboardingWelcomeTitle => get('onboardingWelcomeTitle');
  String get onboardingWelcomeDesc => get('onboardingWelcomeDesc');
  String get onboardingBlurTitle => get('onboardingBlurTitle');
  String get onboardingBlurDesc => get('onboardingBlurDesc');
  String get onboardingTextStickerTitle => get('onboardingTextStickerTitle');
  String get onboardingTextStickerDesc => get('onboardingTextStickerDesc');
  String get onboardingSaveShareTitle => get('onboardingSaveShareTitle');
  String get onboardingSaveShareDesc => get('onboardingSaveShareDesc');
  String get skip => get('skip');
  String get next => get('next');
  String get getStarted => get('getStarted');

  // Color getters
  String get black => get('black');
  String get yellow => get('yellow');
  String get green => get('green');
  String get pink => get('pink');
  String get cyan => get('cyan');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ko'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
