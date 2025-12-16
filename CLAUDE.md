# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cover is a cross-platform image privacy app built with Flutter that lets users blur and mosaic sensitive information in photos. The app supports iOS (13.0+) and Android (API 23+).

**Language**: Dart 3.9.2+ with Flutter
**Status**: Fresh start - basic template only

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run in debug mode
flutter run

# Build for platforms
flutter build ios
flutter build apk

# Run tests
flutter test

# Analyze code
flutter analyze
```

## Current Project Structure

```
lib/
└── main.dart         # Basic app template (HomeScreen only)
```

## Dependencies

Minimal dependencies for MVP:
- `image` - Image processing
- `image_picker` - Gallery/camera access
- `path_provider` - File storage
- `share_plus` - Native share
- `image_gallery_saver` - Save to gallery
- `permission_handler` - Permissions

## What Needs to Be Built

According to PRD.md:

1. **Image Import** - Gallery picker, camera capture
2. **Blur Tool** - Gaussian blur with brush
3. **Mosaic Tool** - Pixelation effect
4. **Eraser Tool** - Remove blur/mosaic
5. **Undo/Redo** - Edit history (max 10 steps)
6. **Save/Share** - Export to gallery, share sheet
7. **Dark Mode** - Theme support

## Design Guidelines

- Primary Color: #2196F3 (Blue)
- Background: Black (#000000 or #0F0F0F for dark mode)
- Spacing: 8px base grid
- Min touch target: 44x44px (iOS), 48x48px (Android)
