import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// 테마 모드 관리
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

// 최근 편집 이미지 관리
class RecentImages {
  static const String _key = 'recent_images';
  static const int _maxImages = 20;

  static Future<List<String>> getRecentImages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> addImage(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final images = prefs.getStringList(_key) ?? [];
    images.remove(path);
    images.insert(0, path);
    if (images.length > _maxImages) {
      images.removeRange(_maxImages, images.length);
    }
    await prefs.setStringList(_key, images);
  }

  static Future<void> removeImage(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final images = prefs.getStringList(_key) ?? [];
    images.remove(path);
    await prefs.setStringList(_key, images);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CoverApp());
}

class CoverApp extends StatelessWidget {
  const CoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          title: 'Cover',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2196F3),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.black,
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

// ==================== Home Screen ====================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  List<String> _recentImages = [];

  @override
  void initState() {
    super.initState();
    _loadRecentImages();
  }

  Future<void> _loadRecentImages() async {
    final images = await RecentImages.getRecentImages();
    // 존재하는 파일만 필터링
    final existingImages = <String>[];
    for (final path in images) {
      if (await File(path).exists()) {
        existingImages.add(path);
      }
    }
    if (mounted) {
      setState(() => _recentImages = existingImages);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(imageFile: File(image.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지를 불러올 수 없습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromCamera() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 100,
      );

      if (image != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(imageFile: File(image.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('카메라를 사용할 수 없습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openRecentImage(String path) async {
    final file = File(path);
    if (await file.exists()) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditorScreen(imageFile: file),
          ),
        ).then((_) => _loadRecentImages());
      }
    } else {
      await RecentImages.removeImage(path);
      _loadRecentImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 찾을 수 없습니다')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // 설정 버튼
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: Icon(Icons.settings_outlined, color: subtitleColor),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                },
              ),
            ),
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      'Cover',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '개인정보를 안전하게',
                      style: TextStyle(
                        fontSize: 16,
                        color: subtitleColor,
                      ),
                    ),
                    const SizedBox(height: 48),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickFromGallery,
                        icon: const Icon(Icons.photo_library_rounded),
                        label: const Text('갤러리', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _pickFromCamera,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: const Text('카메라', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: subtitleColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const BatchScreen()),
                          );
                        },
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('배치 처리', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textColor,
                          side: BorderSide(color: subtitleColor),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),

                    // 최근 편집 이미지
                    if (_recentImages.isNotEmpty) ...[
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '최근 이미지',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.remove('recent_images');
                              _loadRecentImages();
                            },
                            child: Text(
                              '모두 지우기',
                              style: TextStyle(color: subtitleColor, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _recentImages.length,
                          itemBuilder: (context, index) {
                            final path = _recentImages[index];
                            return Padding(
                              padding: EdgeInsets.only(
                                right: index < _recentImages.length - 1 ? 12 : 0,
                              ),
                              child: GestureDetector(
                                onTap: () => _openRecentImage(path),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 120,
                                    height: 120,
                                    child: Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey[800],
                                          child: const Icon(Icons.broken_image, color: Colors.white38),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator(color: Color(0xFF2196F3))),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== Editor Screen ====================

enum EditTool { blur, mosaic, eraser, blackBar, highlighter, sticker, text }

enum DrawMode { brush, rectangle, circle }

// 텍스트 오버레이 데이터 모델
class TextOverlayData {
  String text;
  Offset position; // 정규화된 좌표 (0.0 ~ 1.0)
  double scale;
  double rotation;
  Color color;
  Color backgroundColor;
  bool hasBackground;
  String fontStyle; // 'normal', 'bold', 'italic'

  TextOverlayData({
    required this.text,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.color = Colors.white,
    this.backgroundColor = Colors.black,
    this.hasBackground = true,
    this.fontStyle = 'bold',
  });
}

// 스티커 데이터 모델
class StickerData {
  String content; // 이모지 또는 텍스트
  Offset position;
  double scale;
  double rotation;
  bool isEmoji;

  StickerData({
    required this.content,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.isEmoji = true,
  });

  StickerData copyWith({
    String? content,
    Offset? position,
    double? scale,
    double? rotation,
    bool? isEmoji,
  }) {
    return StickerData(
      content: content ?? this.content,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      isEmoji: isEmoji ?? this.isEmoji,
    );
  }
}

// 스티커 프리셋
class StickerPresets {
  static const List<String> emojis = [
    '😊', '😎', '🙈', '😴', '🤫', '🫣',
    '❤️', '⭐', '✨', '🔥', '💯', '👍',
    '🚫', '⛔', '🔒', '👀', '💬', '📍',
  ];

  static const List<String> shapes = [
    '⬛', '⬜', '🔴', '🟡', '🟢', '🔵',
    '◼️', '◻️', '●', '○', '★', '♥️',
  ];

  static const List<String> labels = [
    'PRIVATE',
    'CENSORED',
    'BLOCKED',
    'NO PHOTO',
    '비공개',
    '모자이크',
  ];
}

// 브러시 프리셋
enum BrushPreset { small, medium, large }

// 이미지 품질 프리셋
enum ImageQuality { low, medium, high, original }

extension ImageQualitySettings on ImageQuality {
  int get jpegQuality {
    switch (this) {
      case ImageQuality.low:
        return 60;
      case ImageQuality.medium:
        return 80;
      case ImageQuality.high:
        return 90;
      case ImageQuality.original:
        return 100;
    }
  }

  String get label {
    switch (this) {
      case ImageQuality.low:
        return '낮음';
      case ImageQuality.medium:
        return '중간';
      case ImageQuality.high:
        return '높음';
      case ImageQuality.original:
        return '원본';
    }
  }

  String get description {
    switch (this) {
      case ImageQuality.low:
        return '60% • 파일 크기 최소';
      case ImageQuality.medium:
        return '80% • 균형잡힌 품질';
      case ImageQuality.high:
        return '90% • 고품질';
      case ImageQuality.original:
        return '100% • 최고 품질';
    }
  }
}

extension BrushPresetSize on BrushPreset {
  double get size {
    switch (this) {
      case BrushPreset.small:
        return 25.0;
      case BrushPreset.medium:
        return 50.0;
      case BrushPreset.large:
        return 80.0;
    }
  }

  String get label {
    switch (this) {
      case BrushPreset.small:
        return 'S';
      case BrushPreset.medium:
        return 'M';
      case BrushPreset.large:
        return 'L';
    }
  }
}

class EditorScreen extends StatefulWidget {
  final File imageFile;
  const EditorScreen({super.key, required this.imageFile});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // 이미지 데이터
  Uint8List? _originalBytes;
  Uint8List? _currentBytes;
  ui.Image? _displayImage;
  ui.Image? _originalDisplayImage; // 원본 이미지 캐시

  // 비교 모드
  bool _showingOriginal = false;

  // 편집 상태
  EditTool _currentTool = EditTool.blur;
  DrawMode _drawMode = DrawMode.brush;
  double _brushSize = 40.0;
  double _intensity = 0.5;
  bool _isProcessing = false;
  Color _highlighterColor = Colors.yellow;

  // 현재 스트로크
  List<Offset> _currentStroke = [];

  // 도형 그리기용
  Offset? _shapeStart;
  Offset? _shapeEnd;

  // 핀치 줌
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;

  // 이미지 회전
  int _rotation = 0; // 0, 90, 180, 270

  // Undo/Redo 스택
  final List<Uint8List> _undoStack = [];
  final List<Uint8List> _redoStack = [];

  // 스티커
  final List<StickerData> _stickers = [];
  int? _selectedStickerIndex;
  Offset? _stickerDragStart;
  double _initialStickerScale = 1.0;

  // 텍스트 오버레이 관련
  final List<TextOverlayData> _textOverlays = [];
  int? _selectedTextIndex;
  double _initialTextScale = 1.0;
  Color _currentTextColor = Colors.white;
  Color _currentTextBgColor = Colors.black;
  bool _textHasBackground = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() => _isProcessing = true);

    try {
      final bytes = await widget.imageFile.readAsBytes();

      // 이미지 리사이즈 (최대 1500px)
      final resizedBytes = await compute(_resizeImage, bytes);

      _originalBytes = resizedBytes;
      _currentBytes = resizedBytes;

      await _updateDisplayImage(resizedBytes);

      // 원본 이미지 캐시
      final codec = await ui.instantiateImageCodec(resizedBytes);
      final frame = await codec.getNextFrame();
      _originalDisplayImage = frame.image;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 로드 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  static Uint8List _resizeImage(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;

    const maxSize = 1500;
    if (image.width <= maxSize && image.height <= maxSize) {
      return bytes;
    }

    final resized = img.copyResize(
      image,
      width: image.width > image.height ? maxSize : null,
      height: image.height >= image.width ? maxSize : null,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
  }

  Future<void> _updateDisplayImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (mounted) {
      setState(() => _displayImage = frame.image);
    }
  }

  void _onPanStart(DragStartDetails details, Size canvasSize) {
    if (_isProcessing || _displayImage == null) return;

    final imagePoint = _canvasToImage(details.localPosition, canvasSize);
    if (imagePoint != null) {
      setState(() {
        if (_drawMode == DrawMode.brush) {
          _currentStroke = [imagePoint];
        } else {
          _shapeStart = imagePoint;
          _shapeEnd = imagePoint;
        }
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_isProcessing || _displayImage == null) return;

    final imagePoint = _canvasToImage(details.localPosition, canvasSize);
    if (imagePoint != null) {
      setState(() {
        if (_drawMode == DrawMode.brush) {
          _currentStroke.add(imagePoint);
        } else {
          _shapeEnd = imagePoint;
        }
      });
    }
  }

  void _onPanEnd(DragEndDetails details) async {
    if (_drawMode == DrawMode.brush && _currentStroke.isEmpty) return;
    if (_drawMode != DrawMode.brush && (_shapeStart == null || _shapeEnd == null)) return;
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // Undo 스택에 현재 상태 저장
      _undoStack.add(_currentBytes!);
      _redoStack.clear();
      if (_undoStack.length > 10) _undoStack.removeAt(0);

      // 처리 요청 생성
      final request = ProcessRequest(
        imageBytes: _currentBytes!,
        points: _drawMode == DrawMode.brush
            ? _currentStroke.map((p) => [p.dx, p.dy]).toList()
            : [],
        brushSize: _brushSize,
        intensity: _intensity,
        tool: _currentTool,
        originalBytes: _originalBytes!,
        drawMode: _drawMode,
        shapeStart: _shapeStart != null ? [_shapeStart!.dx, _shapeStart!.dy] : null,
        shapeEnd: _shapeEnd != null ? [_shapeEnd!.dx, _shapeEnd!.dy] : null,
        highlighterColor: _highlighterColor.toARGB32(),
      );

      final processedBytes = await compute(_processImage, request);

      _currentBytes = processedBytes;
      await _updateDisplayImage(processedBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _currentStroke = [];
          _shapeStart = null;
          _shapeEnd = null;
          _isProcessing = false;
        });
      }
    }
  }

  void _rotateImage() async {
    if (_currentBytes == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      _undoStack.add(_currentBytes!);
      _redoStack.clear();
      if (_undoStack.length > 10) _undoStack.removeAt(0);

      final rotatedBytes = await compute(_rotateImageBytes, _currentBytes!);
      _currentBytes = rotatedBytes;

      // 원본도 회전 (지우개가 올바르게 동작하도록)
      _originalBytes = await compute(_rotateImageBytes, _originalBytes!);

      await _updateDisplayImage(rotatedBytes);

      setState(() => _rotation = (_rotation + 90) % 360);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('회전 실패: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Future<void> _cropImage() async {
    if (_currentBytes == null || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      // 현재 이미지를 임시 파일로 저장
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/crop_temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(_currentBytes!);

      // image_cropper 실행
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: tempFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '이미지 자르기',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: const Color(0xFF2196F3),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio3x2,
            ],
          ),
          IOSUiSettings(
            title: '이미지 자르기',
            cancelButtonTitle: '취소',
            doneButtonTitle: '완료',
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio3x2,
            ],
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: true,
          ),
        ],
      );

      // 임시 파일 삭제
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      if (croppedFile != null) {
        // Undo 스택에 현재 상태 저장
        _undoStack.add(_currentBytes!);
        _redoStack.clear();
        if (_undoStack.length > 10) _undoStack.removeAt(0);

        // 자른 이미지 로드
        final croppedBytes = await File(croppedFile.path).readAsBytes();

        // 원본도 업데이트 (지우개가 올바르게 동작하도록)
        _originalBytes = croppedBytes;
        _currentBytes = croppedBytes;

        await _updateDisplayImage(croppedBytes);

        // 자른 파일 삭제
        if (await File(croppedFile.path).exists()) {
          await File(croppedFile.path).delete();
        }

        // 줌 리셋
        _resetZoom();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미지가 잘렸습니다'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자르기 실패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Offset? _canvasToImage(Offset canvasPoint, Size canvasSize) {
    if (_displayImage == null) return null;

    final imageSize = Size(_displayImage!.width.toDouble(), _displayImage!.height.toDouble());
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, canvasSize);

    final offsetX = (canvasSize.width - fittedSize.destination.width) / 2;
    final offsetY = (canvasSize.height - fittedSize.destination.height) / 2;

    final relativeX = (canvasPoint.dx - offsetX) / fittedSize.destination.width;
    final relativeY = (canvasPoint.dy - offsetY) / fittedSize.destination.height;

    if (relativeX < 0 || relativeX > 1 || relativeY < 0 || relativeY > 1) {
      return null;
    }

    return Offset(
      relativeX * imageSize.width,
      relativeY * imageSize.height,
    );
  }

  void _undo() {
    if (_undoStack.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);

    _redoStack.add(_currentBytes!);
    _currentBytes = _undoStack.removeLast();

    _updateDisplayImage(_currentBytes!).then((_) {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);

    _undoStack.add(_currentBytes!);
    _currentBytes = _redoStack.removeLast();

    _updateDisplayImage(_currentBytes!).then((_) {
      if (mounted) setState(() => _isProcessing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('편집', style: TextStyle(color: Colors.white)),
        actions: [
          // 자르기 버튼
          IconButton(
            icon: const Icon(Icons.crop, color: Colors.white),
            onPressed: _cropImage,
            tooltip: '자르기',
          ),
          // 회전 버튼
          IconButton(
            icon: const Icon(Icons.rotate_right, color: Colors.white),
            onPressed: _rotateImage,
            tooltip: '회전',
          ),
          // 줌 리셋
          if (_scale != 1.0)
            IconButton(
              icon: const Icon(Icons.fit_screen, color: Colors.white),
              onPressed: _resetZoom,
              tooltip: '원래 크기',
            ),
          IconButton(
            icon: Icon(Icons.undo, color: _undoStack.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _undoStack.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: Icon(Icons.redo, color: _redoStack.isNotEmpty ? Colors.white : Colors.white38),
            onPressed: _redoStack.isNotEmpty ? _redo : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // 캔버스 영역
          Expanded(
            child: _displayImage == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                      return Stack(
                        children: [
                          GestureDetector(
                            onScaleStart: (details) {
                              _previousScale = _scale;
                              _previousOffset = _offset;
                              if (details.pointerCount == 1) {
                                _onPanStart(DragStartDetails(localPosition: details.localFocalPoint), canvasSize);
                              }
                            },
                            onScaleUpdate: (details) {
                              if (details.pointerCount == 2) {
                                // 핀치 줌
                                setState(() {
                                  _scale = (_previousScale * details.scale).clamp(0.5, 4.0);
                                  _offset = details.localFocalPoint - (_previousOffset + details.localFocalPoint) * details.scale + _previousOffset;
                                });
                              } else if (details.pointerCount == 1) {
                                _onPanUpdate(DragUpdateDetails(
                                  localPosition: details.localFocalPoint,
                                  globalPosition: details.focalPoint,
                                  delta: details.focalPointDelta,
                                ), canvasSize);
                              }
                            },
                            onScaleEnd: (details) {
                              if (details.pointerCount <= 1) {
                                _onPanEnd(DragEndDetails());
                              }
                            },
                            onLongPressStart: (_) {
                              if (_originalDisplayImage != null) {
                                setState(() => _showingOriginal = true);
                              }
                            },
                            onLongPressEnd: (_) {
                              setState(() => _showingOriginal = false);
                            },
                            child: ClipRect(
                              child: Transform(
                                transform: Matrix4.identity()
                                  ..translate(_offset.dx, _offset.dy)
                                  ..scale(_scale),
                                child: CustomPaint(
                                  size: canvasSize,
                                  painter: ImageCanvasPainter(
                                    image: _showingOriginal && _originalDisplayImage != null
                                        ? _originalDisplayImage!
                                        : _displayImage!,
                                    currentStroke: _showingOriginal ? [] : _currentStroke,
                                    brushSize: _brushSize,
                                    tool: _currentTool,
                                    drawMode: _drawMode,
                                    shapeStart: _showingOriginal ? null : _shapeStart,
                                    shapeEnd: _showingOriginal ? null : _shapeEnd,
                                    highlighterColor: _highlighterColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 원본 표시 중 오버레이
                          if (_showingOriginal)
                            Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.visibility, color: Colors.white, size: 18),
                                      SizedBox(width: 8),
                                      Text('원본', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // 스티커 렌더링
                          if (!_showingOriginal)
                            ..._buildStickerWidgets(canvasSize),
                          // 텍스트 렌더링
                          if (!_showingOriginal)
                            ..._buildTextWidgets(canvasSize),
                        ],
                      );
                    },
                  ),
          ),

          // 로딩 표시
          if (_isProcessing)
            const LinearProgressIndicator(color: Color(0xFF2196F3)),

          // 하단 컨트롤 (고정 컴팩트 UI)
          Container(
            color: const Color(0xFF1A1A1A),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. 도구 선택 - 그리드
                    Column(
                      children: [
                        // 1행: 블러, 모자이크, 검은바, 형광펜
                        Row(
                          children: [
                            Expanded(child: _buildGridToolChip(EditTool.blur, Icons.blur_on, '블러')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.mosaic, Icons.grid_view, '모자이크')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.blackBar, Icons.rectangle, '검은바')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.highlighter, Icons.highlight, '형광펜')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 2행: 지우개, 스티커, 텍스트
                        Row(
                          children: [
                            Expanded(child: _buildGridToolChip(EditTool.eraser, Icons.auto_fix_high, '지우개')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.sticker, Icons.emoji_emotions, '스티커')),
                            const SizedBox(width: 6),
                            Expanded(child: _buildGridToolChip(EditTool.text, Icons.text_fields, '텍스트')),
                            const SizedBox(width: 6),
                            // 빈 공간
                            const Expanded(child: SizedBox()),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // 2. 옵션 영역 - 고정 높이로 레이아웃 유지
                    SizedBox(
                      height: 130,
                      child: _currentTool == EditTool.sticker
                          ? _buildStickerControls()
                          : _currentTool == EditTool.text
                              ? _buildTextControls()
                              : Column(
                              children: [
                                // 모드 선택
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text('모드 ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                    const SizedBox(width: 8),
                                    _buildCompactModeChip(DrawMode.brush, Icons.brush),
                                    _buildCompactModeChip(DrawMode.rectangle, Icons.crop_square),
                                    _buildCompactModeChip(DrawMode.circle, Icons.circle_outlined),
                                    // 색상 선택 (형광펜일 때만)
                                    if (_currentTool == EditTool.highlighter) ...[
                                      const SizedBox(width: 12),
                                      Container(width: 1, height: 24, color: Colors.white24),
                                      const SizedBox(width: 12),
                                      _buildColorChip(Colors.yellow, '노랑'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.greenAccent, '초록'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.pinkAccent, '분홍'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.cyanAccent, '하늘'),
                                      const SizedBox(width: 4),
                                      _buildColorChip(Colors.orangeAccent, '주황'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // 크기 슬라이더
                                _buildSliderRow(
                                  label: '크기',
                                  value: _brushSize,
                                  min: 10,
                                  max: 120,
                                  displayValue: '${_brushSize.toInt()}',
                                  onChanged: (v) => setState(() => _brushSize = v),
                                  presets: true,
                                ),
                                const SizedBox(height: 6),
                                // 강도 슬라이더
                                _buildSliderRow(
                                  label: '강도',
                                  value: _intensity,
                                  min: 0.1,
                                  max: 1.0,
                                  displayValue: '${(_intensity * 100).toInt()}%',
                                  onChanged: (v) => setState(() => _intensity = v),
                                  enabled: _currentTool != EditTool.eraser && _currentTool != EditTool.blackBar,
                                ),
                              ],
                            ),
                    ),

                    const SizedBox(height: 12),

                    // 3. 저장/공유 버튼
                    SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isProcessing ? null : _showSaveOptionsDialog,
                              icon: const Icon(Icons.save_alt, size: 18),
                              label: const Text('저장', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2196F3),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isProcessing ? null : _shareImage,
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('공유', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridToolChip(EditTool tool, IconData icon, String label) {
    final isSelected = _currentTool == tool;
    return GestureDetector(
      onTap: () {
        setState(() => _currentTool = tool);
        if (tool == EditTool.sticker) {
          _showStickerPicker();
        } else if (tool == EditTool.text) {
          _showTextInputDialog();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white70,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactModeChip(DrawMode mode, IconData icon) {
    final isSelected = _drawMode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _drawMode = mode),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 18),
        ),
      ),
    );
  }

  // 스티커 선택 바텀시트
  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.5,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 탭
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      indicatorColor: Color(0xFF2196F3),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(text: '이모지'),
                        Tab(text: '도형'),
                        Tab(text: '텍스트'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // 이모지 탭
                          _buildStickerGrid(StickerPresets.emojis, true),
                          // 도형 탭
                          _buildStickerGrid(StickerPresets.shapes, true),
                          // 텍스트 탭
                          _buildLabelGrid(StickerPresets.labels),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickerGrid(List<String> items, bool isEmoji) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            _addSticker(items[index], isEmoji);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                items[index],
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLabelGrid(List<String> labels) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.5,
      ),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            _addSticker(labels[index], false);
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Center(
              child: Text(
                labels[index],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _addSticker(String content, bool isEmoji) {
    // 이미지 중앙에 스티커 추가
    if (_displayImage == null) return;

    setState(() {
      _stickers.add(StickerData(
        content: content,
        position: const Offset(0.5, 0.5), // 정규화된 좌표 (0~1)
        scale: 1.0,
        isEmoji: isEmoji,
      ));
      _selectedStickerIndex = _stickers.length - 1;
    });
  }

  Widget _buildStickerControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          // 스티커 추가 버튼
          Expanded(
            child: GestureDetector(
              onTap: _showStickerPicker,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text('스티커 추가', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          if (_stickers.isNotEmpty) ...[
            const SizedBox(width: 10),
            // 선택된 스티커 삭제 버튼
            GestureDetector(
              onTap: _selectedStickerIndex != null ? _deleteSelectedSticker : null,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _selectedStickerIndex != null
                      ? Colors.red.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.delete_outline,
                  color: _selectedStickerIndex != null ? Colors.white : Colors.white38,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 모든 스티커 삭제 버튼
            GestureDetector(
              onTap: _clearAllStickers,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.clear_all, color: Colors.white70, size: 20),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _deleteSelectedSticker() {
    if (_selectedStickerIndex != null && _selectedStickerIndex! < _stickers.length) {
      setState(() {
        _stickers.removeAt(_selectedStickerIndex!);
        _selectedStickerIndex = _stickers.isEmpty ? null : (_stickers.length - 1);
      });
    }
  }

  void _clearAllStickers() {
    setState(() {
      _stickers.clear();
      _selectedStickerIndex = null;
    });
  }

  // ========== 텍스트 오버레이 관련 ==========

  Widget _buildTextControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // 텍스트 추가 버튼
              Expanded(
                child: GestureDetector(
                  onTap: _showTextInputDialog,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text('텍스트 추가', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              if (_textOverlays.isNotEmpty) ...[
                const SizedBox(width: 10),
                // 선택된 텍스트 삭제 버튼
                GestureDetector(
                  onTap: _selectedTextIndex != null ? _deleteSelectedText : null,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _selectedTextIndex != null
                          ? Colors.red.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: _selectedTextIndex != null ? Colors.white : Colors.white38,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // 모든 텍스트 삭제 버튼
                GestureDetector(
                  onTap: _clearAllTexts,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.clear_all, color: Colors.white70, size: 20),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // 색상 선택
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('글자 ', style: TextStyle(color: Colors.white54, fontSize: 11)),
              _buildTextColorChip(Colors.white, true),
              _buildTextColorChip(Colors.black, true),
              _buildTextColorChip(Colors.red, true),
              _buildTextColorChip(Colors.yellow, true),
              const SizedBox(width: 12),
              const Text('배경 ', style: TextStyle(color: Colors.white54, fontSize: 11)),
              _buildTextColorChip(Colors.black, false),
              _buildTextColorChip(Colors.white, false),
              _buildTextColorChip(Colors.transparent, false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextColorChip(Color color, bool isTextColor) {
    final isSelected = isTextColor
        ? _currentTextColor == color
        : (color == Colors.transparent ? !_textHasBackground : _currentTextBgColor == color && _textHasBackground);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isTextColor) {
            _currentTextColor = color;
          } else {
            if (color == Colors.transparent) {
              _textHasBackground = false;
            } else {
              _textHasBackground = true;
              _currentTextBgColor = color;
            }
          }
          // 선택된 텍스트가 있으면 바로 적용
          if (_selectedTextIndex != null && _selectedTextIndex! < _textOverlays.length) {
            if (isTextColor) {
              _textOverlays[_selectedTextIndex!].color = color;
            } else {
              _textOverlays[_selectedTextIndex!].hasBackground = color != Colors.transparent;
              if (color != Colors.transparent) {
                _textOverlays[_selectedTextIndex!].backgroundColor = color;
              }
            }
          }
        });
      },
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: color == Colors.transparent ? null : color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF2196F3) : Colors.white38,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: color == Colors.transparent
            ? const Icon(Icons.not_interested, size: 16, color: Colors.white54)
            : null,
      ),
    );
  }

  void _showTextInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('텍스트 입력'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '텍스트를 입력하세요',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _addTextOverlay(controller.text);
              }
              Navigator.pop(context);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }

  void _addTextOverlay(String text) {
    setState(() {
      _textOverlays.add(TextOverlayData(
        text: text,
        position: const Offset(0.5, 0.5),
        color: _currentTextColor,
        backgroundColor: _currentTextBgColor,
        hasBackground: _textHasBackground,
      ));
      _selectedTextIndex = _textOverlays.length - 1;
    });
  }

  void _deleteSelectedText() {
    if (_selectedTextIndex != null && _selectedTextIndex! < _textOverlays.length) {
      setState(() {
        _textOverlays.removeAt(_selectedTextIndex!);
        _selectedTextIndex = _textOverlays.isEmpty ? null : (_textOverlays.length - 1);
      });
    }
  }

  void _clearAllTexts() {
    setState(() {
      _textOverlays.clear();
      _selectedTextIndex = null;
    });
  }

  List<Widget> _buildTextWidgets(Size canvasSize) {
    if (_displayImage == null) return [];

    final imageAspect = _displayImage!.width / _displayImage!.height;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double imageWidth, imageHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspect > canvasAspect) {
      imageWidth = canvasSize.width;
      imageHeight = canvasSize.width / imageAspect;
      offsetY = (canvasSize.height - imageHeight) / 2;
    } else {
      imageHeight = canvasSize.height;
      imageWidth = canvasSize.height * imageAspect;
      offsetX = (canvasSize.width - imageWidth) / 2;
    }

    return _textOverlays.asMap().entries.map((entry) {
      final index = entry.key;
      final textData = entry.value;
      final isSelected = _selectedTextIndex == index;

      final baseSize = 16.0 * textData.scale;
      final x = offsetX + textData.position.dx * imageWidth;
      final y = offsetY + textData.position.dy * imageHeight;

      return Positioned(
        left: x * _scale + _offset.dx,
        top: y * _scale + _offset.dy,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedTextIndex = index);
          },
          onScaleStart: (details) {
            setState(() => _selectedTextIndex = index);
            _initialTextScale = textData.scale;
          },
          onScaleUpdate: (details) {
            if (_selectedTextIndex == index) {
              setState(() {
                final dx = details.focalPointDelta.dx / (imageWidth * _scale);
                final dy = details.focalPointDelta.dy / (imageHeight * _scale);
                textData.position = Offset(
                  (textData.position.dx + dx).clamp(0.0, 1.0),
                  (textData.position.dy + dy).clamp(0.0, 1.0),
                );
                if (details.scale != 1.0) {
                  textData.scale = (_initialTextScale * details.scale).clamp(0.5, 4.0);
                }
              });
            }
          },
          child: Transform.scale(
            scale: _scale,
            child: Container(
              padding: textData.hasBackground
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: textData.hasBackground ? textData.backgroundColor : null,
                borderRadius: BorderRadius.circular(4),
                border: isSelected
                    ? Border.all(color: const Color(0xFF2196F3), width: 2)
                    : null,
              ),
              child: Text(
                textData.text,
                style: TextStyle(
                  color: textData.color,
                  fontSize: baseSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildStickerWidgets(Size canvasSize) {
    if (_displayImage == null) return [];

    // 이미지 영역 계산
    final imageAspect = _displayImage!.width / _displayImage!.height;
    final canvasAspect = canvasSize.width / canvasSize.height;

    double imageWidth, imageHeight;
    double offsetX = 0, offsetY = 0;

    if (imageAspect > canvasAspect) {
      imageWidth = canvasSize.width;
      imageHeight = canvasSize.width / imageAspect;
      offsetY = (canvasSize.height - imageHeight) / 2;
    } else {
      imageHeight = canvasSize.height;
      imageWidth = canvasSize.height * imageAspect;
      offsetX = (canvasSize.width - imageWidth) / 2;
    }

    return _stickers.asMap().entries.map((entry) {
      final index = entry.key;
      final sticker = entry.value;
      final isSelected = _selectedStickerIndex == index;

      // 스티커 기본 크기 (이모지 vs 텍스트)
      final baseSize = sticker.isEmoji ? 60.0 : 80.0;
      final stickerSize = baseSize * sticker.scale;

      // 정규화된 좌표를 실제 좌표로 변환
      final x = offsetX + sticker.position.dx * imageWidth - stickerSize / 2;
      final y = offsetY + sticker.position.dy * imageHeight - stickerSize / 2;

      return Positioned(
        left: x * _scale + _offset.dx,
        top: y * _scale + _offset.dy,
        child: GestureDetector(
          onTap: () {
            setState(() => _selectedStickerIndex = index);
          },
          onScaleStart: (details) {
            setState(() {
              _selectedStickerIndex = index;
              _stickerDragStart = sticker.position;
            });
            _initialStickerScale = sticker.scale;
          },
          onScaleUpdate: (details) {
            if (_selectedStickerIndex == index) {
              setState(() {
                // 드래그: focalPointDelta를 정규화된 좌표로 변환
                final dx = details.focalPointDelta.dx / (imageWidth * _scale);
                final dy = details.focalPointDelta.dy / (imageHeight * _scale);
                sticker.position = Offset(
                  (sticker.position.dx + dx).clamp(0.0, 1.0),
                  (sticker.position.dy + dy).clamp(0.0, 1.0),
                );
                // 스케일 (두 손가락 제스처)
                if (details.scale != 1.0) {
                  sticker.scale = (_initialStickerScale * details.scale).clamp(0.5, 3.0);
                }
              });
            }
          },
          child: Transform.scale(
            scale: _scale,
            child: Container(
              width: stickerSize,
              height: sticker.isEmoji ? stickerSize : stickerSize * 0.5,
              decoration: isSelected
                  ? BoxDecoration(
                      border: Border.all(color: const Color(0xFF2196F3), width: 2),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Center(
                child: sticker.isEmoji
                    ? Text(
                        sticker.content,
                        style: TextStyle(fontSize: stickerSize * 0.7),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sticker.content,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: stickerSize * 0.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String displayValue,
    required ValueChanged<double> onChanged,
    bool enabled = true,
    bool presets = false,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.3,
      child: IgnorePointer(
        ignoring: !enabled,
        child: SizedBox(
          height: 32,
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
              if (presets) ...[
                for (final preset in BrushPreset.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _buildPresetButton(preset),
                  ),
              ],
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    activeColor: const Color(0xFF2196F3),
                    inactiveColor: Colors.white24,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 36,
                child: Text(
                  displayValue,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorChip(Color color, String label) {
    final isSelected = _highlighterColor == color;
    return GestureDetector(
      onTap: () => setState(() => _highlighterColor = color),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildPresetButton(BrushPreset preset) {
    final isSelected = (_brushSize - preset.size).abs() < 5;
    return GestureDetector(
      onTap: () => setState(() => _brushSize = preset.size),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            preset.label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  void _showSaveOptionsDialog() {
    if (_currentBytes == null) return;

    // 예상 파일 크기 계산
    final originalSize = _currentBytes!.length;
    String estimateSize(ImageQuality quality) {
      final estimatedBytes = (originalSize * quality.jpegQuality / 100).round();
      if (estimatedBytes < 1024) {
        return '$estimatedBytes B';
      } else if (estimatedBytes < 1024 * 1024) {
        return '${(estimatedBytes / 1024).toStringAsFixed(1)} KB';
      } else {
        return '${(estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 타이틀
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.high_quality, color: Colors.white, size: 24),
                    SizedBox(width: 12),
                    Text(
                      '저장 품질 선택',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 품질 옵션
              ...ImageQuality.values.map((quality) => _buildQualityOption(
                    quality,
                    estimateSize(quality),
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityOption(ImageQuality quality, String estimatedSize) {
    final isRecommended = quality == ImageQuality.high;
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _saveImageWithQuality(quality);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isRecommended
                    ? const Color(0xFF2196F3).withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '${quality.jpegQuality}%',
                  style: TextStyle(
                    color: isRecommended ? const Color(0xFF2196F3) : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        quality.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '추천',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quality.description,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              '~$estimatedSize',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _saveImageWithQuality(ImageQuality quality) async {
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // 스티커가 있으면 합성
      Uint8List finalBytes = _currentBytes!;
      if (_stickers.isNotEmpty) {
        finalBytes = await compute(compositeStickers, CompositeRequest(
          imageBytes: finalBytes,
          stickers: _stickers.map((s) => StickerInfo(
            content: s.content,
            positionX: s.position.dx,
            positionY: s.position.dy,
            scale: s.scale,
            isEmoji: s.isEmoji,
          )).toList(),
        ));
      }

      // 텍스트 오버레이가 있으면 합성
      if (_textOverlays.isNotEmpty) {
        finalBytes = await compute(compositeTexts, TextCompositeRequest(
          imageBytes: finalBytes,
          texts: _textOverlays.map((t) => TextOverlayInfo(
            text: t.text,
            positionX: t.position.dx,
            positionY: t.position.dy,
            scale: t.scale,
            colorR: (t.color.r * 255.0).round().clamp(0, 255),
            colorG: (t.color.g * 255.0).round().clamp(0, 255),
            colorB: (t.color.b * 255.0).round().clamp(0, 255),
            bgColorR: (t.backgroundColor.r * 255.0).round().clamp(0, 255),
            bgColorG: (t.backgroundColor.g * 255.0).round().clamp(0, 255),
            bgColorB: (t.backgroundColor.b * 255.0).round().clamp(0, 255),
            hasBackground: t.hasBackground,
          )).toList(),
        ));
      }

      // 파일명 생성
      final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final fileName = 'Cover_$timestamp';

      // 갤러리에 저장
      final result = await ImageGallerySaver.saveImage(
        finalBytes,
        quality: quality.jpegQuality,
        name: fileName,
      );

      if (mounted) {
        if (result['isSuccess'] == true) {
          // 최근 이미지에 원본 경로 추가
          await RecentImages.addImage(widget.imageFile.path);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('${quality.label} 품질로 저장되었습니다'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('저장에 실패했습니다'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _shareImage() async {
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // 임시 파일 생성
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/Cover_$timestamp.jpg');
      await tempFile.writeAsBytes(_currentBytes!);

      // 공유
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Cover로 편집한 이미지',
      );

      // 임시 파일 삭제
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('공유 오류: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

// ==================== Image Processing ====================

// 스티커 합성을 위한 데이터 클래스
class StickerInfo {
  final String content;
  final double positionX;
  final double positionY;
  final double scale;
  final bool isEmoji;

  StickerInfo({
    required this.content,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.isEmoji,
  });
}

class CompositeRequest {
  final Uint8List imageBytes;
  final List<StickerInfo> stickers;

  CompositeRequest({
    required this.imageBytes,
    required this.stickers,
  });
}

// 스티커 합성 함수 (Isolate에서 실행)
Uint8List compositeStickers(CompositeRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  for (final sticker in request.stickers) {
    // 스티커 위치 계산 (정규화된 좌표 -> 실제 좌표)
    final x = (sticker.positionX * image.width).toInt();
    final y = (sticker.positionY * image.height).toInt();

    // 스티커 크기 계산
    final baseSize = sticker.isEmoji ? 60 : 80;
    final size = (baseSize * sticker.scale).toInt();

    if (sticker.isEmoji) {
      // 이모지: 검은색 원으로 가리기 (이모지는 이미지로 렌더링 어려움)
      final halfSize = size ~/ 2;
      for (int dy = -halfSize; dy < halfSize; dy++) {
        for (int dx = -halfSize; dx < halfSize; dx++) {
          if (dx * dx + dy * dy <= halfSize * halfSize) {
            final px = x + dx;
            final py = y + dy;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 255));
            }
          }
        }
      }
    } else {
      // 텍스트 라벨: 검은색 사각형으로 가리기
      final halfWidth = size ~/ 2;
      final halfHeight = size ~/ 4;
      for (int dy = -halfHeight; dy < halfHeight; dy++) {
        for (int dx = -halfWidth; dx < halfWidth; dx++) {
          final px = x + dx;
          final py = y + dy;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

// 텍스트 오버레이 정보 클래스
class TextOverlayInfo {
  final String text;
  final double positionX;
  final double positionY;
  final double scale;
  final int colorR;
  final int colorG;
  final int colorB;
  final int bgColorR;
  final int bgColorG;
  final int bgColorB;
  final bool hasBackground;

  TextOverlayInfo({
    required this.text,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.colorR,
    required this.colorG,
    required this.colorB,
    required this.bgColorR,
    required this.bgColorG,
    required this.bgColorB,
    required this.hasBackground,
  });
}

class TextCompositeRequest {
  final Uint8List imageBytes;
  final List<TextOverlayInfo> texts;

  TextCompositeRequest({
    required this.imageBytes,
    required this.texts,
  });
}

// 텍스트 합성 함수 (Isolate에서 실행)
Uint8List compositeTexts(TextCompositeRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  for (final textInfo in request.texts) {
    // 텍스트 위치 계산 (정규화된 좌표 -> 실제 좌표)
    final x = (textInfo.positionX * image.width).toInt();
    final y = (textInfo.positionY * image.height).toInt();

    // 텍스트 크기 계산 (scale 기반)
    final baseWidth = (textInfo.text.length * 12 * textInfo.scale).toInt();
    final baseHeight = (24 * textInfo.scale).toInt();
    final padding = (4 * textInfo.scale).toInt();

    final halfWidth = baseWidth ~/ 2 + padding;
    final halfHeight = baseHeight ~/ 2 + padding;

    // 배경이 있으면 배경 사각형 그리기
    if (textInfo.hasBackground) {
      final bgColor = img.ColorRgba8(textInfo.bgColorR, textInfo.bgColorG, textInfo.bgColorB, 255);
      for (int dy = -halfHeight; dy < halfHeight; dy++) {
        for (int dx = -halfWidth; dx < halfWidth; dx++) {
          final px = x + dx;
          final py = y + dy;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, bgColor);
          }
        }
      }
    }

    // 텍스트 색상으로 테두리 표시 (텍스트 자체는 이미지로 렌더링 어려움)
    final textColor = img.ColorRgba8(textInfo.colorR, textInfo.colorG, textInfo.colorB, 255);
    final borderWidth = (2 * textInfo.scale).toInt().clamp(1, 4);

    // 상단 테두리
    for (int dy = -halfHeight; dy < -halfHeight + borderWidth; dy++) {
      for (int dx = -halfWidth; dx < halfWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
    // 하단 테두리
    for (int dy = halfHeight - borderWidth; dy < halfHeight; dy++) {
      for (int dx = -halfWidth; dx < halfWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
    // 좌측 테두리
    for (int dy = -halfHeight; dy < halfHeight; dy++) {
      for (int dx = -halfWidth; dx < -halfWidth + borderWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
    // 우측 테두리
    for (int dy = -halfHeight; dy < halfHeight; dy++) {
      for (int dx = halfWidth - borderWidth; dx < halfWidth; dx++) {
        final px = x + dx;
        final py = y + dy;
        if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
          image.setPixel(px, py, textColor);
        }
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

class ProcessRequest {
  final Uint8List imageBytes;
  final List<List<double>> points;
  final double brushSize;
  final double intensity;
  final EditTool tool;
  final Uint8List originalBytes;
  final DrawMode drawMode;
  final List<double>? shapeStart;
  final List<double>? shapeEnd;
  final int highlighterColor;

  ProcessRequest({
    required this.imageBytes,
    required this.points,
    required this.brushSize,
    required this.intensity,
    required this.tool,
    required this.originalBytes,
    this.drawMode = DrawMode.brush,
    this.shapeStart,
    this.shapeEnd,
    this.highlighterColor = 0xFFFFFF00,
  });
}

// 이미지 회전 함수
Uint8List _rotateImageBytes(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return bytes;

  final rotated = img.copyRotate(image, angle: 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
}

Uint8List _processImage(ProcessRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  final points = request.points.map((p) => Offset(p[0], p[1])).toList();
  final radius = (request.brushSize / 2).toInt();

  // 도형 모드인 경우
  if (request.drawMode != DrawMode.brush && request.shapeStart != null && request.shapeEnd != null) {
    final start = Offset(request.shapeStart![0], request.shapeStart![1]);
    final end = Offset(request.shapeEnd![0], request.shapeEnd![1]);

    switch (request.tool) {
      case EditTool.blur:
        _applyShapeBlur(image, start, end, request.drawMode, request.intensity);
        break;
      case EditTool.mosaic:
        _applyShapeMosaic(image, start, end, request.drawMode, request.intensity);
        break;
      case EditTool.blackBar:
        _applyShapeBlackBar(image, start, end, request.drawMode);
        break;
      case EditTool.eraser:
        final original = img.decodeImage(request.originalBytes);
        if (original != null) {
          _applyShapeEraser(image, original, start, end, request.drawMode);
        }
        break;
      case EditTool.highlighter:
        _applyShapeHighlighter(image, start, end, request.drawMode, request.highlighterColor, request.intensity);
        break;
      case EditTool.sticker:
      case EditTool.text:
        break; // 스티커/텍스트는 별도 레이어에서 처리
    }
  } else {
    // 브러시 모드
    switch (request.tool) {
      case EditTool.blur:
        _applyBlur(image, points, radius, request.intensity);
        break;
      case EditTool.mosaic:
        _applyMosaic(image, points, radius, request.intensity);
        break;
      case EditTool.blackBar:
        _applyBlackBar(image, points, radius);
        break;
      case EditTool.highlighter:
        _applyHighlighter(image, points, radius, request.highlighterColor, request.intensity);
        break;
      case EditTool.eraser:
        final original = img.decodeImage(request.originalBytes);
        if (original != null) {
          _applyEraser(image, original, points, radius);
        }
        break;
      case EditTool.sticker:
      case EditTool.text:
        break; // 스티커/텍스트는 별도 레이어에서 처리
    }
  }

  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void _applyBlur(img.Image image, List<Offset> points, int radius, double intensity) {
  final blurRadius = (intensity * 15).toInt().clamp(1, 20);

  // 영향받는 영역 계산
  int minX = image.width, minY = image.height, maxX = 0, maxY = 0;

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();
    minX = min(minX, cx - radius);
    minY = min(minY, cy - radius);
    maxX = max(maxX, cx + radius);
    maxY = max(maxY, cy + radius);
  }

  minX = minX.clamp(0, image.width - 1);
  minY = minY.clamp(0, image.height - 1);
  maxX = maxX.clamp(0, image.width - 1);
  maxY = maxY.clamp(0, image.height - 1);

  // 마스크 생성
  final mask = List.generate(
    maxY - minY + 1,
    (_) => List.filled(maxX - minX + 1, false),
  );

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < minX || x > maxX || y < minY || y > maxY) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          mask[y - minY][x - minX] = true;
        }
      }
    }
  }

  // 블러 적용
  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (!mask[y - minY][x - minX]) continue;

      int r = 0, g = 0, b = 0, count = 0;

      for (int ky = -blurRadius; ky <= blurRadius; ky++) {
        for (int kx = -blurRadius; kx <= blurRadius; kx++) {
          final nx = (x + kx).clamp(0, image.width - 1);
          final ny = (y + ky).clamp(0, image.height - 1);

          final pixel = image.getPixel(nx, ny);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        image.setPixelRgba(x, y, r ~/ count, g ~/ count, b ~/ count, 255);
      }
    }
  }
}

void _applyMosaic(img.Image image, List<Offset> points, int radius, double intensity) {
  final blockSize = (intensity * 20).toInt().clamp(4, 30);

  // 영향받는 픽셀 수집
  final affectedPixels = <String, bool>{};

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          // 블록 단위로 그룹화
          final bx = (x ~/ blockSize) * blockSize;
          final by = (y ~/ blockSize) * blockSize;
          affectedPixels['$bx,$by'] = true;
        }
      }
    }
  }

  // 각 블록에 모자이크 적용
  for (final key in affectedPixels.keys) {
    final parts = key.split(',');
    final bx = int.parse(parts[0]);
    final by = int.parse(parts[1]);

    int r = 0, g = 0, b = 0, count = 0;

    // 블록 평균 색상 계산
    for (int y = by; y < by + blockSize && y < image.height; y++) {
      for (int x = bx; x < bx + blockSize && x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        r += pixel.r.toInt();
        g += pixel.g.toInt();
        b += pixel.b.toInt();
        count++;
      }
    }

    if (count > 0) {
      final avgR = r ~/ count;
      final avgG = g ~/ count;
      final avgB = b ~/ count;

      // 블록에 평균 색상 적용
      for (int y = by; y < by + blockSize && y < image.height; y++) {
        for (int x = bx; x < bx + blockSize && x < image.width; x++) {
          image.setPixelRgba(x, y, avgR, avgG, avgB, 255);
        }
      }
    }
  }
}

void _applyEraser(img.Image image, img.Image original, List<Offset> points, int radius) {
  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          final originalPixel = original.getPixel(x, y);
          image.setPixel(x, y, originalPixel);
        }
      }
    }
  }
}

// 검은 바 적용 (브러시 모드)
void _applyBlackBar(img.Image image, List<Offset> points, int radius) {
  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          image.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }
  }
}

// 형광펜 적용 (브러시 모드)
void _applyHighlighter(img.Image image, List<Offset> points, int radius, int colorValue, double intensity) {
  final color = Color(colorValue);
  final alpha = (intensity * 0.5).clamp(0.2, 0.6);
  final colorR = (color.r * 255).round().clamp(0, 255);
  final colorG = (color.g * 255).round().clamp(0, 255);
  final colorB = (color.b * 255).round().clamp(0, 255);

  for (final point in points) {
    final cx = point.dx.toInt();
    final cy = point.dy.toInt();

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final x = cx + dx;
        final y = cy + dy;

        if (x < 0 || x >= image.width || y < 0 || y >= image.height) continue;

        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= radius) {
          final pixel = image.getPixel(x, y);
          final newR = ((pixel.r * (1 - alpha)) + (colorR * alpha)).toInt().clamp(0, 255);
          final newG = ((pixel.g * (1 - alpha)) + (colorG * alpha)).toInt().clamp(0, 255);
          final newB = ((pixel.b * (1 - alpha)) + (colorB * alpha)).toInt().clamp(0, 255);
          image.setPixelRgba(x, y, newR, newG, newB, 255);
        }
      }
    }
  }
}

// ==================== 도형 모드 함수들 ====================

bool _isInShape(int x, int y, Offset start, Offset end, DrawMode mode) {
  final minX = min(start.dx, end.dx).toInt();
  final maxX = max(start.dx, end.dx).toInt();
  final minY = min(start.dy, end.dy).toInt();
  final maxY = max(start.dy, end.dy).toInt();

  if (mode == DrawMode.rectangle) {
    return x >= minX && x <= maxX && y >= minY && y <= maxY;
  } else {
    // 원형 (타원)
    final centerX = (start.dx + end.dx) / 2;
    final centerY = (start.dy + end.dy) / 2;
    final radiusX = (end.dx - start.dx).abs() / 2;
    final radiusY = (end.dy - start.dy).abs() / 2;

    if (radiusX == 0 || radiusY == 0) return false;

    final dx = (x - centerX) / radiusX;
    final dy = (y - centerY) / radiusY;
    return (dx * dx + dy * dy) <= 1;
  }
}

void _applyShapeBlur(img.Image image, Offset start, Offset end, DrawMode mode, double intensity) {
  final blurRadius = (intensity * 15).toInt().clamp(1, 20);
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  // 영역 복사본 만들기
  final tempImage = img.Image.from(image);

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (!_isInShape(x, y, start, end, mode)) continue;

      int r = 0, g = 0, b = 0, count = 0;

      for (int ky = -blurRadius; ky <= blurRadius; ky++) {
        for (int kx = -blurRadius; kx <= blurRadius; kx++) {
          final nx = (x + kx).clamp(0, image.width - 1);
          final ny = (y + ky).clamp(0, image.height - 1);

          final pixel = tempImage.getPixel(nx, ny);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        image.setPixelRgba(x, y, r ~/ count, g ~/ count, b ~/ count, 255);
      }
    }
  }
}

void _applyShapeMosaic(img.Image image, Offset start, Offset end, DrawMode mode, double intensity) {
  final blockSize = (intensity * 20).toInt().clamp(4, 30);
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int by = minY; by <= maxY; by += blockSize) {
    for (int bx = minX; bx <= maxX; bx += blockSize) {
      int r = 0, g = 0, b = 0, count = 0;

      // 블록 평균 색상 계산
      for (int y = by; y < by + blockSize && y <= maxY; y++) {
        for (int x = bx; x < bx + blockSize && x <= maxX; x++) {
          if (!_isInShape(x, y, start, end, mode)) continue;
          final pixel = image.getPixel(x, y);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        final avgR = r ~/ count;
        final avgG = g ~/ count;
        final avgB = b ~/ count;

        for (int y = by; y < by + blockSize && y <= maxY; y++) {
          for (int x = bx; x < bx + blockSize && x <= maxX; x++) {
            if (!_isInShape(x, y, start, end, mode)) continue;
            image.setPixelRgba(x, y, avgR, avgG, avgB, 255);
          }
        }
      }
    }
  }
}

void _applyShapeBlackBar(img.Image image, Offset start, Offset end, DrawMode mode) {
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (_isInShape(x, y, start, end, mode)) {
        image.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
  }
}

void _applyShapeHighlighter(img.Image image, Offset start, Offset end, DrawMode mode, int colorValue, double intensity) {
  final color = Color(colorValue);
  final alpha = (intensity * 0.5).clamp(0.2, 0.6);
  final colorR = (color.r * 255).round().clamp(0, 255);
  final colorG = (color.g * 255).round().clamp(0, 255);
  final colorB = (color.b * 255).round().clamp(0, 255);
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (!_isInShape(x, y, start, end, mode)) continue;

      final pixel = image.getPixel(x, y);
      final newR = ((pixel.r * (1 - alpha)) + (colorR * alpha)).toInt().clamp(0, 255);
      final newG = ((pixel.g * (1 - alpha)) + (colorG * alpha)).toInt().clamp(0, 255);
      final newB = ((pixel.b * (1 - alpha)) + (colorB * alpha)).toInt().clamp(0, 255);
      image.setPixelRgba(x, y, newR, newG, newB, 255);
    }
  }
}

void _applyShapeEraser(img.Image image, img.Image original, Offset start, Offset end, DrawMode mode) {
  final minX = max(0, min(start.dx, end.dx).toInt());
  final maxX = min(image.width - 1, max(start.dx, end.dx).toInt());
  final minY = max(0, min(start.dy, end.dy).toInt());
  final maxY = min(image.height - 1, max(start.dy, end.dy).toInt());

  for (int y = minY; y <= maxY; y++) {
    for (int x = minX; x <= maxX; x++) {
      if (_isInShape(x, y, start, end, mode)) {
        final originalPixel = original.getPixel(x, y);
        image.setPixel(x, y, originalPixel);
      }
    }
  }
}

// ==================== Canvas Painter ====================

class ImageCanvasPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> currentStroke;
  final double brushSize;
  final EditTool tool;
  final DrawMode drawMode;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final Color highlighterColor;

  ImageCanvasPainter({
    required this.image,
    required this.currentStroke,
    required this.brushSize,
    required this.tool,
    required this.drawMode,
    this.shapeStart,
    this.shapeEnd,
    this.highlighterColor = Colors.yellow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 이미지 그리기
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fittedSize = applyBoxFit(BoxFit.contain, imageSize, size);

    final offsetX = (size.width - fittedSize.destination.width) / 2;
    final offsetY = (size.height - fittedSize.destination.height) / 2;

    final destRect = Rect.fromLTWH(
      offsetX,
      offsetY,
      fittedSize.destination.width,
      fittedSize.destination.height,
    );

    final srcRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);

    canvas.drawImageRect(image, srcRect, destRect, Paint());

    final scaleX = fittedSize.destination.width / imageSize.width;
    final scaleY = fittedSize.destination.height / imageSize.height;

    // 도형 미리보기
    if (drawMode != DrawMode.brush && shapeStart != null && shapeEnd != null) {
      final startX = offsetX + shapeStart!.dx * scaleX;
      final startY = offsetY + shapeStart!.dy * scaleY;
      final endX = offsetX + shapeEnd!.dx * scaleX;
      final endY = offsetY + shapeEnd!.dy * scaleY;

      final shapePaint = Paint()
        ..color = _getStrokeColor()
        ..style = PaintingStyle.fill;

      if (drawMode == DrawMode.rectangle) {
        canvas.drawRect(
          Rect.fromPoints(Offset(startX, startY), Offset(endX, endY)),
          shapePaint,
        );
      } else {
        // 원형 (타원)
        final rect = Rect.fromPoints(Offset(startX, startY), Offset(endX, endY));
        canvas.drawOval(rect, shapePaint);
      }
    }

    // 브러시 스트로크 미리보기
    if (drawMode == DrawMode.brush && currentStroke.isNotEmpty) {
      final strokePaint = Paint()
        ..color = _getStrokeColor()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = brushSize * scaleX;

      final path = Path();
      for (int i = 0; i < currentStroke.length; i++) {
        final point = currentStroke[i];
        final canvasX = offsetX + point.dx * scaleX;
        final canvasY = offsetY + point.dy * scaleY;

        if (i == 0) {
          path.moveTo(canvasX, canvasY);
        } else {
          path.lineTo(canvasX, canvasY);
        }
      }

      canvas.drawPath(path, strokePaint);
    }
  }

  Color _getStrokeColor() {
    switch (tool) {
      case EditTool.blur:
        return Colors.blue.withValues(alpha: 0.4);
      case EditTool.mosaic:
        return Colors.purple.withValues(alpha: 0.4);
      case EditTool.eraser:
        return Colors.white.withValues(alpha: 0.4);
      case EditTool.blackBar:
        return Colors.black.withValues(alpha: 0.7);
      case EditTool.highlighter:
        return highlighterColor.withValues(alpha: 0.5);
      case EditTool.sticker:
      case EditTool.text:
        return Colors.transparent;
    }
  }

  @override
  bool shouldRepaint(covariant ImageCanvasPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.brushSize != brushSize ||
        oldDelegate.tool != tool ||
        oldDelegate.drawMode != drawMode ||
        oldDelegate.shapeStart != shapeStart ||
        oldDelegate.shapeEnd != shapeEnd ||
        oldDelegate.highlighterColor != highlighterColor;
  }
}

// ==================== Batch Screen ====================

enum BatchEffect { blur, mosaic, blackBar }

class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  final ImagePicker _picker = ImagePicker();
  List<File> _selectedImages = [];
  BatchEffect _selectedEffect = BatchEffect.blur;
  double _intensity = 0.5;
  bool _isProcessing = false;
  int _processedCount = 0;
  String _statusMessage = '';

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 100,
        limit: 10,
      );

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages = images.map((x) => File(x.path)).toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지를 선택할 수 없습니다: $e')),
        );
      }
    }
  }

  Future<void> _processAllImages() async {
    if (_selectedImages.isEmpty || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _processedCount = 0;
      _statusMessage = '처리 중...';
    });

    int successCount = 0;

    for (int i = 0; i < _selectedImages.length; i++) {
      setState(() {
        _statusMessage = '${i + 1}/${_selectedImages.length} 처리 중...';
      });

      try {
        final result = await compute(_applyBatchEffect, _BatchProcessRequest(
          imagePath: _selectedImages[i].path,
          effect: _selectedEffect,
          intensity: _intensity,
        ));

        if (result != null) {
          // 갤러리에 저장
          await ImageGallerySaver.saveImage(
            result,
            quality: 90,
            name: 'Cover_batch_${DateTime.now().millisecondsSinceEpoch}_$i',
          );
          successCount++;
        }
      } catch (e) {
        debugPrint('배치 처리 오류: $e');
      }

      setState(() {
        _processedCount = i + 1;
      });
    }

    setState(() {
      _isProcessing = false;
      _statusMessage = '';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$successCount개 이미지가 저장되었습니다'),
          backgroundColor: Colors.green,
        ),
      );

      if (successCount > 0) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('배치 처리'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // 이미지 선택 영역
          Expanded(
            child: _selectedImages.isEmpty
                ? _buildEmptyState()
                : _buildImageGrid(),
          ),

          // 하단 컨트롤
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 효과 선택
                    Row(
                      children: [
                        _buildEffectChip(BatchEffect.blur, '블러', Icons.blur_on),
                        const SizedBox(width: 8),
                        _buildEffectChip(BatchEffect.mosaic, '모자이크', Icons.grid_view),
                        const SizedBox(width: 8),
                        _buildEffectChip(BatchEffect.blackBar, '검은바', Icons.rectangle),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 강도 슬라이더
                    if (_selectedEffect != BatchEffect.blackBar)
                      Row(
                        children: [
                          const Text('강도', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Slider(
                              value: _intensity,
                              min: 0.1,
                              max: 1.0,
                              onChanged: (v) => setState(() => _intensity = v),
                            ),
                          ),
                          Text('${(_intensity * 100).toInt()}%',
                              style: const TextStyle(fontSize: 13)),
                        ],
                      ),

                    const SizedBox(height: 16),

                    // 진행 상태
                    if (_isProcessing) ...[
                      LinearProgressIndicator(
                        value: _selectedImages.isNotEmpty
                            ? _processedCount / _selectedImages.length
                            : 0,
                      ),
                      const SizedBox(height: 8),
                      Text(_statusMessage,
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 16),
                    ],

                    // 처리 버튼
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _selectedImages.isEmpty || _isProcessing
                            ? null
                            : _processAllImages,
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high),
                        label: Text(
                          _isProcessing
                              ? '처리 중...'
                              : '${_selectedImages.length}개 이미지 처리',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '이미지를 선택하세요',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '최대 10장까지 선택 가능',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.add_photo_alternate),
            label: const Text('갤러리에서 선택'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid() {
    return Column(
      children: [
        // 상단 액션 바
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_selectedImages.length}개 선택됨',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _isProcessing ? null : _pickImages,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('추가'),
                  ),
                  TextButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => setState(() => _selectedImages.clear()),
                    icon: const Icon(Icons.clear_all, size: 20),
                    label: const Text('전체 삭제'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 이미지 그리드
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedImages.length,
            itemBuilder: (context, index) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _selectedImages[index],
                      fit: BoxFit.cover,
                    ),
                  ),
                  // 삭제 버튼
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _isProcessing
                          ? null
                          : () {
                              setState(() {
                                _selectedImages.removeAt(index);
                              });
                            },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                  // 처리 완료 표시
                  if (_isProcessing && index < _processedCount)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.check, color: Colors.white, size: 32),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEffectChip(BatchEffect effect, String label, IconData icon) {
    final isSelected = _selectedEffect == effect;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedEffect = effect),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF2196F3)
                : Colors.grey.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18, color: isSelected ? Colors.white : Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 배치 처리 요청 데이터
class _BatchProcessRequest {
  final String imagePath;
  final BatchEffect effect;
  final double intensity;

  _BatchProcessRequest({
    required this.imagePath,
    required this.effect,
    required this.intensity,
  });
}

// 배치 효과 적용 (isolate에서 실행)
Uint8List? _applyBatchEffect(_BatchProcessRequest request) {
  try {
    final bytes = File(request.imagePath).readAsBytesSync();
    final image = img.decodeImage(bytes);
    if (image == null) return null;

    img.Image processed;

    switch (request.effect) {
      case BatchEffect.blur:
        final radius = (request.intensity * 20).toInt().clamp(1, 20);
        processed = img.gaussianBlur(image, radius: radius);
        break;
      case BatchEffect.mosaic:
        final blockSize = (request.intensity * 30).toInt().clamp(5, 30);
        processed = _applyMosaicToImage(image, blockSize);
        break;
      case BatchEffect.blackBar:
        // 전체 이미지를 검은색으로
        processed = img.fill(image, color: img.ColorRgb8(0, 0, 0));
        break;
    }

    return Uint8List.fromList(img.encodeJpg(processed, quality: 90));
  } catch (e) {
    debugPrint('배치 처리 오류: $e');
    return null;
  }
}

// 모자이크 효과 적용
img.Image _applyMosaicToImage(img.Image image, int blockSize) {
  final result = img.Image.from(image);

  for (int y = 0; y < image.height; y += blockSize) {
    for (int x = 0; x < image.width; x += blockSize) {
      // 블록 평균 색상 계산
      int r = 0, g = 0, b = 0, count = 0;

      for (int by = 0; by < blockSize && y + by < image.height; by++) {
        for (int bx = 0; bx < blockSize && x + bx < image.width; bx++) {
          final pixel = image.getPixel(x + bx, y + by);
          r += pixel.r.toInt();
          g += pixel.g.toInt();
          b += pixel.b.toInt();
          count++;
        }
      }

      if (count > 0) {
        r = r ~/ count;
        g = g ~/ count;
        b = b ~/ count;

        // 블록 채우기
        for (int by = 0; by < blockSize && y + by < image.height; by++) {
          for (int bx = 0; bx < blockSize && x + bx < image.width; bx++) {
            result.setPixelRgb(x + bx, y + by, r, g, b);
          }
        }
      }
    }
  }

  return result;
}

// ==================== Settings Screen ====================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showProSubscription(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ProSubscriptionSheet(),
    );
  }

  // 앱스토어 ID (출시 후 실제 ID로 변경)
  static const String _appStoreId = '6740097791';

  Future<void> _rateApp(BuildContext context) async {
    final url = Platform.isIOS
        ? Uri.parse('https://apps.apple.com/app/id$_appStoreId?action=write-review')
        : Uri.parse('https://play.google.com/store/apps/details?id=com.cover.app');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('앱스토어를 열 수 없습니다')),
        );
      }
    }
  }

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@cover.app',
      queryParameters: {
        'subject': '[Cover 앱 문의]',
        'body': '\n\n---\n앱 버전: 1.0.0\n기기: ${Platform.operatingSystem}',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          // Pro 구독 배너
          Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () => _showProSubscription(context),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.workspace_premium, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cover Pro',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '모든 기능을 무제한으로',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                  ],
                ),
              ),
            ),
          ),

          // 지원
          const _SectionHeader(title: '지원'),
          _SettingsTile(
            icon: Icons.star_outline,
            title: '앱 리뷰 작성',
            subtitle: '별점과 리뷰로 응원해주세요',
            onTap: () => _rateApp(context),
          ),
          _SettingsTile(
            icon: Icons.mail_outline,
            title: '문의하기',
            subtitle: 'support@cover.app',
            onTap: _sendEmail,
          ),

          const SizedBox(height: 8),

          // 앱 정보
          const _SectionHeader(title: '정보'),
          _SettingsTile(
            icon: Icons.info_outline,
            title: '버전',
            subtitle: '1.0.0',
            onTap: null,
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: '오픈소스 라이선스',
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Cover',
                applicationVersion: '1.0.0',
              );
            },
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: '개인정보 처리방침',
            onTap: () => _openUrl('https://cover.app/privacy'),
          ),
          _SettingsTile(
            icon: Icons.article_outlined,
            title: '이용약관',
            onTap: () => _openUrl('https://cover.app/terms'),
          ),

          const SizedBox(height: 32),

          // 앱 정보 푸터
          Center(
            child: Column(
              children: [
                Text(
                  'Cover',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white54 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '개인정보를 안전하게',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black26,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Pro 구독 바텀시트
class _ProSubscriptionSheet extends StatelessWidget {
  const _ProSubscriptionSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // 헤더
          const Icon(Icons.workspace_premium, size: 48, color: Color(0xFF6366F1)),
          const SizedBox(height: 12),
          const Text(
            'Cover Pro',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '모든 프리미엄 기능을 무제한으로 사용하세요',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),

          const SizedBox(height: 24),

          // 기능 목록
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _buildFeatureRow(Icons.auto_fix_high, '모든 편집 도구 무제한'),
                _buildFeatureRow(Icons.photo_library, '배치 처리 무제한'),
                _buildFeatureRow(Icons.emoji_emotions, '50+ 프리미엄 스티커'),
                _buildFeatureRow(Icons.block, '광고 제거'),
                _buildFeatureRow(Icons.support_agent, '우선 고객 지원'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 가격 옵션
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _buildPriceOption(
                  context,
                  title: '연간',
                  price: '₩19,900/년',
                  subtitle: '월 ₩1,658 (44% 할인)',
                  isPopular: true,
                ),
                const SizedBox(height: 12),
                _buildPriceOption(
                  context,
                  title: '월간',
                  price: '₩2,900/월',
                  subtitle: '',
                  isPopular: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 구독 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: 실제 구독 처리
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('곧 출시 예정입니다!')),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '무료 체험 시작하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 하단 안내
          Text(
            '7일 무료 체험 후 결제가 시작됩니다',
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
          TextButton(
            onPressed: () {
              // TODO: 구독 복원
            },
            child: Text(
              '이전 구매 복원',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6366F1), size: 22),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildPriceOption(
    BuildContext context, {
    required String title,
    required String price,
    required String subtitle,
    required bool isPopular,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: isPopular ? const Color(0xFF6366F1) : Colors.grey[300]!,
          width: isPopular ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (isPopular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '인기',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ],
            ),
          ),
          Text(
            price,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 24),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      onTap: onTap,
    );
  }
}
