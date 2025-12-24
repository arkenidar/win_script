#!/usr/bin/env luajit
-- canvas-sdl2.lua - Simple 2D canvas with rectangle drawing using SDL2
-- Run: luajit canvas-sdl2.lua

local ffi = require "ffi"

ffi.cdef [[
  typedef struct SDL_Window SDL_Window;
  typedef struct SDL_Renderer SDL_Renderer;
  typedef uint32_t Uint32;
  typedef uint8_t Uint8;
  typedef uint16_t Uint16;
  typedef int32_t Sint32;

  typedef struct {
    Uint32 type;
    Uint32 timestamp;
    Uint8 padding[52];
  } SDL_Event;

  typedef struct {
    Uint32 type;
    Uint32 timestamp;
    Uint32 windowID;
    Uint8 state;
    Uint8 repeat_;
    Uint8 padding2;
    Uint8 padding3;
    Sint32 scancode;
    Sint32 sym;
    Uint16 mod;
    Uint32 unused;
  } SDL_KeyboardEvent;

  typedef enum {
    SDL_INIT_VIDEO = 0x00000020,
    SDL_INIT_EVENTS = 0x00004000
  } SDL_InitFlags;

  typedef enum {
    SDL_WINDOW_SHOWN = 0x00000004
  } SDL_WindowFlags;

  typedef enum {
    SDL_RENDERER_ACCELERATED = 0x00000002,
    SDL_RENDERER_PRESENTVSYNC = 0x00000004
  } SDL_RendererFlags;

  int SDL_Init(Uint32 flags);
  void SDL_Quit(void);
  SDL_Window* SDL_CreateWindow(const char* title, int x, int y, int w, int h, Uint32 flags);
  void SDL_DestroyWindow(SDL_Window* window);
  SDL_Renderer* SDL_CreateRenderer(SDL_Window* window, int index, Uint32 flags);
  void SDL_DestroyRenderer(SDL_Renderer* renderer);
  int SDL_SetRenderDrawColor(SDL_Renderer* renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
  int SDL_RenderClear(SDL_Renderer* renderer);
  void SDL_RenderPresent(SDL_Renderer* renderer);
  int SDL_RenderFillRect(SDL_Renderer* renderer, const void* rect);
  int SDL_RenderDrawRect(SDL_Renderer* renderer, const void* rect);
  int SDL_PollEvent(SDL_Event* event);
  const char* SDL_GetError(void);
  void SDL_Delay(Uint32 ms);

  typedef struct { int x, y, w, h; } SDL_Rect;
]]

-- Try to load SDL2 library
local sdl
local ok, err = pcall(function()
    if ffi.os == "Windows" then
        sdl = ffi.load("SDL2")
    elseif ffi.os == "OSX" then
        sdl = ffi.load("SDL2")
    else
        -- Linux
        sdl = ffi.load("SDL2")
    end
end)

if not ok then
    print("ERROR: Failed to load SDL2 library")
    print("Please install SDL2:")
    print("  Linux: sudo apt-get install libsdl2-2.0-0")
    print("  macOS: brew install sdl2")
    print("  Windows: Download SDL2.dll from libsdl.org")
    os.exit(1)
end

-- SDL constants
local SDL_INIT_VIDEO = 0x00000020
local SDL_WINDOW_SHOWN = 0x00000004
local SDL_RENDERER_ACCELERATED = 0x00000002
local SDL_RENDERER_PRESENTVSYNC = 0x00000004
local SDL_QUIT = 0x100
local SDL_KEYDOWN = 0x300
local SDLK_ESCAPE = 27

local function main()
    print("=== 2D Canvas - Rectangle Demo (SDL2) ===")

    -- Initialize SDL
    if sdl.SDL_Init(SDL_INIT_VIDEO) < 0 then
        print("ERROR: SDL_Init failed: " .. ffi.string(sdl.SDL_GetError()))
        return
    end
    print("[OK] SDL initialized")

    -- Create window
    local window = sdl.SDL_CreateWindow(
        "2D Canvas (SDL2)",
        100, 100, -- x, y position
        400, 300, -- width, height
        SDL_WINDOW_SHOWN
    )

    if window == nil then
        print("ERROR: SDL_CreateWindow failed: " .. ffi.string(sdl.SDL_GetError()))
        sdl.SDL_Quit()
        return
    end
    print("[OK] Window created")

    -- Create renderer
    local renderer = sdl.SDL_CreateRenderer(
        window,
        -1,
        SDL_RENDERER_ACCELERATED + SDL_RENDERER_PRESENTVSYNC
    )

    if renderer == nil then
        print("ERROR: SDL_CreateRenderer failed: " .. ffi.string(sdl.SDL_GetError()))
        sdl.SDL_DestroyWindow(window)
        sdl.SDL_Quit()
        return
    end
    print("[OK] Renderer created")

    -- Main loop
    print("[OK] Event loop...")
    local event = ffi.new("SDL_Event")
    local running = true

    while running do
        -- Poll events
        while sdl.SDL_PollEvent(event) ~= 0 do
            if event.type == SDL_QUIT then
                running = false
            elseif event.type == SDL_KEYDOWN then
                -- Cast event to keyboard event to access key data
                local keyEvent = ffi.cast("SDL_KeyboardEvent*", event)
                if keyEvent.sym == SDLK_ESCAPE then
                    running = false
                end
            end
        end

        -- Clear screen with white background
        sdl.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
        sdl.SDL_RenderClear(renderer)

        -- Draw red filled rectangle
        sdl.SDL_SetRenderDrawColor(renderer, 255, 0, 0, 255) -- Red
        local fillRect = ffi.new("SDL_Rect", { x = 50, y = 50, w = 200, h = 150 })
        sdl.SDL_RenderFillRect(renderer, fillRect)

        -- Draw black border around rectangle
        sdl.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) -- Black
        local borderRect = ffi.new("SDL_Rect", { x = 50, y = 50, w = 200, h = 150 })
        sdl.SDL_RenderDrawRect(renderer, borderRect)

        -- Present
        sdl.SDL_RenderPresent(renderer)

        -- Small delay to reduce CPU usage
        sdl.SDL_Delay(16) -- ~60 FPS
    end

    -- Cleanup
    sdl.SDL_DestroyRenderer(renderer)
    sdl.SDL_DestroyWindow(window)
    sdl.SDL_Quit()
    print("[OK] Exited")
end

main()
