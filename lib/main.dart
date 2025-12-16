import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const CoverApp());
}

class CoverApp extends StatelessWidget {
  const CoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cover',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2196F3),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const HomeScreen(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Cover',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '개인정보를 안전하게',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 64),
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
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                      ),
                    ),
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

enum EditTool { blur, mosaic, eraser }

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
  double _brushSize = 40.0;
  double _intensity = 0.5;
  bool _isProcessing = false;

  // 현재 스트로크
  List<Offset> _currentStroke = [];

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
        _currentStroke = [imagePoint];
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size canvasSize) {
    if (_isProcessing || _displayImage == null) return;

    final imagePoint = _canvasToImage(details.localPosition, canvasSize);
    if (imagePoint != null) {
      setState(() {
        _currentStroke.add(imagePoint);
      });
    }
  }

  void _onPanEnd(DragEndDetails details) async {
    if (_currentStroke.isEmpty || _currentBytes == null) return;

    setState(() => _isProcessing = true);

    try {
      // Undo 스택에 현재 상태 저장
      _undoStack.add(_currentBytes!);
      _redoStack.clear();
      if (_undoStack.length > 10) _undoStack.removeAt(0);

      // 블러/모자이크 적용
      final request = ProcessRequest(
        imageBytes: _currentBytes!,
        points: _currentStroke.map((p) => [p.dx, p.dy]).toList(),
        brushSize: _brushSize,
        intensity: _intensity,
        tool: _currentTool,
        originalBytes: _originalBytes!,
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
          _isProcessing = false;
        });
      }
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
                        onPanStart: (d) => _onPanStart(d, canvasSize),
                        onPanUpdate: (d) => _onPanUpdate(d, canvasSize),
                        onPanEnd: _onPanEnd,
                        child: CustomPaint(
                          size: canvasSize,
                          painter: ImageCanvasPainter(
                            image: _displayImage!,
                            currentStroke: _currentStroke,
                            brushSize: _brushSize,
                            tool: _currentTool,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 도구 선택
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildToolButton(EditTool.blur, Icons.blur_on, '블러'),
                    _buildToolButton(EditTool.mosaic, Icons.grid_on, '모자이크'),
                    _buildToolButton(EditTool.eraser, Icons.auto_fix_off, '지우개'),
                  ],
                ),
                const SizedBox(height: 16),

                // 브러시 크기
                Row(
                  children: [
                    const SizedBox(width: 8),
                    const Icon(Icons.brush, color: Colors.white54, size: 20),
                    Expanded(
                      child: Slider(
                        value: _brushSize,
                        min: 20,
                        max: 100,
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

                // 강도 (지우개 제외)
                if (_currentTool != EditTool.eraser)
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

  ProcessRequest({
    required this.imageBytes,
    required this.points,
    required this.brushSize,
    required this.intensity,
    required this.tool,
    required this.originalBytes,
  });
}

Uint8List _processImage(ProcessRequest request) {
  final image = img.decodeImage(request.imageBytes);
  if (image == null) return request.imageBytes;

  final points = request.points.map((p) => Offset(p[0], p[1])).toList();
  final radius = (request.brushSize / 2).toInt();

  switch (request.tool) {
    case EditTool.blur:
      _applyBlur(image, points, radius, request.intensity);
      break;
    case EditTool.mosaic:
      _applyMosaic(image, points, radius, request.intensity);
      break;
    case EditTool.eraser:
      final original = img.decodeImage(request.originalBytes);
      if (original != null) {
        _applyEraser(image, original, points, radius);
      }
      break;
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

// ==================== Canvas Painter ====================

class ImageCanvasPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> currentStroke;
  final double brushSize;
  final EditTool tool;

  ImageCanvasPainter({
    required this.image,
    required this.currentStroke,
    required this.brushSize,
    required this.tool,
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

    // 현재 스트로크 미리보기
    if (currentStroke.isNotEmpty) {
      final scaleX = fittedSize.destination.width / imageSize.width;
      final scaleY = fittedSize.destination.height / imageSize.height;

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
    }
  }

  @override
  bool shouldRepaint(covariant ImageCanvasPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.currentStroke != currentStroke ||
        oldDelegate.brushSize != brushSize ||
        oldDelegate.tool != tool;
  }
}
