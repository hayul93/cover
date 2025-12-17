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

enum EditTool { blur, mosaic, eraser, blackBar, highlighter }

enum DrawMode { brush, rectangle, circle }

// 브러시 프리셋
enum BrushPreset { small, medium, large }

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
                      return GestureDetector(
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
                        child: ClipRect(
                          child: Transform(
                            transform: Matrix4.identity()
                              ..translate(_offset.dx, _offset.dy)
                              ..scale(_scale),
                            child: CustomPaint(
                              size: canvasSize,
                              painter: ImageCanvasPainter(
                                image: _displayImage!,
                                currentStroke: _currentStroke,
                                brushSize: _brushSize,
                                tool: _currentTool,
                                drawMode: _drawMode,
                                shapeStart: _shapeStart,
                                shapeEnd: _shapeEnd,
                                highlighterColor: _highlighterColor,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // 로딩 표시
          if (_isProcessing)
            const LinearProgressIndicator(color: Color(0xFF2196F3)),

          // 하단 컨트롤
          Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 도구 선택 (스크롤 가능)
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildToolButton(EditTool.blur, Icons.blur_on, '블러'),
                      const SizedBox(width: 8),
                      _buildToolButton(EditTool.mosaic, Icons.grid_on, '모자이크'),
                      const SizedBox(width: 8),
                      _buildToolButton(EditTool.blackBar, Icons.rectangle, '검은바'),
                      const SizedBox(width: 8),
                      _buildToolButton(EditTool.highlighter, Icons.highlight, '형광펜'),
                      const SizedBox(width: 8),
                      _buildToolButton(EditTool.eraser, Icons.auto_fix_off, '지우개'),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // 그리기 모드 선택 (블러, 모자이크, 검은바에서만 표시)
                if (_currentTool == EditTool.blur ||
                    _currentTool == EditTool.mosaic ||
                    _currentTool == EditTool.blackBar)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModeChip(DrawMode.brush, Icons.brush, '브러시'),
                      const SizedBox(width: 8),
                      _buildModeChip(DrawMode.rectangle, Icons.crop_square, '사각형'),
                      const SizedBox(width: 8),
                      _buildModeChip(DrawMode.circle, Icons.circle_outlined, '원형'),
                    ],
                  ),

                // 형광펜 색상 선택
                if (_currentTool == EditTool.highlighter)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildColorChip(Colors.yellow, '노랑'),
                      const SizedBox(width: 8),
                      _buildColorChip(Colors.greenAccent, '초록'),
                      const SizedBox(width: 8),
                      _buildColorChip(Colors.pinkAccent, '분홍'),
                      const SizedBox(width: 8),
                      _buildColorChip(Colors.cyanAccent, '하늘'),
                      const SizedBox(width: 8),
                      _buildColorChip(Colors.orangeAccent, '주황'),
                    ],
                  ),

                const SizedBox(height: 12),

                // 브러시 프리셋
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final preset in BrushPreset.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _buildPresetButton(preset),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // 브러시 크기 슬라이더
                Row(
                  children: [
                    const SizedBox(width: 8),
                    const Icon(Icons.brush, color: Colors.white54, size: 20),
                    Expanded(
                      child: Slider(
                        value: _brushSize,
                        min: 10,
                        max: 120,
                        activeColor: const Color(0xFF2196F3),
                        inactiveColor: Colors.white24,
                        onChanged: (v) => setState(() => _brushSize = v),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        _brushSize.toInt().toString(),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),

                // 강도 슬라이더 (지우개, 검은바 제외)
                if (_currentTool != EditTool.eraser && _currentTool != EditTool.blackBar)
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      const Icon(Icons.opacity, color: Colors.white54, size: 20),
                      Expanded(
                        child: Slider(
                          value: _intensity,
                          min: 0.1,
                          max: 1.0,
                          activeColor: const Color(0xFF2196F3),
                          inactiveColor: Colors.white24,
                          onChanged: (v) => setState(() => _intensity = v),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${(_intensity * 100).toInt()}%',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 12),

                // 저장/공유 버튼
                Row(
                  children: [
                    // 저장 버튼
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _saveImage,
                          icon: const Icon(Icons.save_alt, size: 20),
                          label: const Text('저장', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 공유 버튼
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing ? null : _shareImage,
                          icon: const Icon(Icons.share, size: 20),
                          label: const Text('공유', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(DrawMode mode, IconData icon, String label) {
    final isSelected = _drawMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _drawMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white12,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12)),
          ],
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

  Widget _buildToolButton(EditTool tool, IconData icon, String label) {
    final isSelected = _currentTool == tool;
    return GestureDetector(
      onTap: () => setState(() => _currentTool = tool),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF2196F3) : Colors.white12,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: isSelected ? Colors.white : Colors.white70, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _saveImage() async {
    if (_currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // 파일명 생성
      final timestamp = DateTime.now().toString().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
      final fileName = 'Cover_$timestamp';

      // 갤러리에 저장
      final result = await ImageGallerySaver.saveImage(
        _currentBytes!,
        quality: 100,
        name: fileName,
      );

      if (mounted) {
        if (result['isSuccess'] == true) {
          // 최근 이미지에 원본 경로 추가
          await RecentImages.addImage(widget.imageFile.path);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('갤러리에 저장되었습니다'),
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

// ==================== Settings Screen ====================

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          // 테마 설정
          const _SectionHeader(title: '화면'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeNotifier,
            builder: (context, currentMode, child) {
              return Column(
                children: [
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    groupValue: currentMode,
                    onChanged: (value) => themeNotifier.value = value!,
                    title: const Text('시스템 설정'),
                    subtitle: const Text('기기 설정에 따라 자동 전환'),
                    secondary: const Icon(Icons.brightness_auto),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.light,
                    groupValue: currentMode,
                    onChanged: (value) => themeNotifier.value = value!,
                    title: const Text('라이트 모드'),
                    subtitle: const Text('밝은 테마 사용'),
                    secondary: const Icon(Icons.light_mode),
                  ),
                  RadioListTile<ThemeMode>(
                    value: ThemeMode.dark,
                    groupValue: currentMode,
                    onChanged: (value) => themeNotifier.value = value!,
                    title: const Text('다크 모드'),
                    subtitle: const Text('어두운 테마 사용'),
                    secondary: const Icon(Icons.dark_mode),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

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
