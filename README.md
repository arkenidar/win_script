# LuaJIT Win32 & SDL2 Graphics Demos

This project demonstrates parallel implementations of 2D canvas drawing and 3D raytracing using both **Win32 API** (Windows-only) and **SDL2** (cross-platform).

## Project Structure

### Canvas Demos (2D Drawing)
- **[canvas-winapi.lua](canvas-winapi.lua)** - Win32 GDI canvas with red rectangle
- **[canvas-sdl2.lua](canvas-sdl2.lua)** - SDL2 canvas with red rectangle (cross-platform)

### Raytracing Demos (3D Rendering)
- **[ray3d-winapi.lua](ray3d-winapi.lua)** - Win32 raytracer with reflections, shadows, animated spheres
- **[ray3d-sdl2.lua](ray3d-sdl2.lua)** - SDL2 raytracer with same features (cross-platform)

## Features Comparison

### Canvas Demos
| Feature | Win32 | SDL2 |
|---------|-------|------|
| 2D rectangle drawing | ✓ | ✓ |
| Mouse cursor visible | ✓ | ✓ |
| Escape key exits | ✓ | ✓ |
| Window resize | ✓ | ✓ |
| Platform | Windows only | Cross-platform |

### Raytracing Demos
| Feature | Win32 | SDL2 |
|---------|-------|------|
| 3 animated spheres (RGB) | ✓ | ✓ |
| Reflective surfaces | ✓ | ✓ |
| Checkerboard floor | ✓ | ✓ |
| Dynamic shadows | ✓ | ✓ |
| Multi-bounce reflections | ✓ | ✓ |
| Dynamic resolution | ✓ | ✓ |
| Smooth time-based animation | ✓ | ✓ |
| Escape key exits | ✓ | ✓ |
| Platform | Windows only | Cross-platform |

## Running the Demos

### Win32 Versions (Windows with Wine)
```bash
cd /home/arkenidar/luajit/win_script
wine luajit.exe canvas-winapi.lua
wine luajit.exe ray3d-winapi.lua
```

### SDL2 Versions (Native Linux)
```bash
cd /home/arkenidar/luajit/win_script
luajit canvas-sdl2.lua
luajit ray3d-sdl2.lua
```

## Requirements

### For Win32 versions:
- **Wine** (Linux) or Windows
- **LuaJIT** (Windows build: `luajit.exe`)

### For SDL2 versions:
- **LuaJIT** (native build)
- **SDL2** library (`libSDL2-2.0.so.0` on Linux, `SDL2.dll` on Windows)

Install SDL2 on Linux:
```bash
sudo apt-get install libsdl2-2.0-0
```

## Technical Details

### Win32 Implementation
- Uses FFI to call Win32 APIs: `user32.dll`, `kernel32.dll`, `gdi32.dll`
- GDI for 2D drawing (`Rectangle`, `CreateSolidBrush`)
- `StretchDIBits` for pixel buffer rendering (raytracer)
- Win32 message loop (`GetMessageW`, `DispatchMessageW`)
- Timer-based animation (`SetTimer`, `WM_TIMER`)

### SDL2 Implementation
- Uses FFI to call SDL2 APIs
- SDL2 renderer for 2D drawing
- `SDL_Texture` with streaming for pixel buffer rendering (raytracer)
- SDL2 event loop (`SDL_PollEvent`)
- Time-based animation (`SDL_GetTicks`)
- Automatic library detection (Linux `.so` / Windows `.dll`)

### Raytracer Features
- **Camera model**: Perspective projection with aspect ratio correction
- **Ray-sphere intersection**: Analytic quadratic solution
- **Ray-plane intersection**: Floor at y = -2
- **Lighting**: Single directional light with diffuse shading
- **Shadows**: Ray tracing from hit point to light source
- **Reflections**: Recursive ray tracing (max depth 2)
- **Materials**: Configurable reflectivity per sphere (0.6-0.7)
- **Animation**: Spheres orbit around center using time-based rotation
- **Dynamic resolution**: Renders at exact window size (no oversampling)

## Code Structure

Both Win32 and SDL2 versions follow the same logical structure:

1. **FFI Declarations**: Platform-specific API types and functions
2. **Utility Functions**: `wstr()` for Win32, helper functions
3. **Raytracer Logic**: 
   - `raytrace(w, h, angle)` - Main rendering loop
   - `trace_ray()` - Recursive ray tracer
   - `is_in_shadow()` - Shadow testing
4. **Window/Event Handling**: Platform-specific message/event loop
5. **Main Function**: Window creation and initialization

## Performance

- **Win32**: ~30-60 FPS at 640x480 (depends on CPU)
- **SDL2**: Similar performance to Win32
- **Rendering**: Real-time ray tracing with reflections and shadows
- **Resolution**: Dynamically adjusts to window size

## Future Enhancements

Possible improvements:
- Anti-aliasing (supersampling)
- More complex geometry (triangles, meshes)
- Multiple light sources
- Texture mapping
- Refractions (transparent materials)
- Depth of field
- Ambient occlusion
- Path tracing

## License

Educational/demonstration code. Use freely.
