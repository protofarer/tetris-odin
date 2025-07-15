# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Tetris remake built with Odin and Raylib, following Game Boy mechanics and appearance with custom colors, game types, music, and timing parameters (ARE, DAS, ARR). Uses Nintendo rotation and scoring systems with Game Boy-style soft drop and level drop rates.

## Build Commands

### Development (Hot Reload)
```bash
./build_hot_reload.sh        # Build with hot reload support
./build_hot_reload.sh run    # Build and run with hot reload
./task.sh a                  # Quick hot reload build
./task.sh b                  # Run hot reload binary
```

### Production Builds
```bash
./build_release.sh           # Optimized release build (build/release/)
./build_debug.sh             # Debug build without hot reload (build/debug/)
./build_web.sh              # Web/WASM build (build/web/)
```

## Architecture

### Core Structure
- **Scene System**: Union-based scene management with Menu_Scene and Play_Scene
- **Game Loop**: Managed through `game_init()`, `game_update()`, `game_should_run()`, `game_shutdown()`
- **Hot Reload**: Separate entry points for development vs release builds

### Key Components
- **game.odin**: Core constants, types (Vec2, Vec2i, Position), window dimensions, timing parameters
- **scene.odin**: Scene switching system with update/draw/transition functions
- **tetramino.odin**: Tetris piece definitions, layouts, colors, and rotation logic
- **play_scene.odin**: Main gameplay logic, playfield management, line clearing
- **menu_scene.odin**: Menu navigation, game type selection, settings
- **resman.odin**: Resource management for assets (sounds, textures)
- **timer.odin**: Game timing and frame rate management

### Entry Points
- **main_release/**: Production builds without hot reload
- **main_hot_reload/**: Development builds with DLL hot reload
- **main_web/**: Web/WASM builds with Emscripten

### Game Constants
- Playfield: 10x18 blocks, 720x720 window
- Timing: 60 FPS tick rate, DAS=23 frames, ARR=9 frames
- Game modes: Marathon and Lines with configurable settings

### Asset Management
- Audio: Music (A/B/C), sound effects (clear, lock, rotate, shift)
- Graphics: Background, border, block sprites
- Preloaded via resource manager with web build support