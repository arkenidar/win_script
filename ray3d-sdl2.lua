#!/usr/bin/env luajit
-- ray3d-sdl2.lua - Simple raytracer with dynamic resolution using SDL2
-- Run: luajit ray3d-sdl2.lua

local ffi = require "ffi"

ffi.cdef [[
  typedef struct SDL_Window SDL_Window;
  typedef struct SDL_Renderer SDL_Renderer;
  typedef struct SDL_Texture SDL_Texture;
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

  int SDL_Init(Uint32 flags);
  void SDL_Quit(void);
  SDL_Window* SDL_CreateWindow(const char* title, int x, int y, int w, int h, Uint32 flags);
  void SDL_DestroyWindow(SDL_Window* window);
  SDL_Renderer* SDL_CreateRenderer(SDL_Window* window, int index, Uint32 flags);
  void SDL_DestroyRenderer(SDL_Renderer* renderer);
  int SDL_SetRenderDrawColor(SDL_Renderer* renderer, Uint8 r, Uint8 g, Uint8 b, Uint8 a);
  int SDL_RenderClear(SDL_Renderer* renderer);
  void SDL_RenderPresent(SDL_Renderer* renderer);
  int SDL_PollEvent(SDL_Event* event);
  const char* SDL_GetError(void);
  void SDL_Delay(Uint32 ms);
  Uint32 SDL_GetTicks(void);

  SDL_Texture* SDL_CreateTexture(SDL_Renderer* renderer, Uint32 format, int access, int w, int h);
  void SDL_DestroyTexture(SDL_Texture* texture);
  int SDL_UpdateTexture(SDL_Texture* texture, const void* rect, const void* pixels, int pitch);
  int SDL_RenderCopy(SDL_Renderer* renderer, SDL_Texture* texture, const void* srcrect, const void* dstrect);
  int SDL_GetRendererOutputSize(SDL_Renderer* renderer, int* w, int* h);
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
local SDL_WINDOW_RESIZABLE = 0x00000020
local SDL_RENDERER_ACCELERATED = 0x00000002
local SDL_RENDERER_PRESENTVSYNC = 0x00000004
local SDL_QUIT = 0x100
local SDL_KEYDOWN = 0x300
local SDL_WINDOWEVENT = 0x200
local SDL_WINDOWEVENT_SIZE_CHANGED = 6
local SDLK_ESCAPE = 27
local SDL_PIXELFORMAT_ARGB8888 = 372645892
local SDL_TEXTUREACCESS_STREAMING = 1

-- Canvas size (dynamic - matches window client area)
local W, H = 640, 480
local pixels = nil
local start_time = nil

-- Simple raytracer: multiple spheres with lighting and reflections
local function raytrace(w, h, angle)
    angle = angle or 0

    local cos_a = math.cos(angle)
    local sin_a = math.sin(angle)

    local spheres = {
        { x = 0,          y = 0, z = -5,             radius = 1,   r = 255, g = 100, b = 100, reflectivity = 0.7 }, -- Red center (reflective)
        { x = -2 * cos_a, y = 0, z = -5 + 2 * sin_a, radius = 0.8, r = 100, g = 200, b = 100, reflectivity = 0.6 }, -- Green (reflective)
        { x = 2 * cos_a,  y = 0, z = -5 - 2 * sin_a, radius = 0.8, r = 100, g = 150, b = 255, reflectivity = 0.6 }  -- Blue (reflective)
    }

    local light_x, light_y, light_z = 0.577, 0.577, 0.577

    local aspect = w / h

    -- Helper to check if a point is in shadow
    local function is_in_shadow(from_x, from_y, from_z)
        -- Trace ray from hit point to light
        local shadow_ray_x = light_x
        local shadow_ray_y = light_y
        local shadow_ray_z = light_z

        -- Check if shadow ray hits any sphere
        for _, sphere in ipairs(spheres) do
            local oc_x = from_x - sphere.x
            local oc_y = from_y - sphere.y
            local oc_z = from_z - sphere.z

            local a = shadow_ray_x * shadow_ray_x + shadow_ray_y * shadow_ray_y + shadow_ray_z * shadow_ray_z
            local b = 2 * (oc_x * shadow_ray_x + oc_y * shadow_ray_y + oc_z * shadow_ray_z)
            local c = oc_x * oc_x + oc_y * oc_y + oc_z * oc_z - sphere.radius * sphere.radius
            local discriminant = b * b - 4 * a * c

            if discriminant >= 0 then
                local t = (-b - math.sqrt(discriminant)) / (2 * a)
                if t > 0.001 and t < 10 then -- Shadow only if object is between point and light
                    return true
                end
            end
        end

        return false
    end

    -- Helper function to trace a ray and return color
    local function trace_ray(ray_x, ray_y, ray_z, depth, origin_x, origin_y, origin_z)
        if depth > 2 then return { r = 30, g = 40, b = 60 } end -- Max reflection depth

        -- Default origin is camera at (0,0,0)
        origin_x = origin_x or 0
        origin_y = origin_y or 0
        origin_z = origin_z or 0

        local closest_t = math.huge
        local closest_sphere_idx = nil
        local hit_normal = nil
        local is_floor = false

        -- Check floor intersection (y = -2, reflective)
        if ray_y < 0 then -- Only rays going downward can hit the floor
            local t = (-2 - origin_y) / ray_y
            if t > 0.001 and t < closest_t then
                local hit_x = origin_x + ray_x * t
                local hit_z = origin_z + ray_z * t

                -- Only if within a reasonable distance from objects
                if math.abs(hit_x) < 10 and math.abs(hit_z + 5) < 10 then -- Center around spheres at z=-5
                    closest_t = t
                    closest_sphere_idx = nil
                    is_floor = true
                    hit_normal = { x = 0, y = 1, z = 0 } -- Floor normal points up
                end
            end
        end

        -- Check intersection with all spheres
        for i, sphere in ipairs(spheres) do
            local oc_x = origin_x - sphere.x
            local oc_y = origin_y - sphere.y
            local oc_z = origin_z - sphere.z

            local a = ray_x * ray_x + ray_y * ray_y + ray_z * ray_z
            local b = 2 * (oc_x * ray_x + oc_y * ray_y + oc_z * ray_z)
            local c = oc_x * oc_x + oc_y * oc_y + oc_z * oc_z - sphere.radius * sphere.radius
            local discriminant = b * b - 4 * a * c

            if discriminant >= 0 then
                local t = (-b - math.sqrt(discriminant)) / (2 * a)
                if t > 0.001 and t < closest_t then
                    closest_t = t
                    closest_sphere_idx = i

                    local hit_x = origin_x + ray_x * t
                    local hit_y = origin_y + ray_y * t
                    local hit_z = origin_z + ray_z * t

                    hit_normal = {
                        x = (hit_x - sphere.x) / sphere.radius,
                        y = (hit_y - sphere.y) / sphere.radius,
                        z = (hit_z - sphere.z) / sphere.radius
                    }
                end
            end
        end

        if closest_sphere_idx == nil and not is_floor then
            return { r = 30, g = 40, b = 60 } -- Background color
        end

        if not hit_normal then
            return { r = 30, g = 40, b = 60 } -- Safety check: no valid hit
        end

        if is_floor then
            -- Floor color with checkerboard pattern
            local hit_x = origin_x + ray_x * closest_t
            local hit_y = origin_y + ray_y * closest_t
            local hit_z = origin_z + ray_z * closest_t
            local checker = (math.floor(hit_x) + math.floor(hit_z)) % 2
            local floor_color = { r = 200, g = 200, b = 200 }
            if checker == 1 then
                floor_color = { r = 100, g = 100, b = 100 }
            end

            -- Check shadow
            local in_shadow = is_in_shadow(hit_x, hit_y, hit_z)
            local diffuse = in_shadow and 0.3 or 0.8 -- Dark if in shadow, bright if lit
            floor_color.r = math.floor(floor_color.r * diffuse)
            floor_color.g = math.floor(floor_color.g * diffuse)
            floor_color.b = math.floor(floor_color.b * diffuse)

            -- Floor reflection (reflect ray direction around normal (0,1,0))
            -- Reflected ray direction: flip y component
            local reflect_dir_x = ray_x
            local reflect_dir_y = -ray_y
            local reflect_dir_z = ray_z

            -- Normalize reflected direction
            local reflect_len = math.sqrt(reflect_dir_x * reflect_dir_x + reflect_dir_y * reflect_dir_y +
                reflect_dir_z * reflect_dir_z)
            reflect_dir_x = reflect_dir_x / reflect_len
            reflect_dir_y = reflect_dir_y / reflect_len
            reflect_dir_z = reflect_dir_z / reflect_len

            -- Trace from floor hit point in reflected direction
            local reflect_color = trace_ray(reflect_dir_x, reflect_dir_y, reflect_dir_z, depth + 1, hit_x, hit_y, hit_z)

            floor_color.r = math.floor(floor_color.r * 0.3 + reflect_color.r * 0.7)
            floor_color.g = math.floor(floor_color.g * 0.3 + reflect_color.g * 0.7)
            floor_color.b = math.floor(floor_color.b * 0.3 + reflect_color.b * 0.7)

            return floor_color
        end

        local sphere = spheres[closest_sphere_idx]

        -- Calculate hit point
        local hit_x = origin_x + ray_x * closest_t
        local hit_y = origin_y + ray_y * closest_t
        local hit_z = origin_z + ray_z * closest_t

        -- Check if point is in shadow
        local in_shadow = is_in_shadow(hit_x, hit_y, hit_z)

        -- Calculate diffuse lighting
        local diffuse = hit_normal.x * light_x + hit_normal.y * light_y + hit_normal.z * light_z
        diffuse = math.max(0.2, math.min(1, diffuse))

        -- If in shadow, only use ambient light
        if in_shadow then
            diffuse = 0.2
        end

        local base_color = {
            r = math.floor(sphere.r * (0.3 + diffuse * 0.7)),
            g = math.floor(sphere.g * (0.3 + diffuse * 0.7)),
            b = math.floor(sphere.b * (0.3 + diffuse * 0.7))
        }

        -- If reflective, trace reflection
        if sphere.reflectivity > 0 then
            local reflect_x = ray_x - 2 * (ray_x * hit_normal.x + ray_y * hit_normal.y + ray_z * hit_normal.z) *
                hit_normal.x
            local reflect_y = ray_y - 2 * (ray_x * hit_normal.x + ray_y * hit_normal.y + ray_z * hit_normal.z) *
                hit_normal.y
            local reflect_z = ray_z - 2 * (ray_x * hit_normal.x + ray_y * hit_normal.y + ray_z * hit_normal.z) *
                hit_normal.z

            local reflect_color = trace_ray(reflect_x, reflect_y, reflect_z, depth + 1, hit_x, hit_y, hit_z)

            -- Blend base color with reflection
            base_color.r = math.floor(base_color.r * (1 - sphere.reflectivity) + reflect_color.r * sphere.reflectivity)
            base_color.g = math.floor(base_color.g * (1 - sphere.reflectivity) + reflect_color.g * sphere.reflectivity)
            base_color.b = math.floor(base_color.b * (1 - sphere.reflectivity) + reflect_color.b * sphere.reflectivity)
        end

        return base_color
    end

    for y = 0, h - 1 do
        for x = 0, w - 1 do
            -- Proper camera ray calculation with aspect ratio
            local u = (2 * x / w - 1) * aspect
            local v = -(2 * y / h - 1)

            local ray_x, ray_y, ray_z = u, v, -1
            local len = math.sqrt(ray_x * ray_x + ray_y * ray_y + ray_z * ray_z)
            ray_x, ray_y, ray_z = ray_x / len, ray_y / len, ray_z / len

            local color = trace_ray(ray_x, ray_y, ray_z, 0)

            -- SDL2 uses ARGB format
            local idx = (y * w + x) * 4
            pixels[idx + 0] = color.b
            pixels[idx + 1] = color.g
            pixels[idx + 2] = color.r
            pixels[idx + 3] = 255
        end
    end
end

-- Helper to allocate and raytrace at new resolution
local function resize_and_raytrace(w, h, texture, renderer)
    W, H = w, h
    pixels = ffi.new("uint8_t[?]", w * h * 4)

    -- Recreate texture at new size
    if texture ~= nil then
        sdl.SDL_DestroyTexture(texture)
    end
    texture = sdl.SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, w, h)

    raytrace(w, h, 0)
    return texture
end

local function main()
    print("=== Raytracer (Dynamic Resolution - SDL2) ===")

    -- Initialize SDL
    if sdl.SDL_Init(SDL_INIT_VIDEO) < 0 then
        print("ERROR: SDL_Init failed: " .. ffi.string(sdl.SDL_GetError()))
        return
    end
    print("[OK] SDL initialized")

    -- Create window
    local window = sdl.SDL_CreateWindow(
        "Raytracer (SDL2)",
        100, 100,
        W, H,
        SDL_WINDOW_SHOWN + SDL_WINDOW_RESIZABLE
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
        SDL_RENDERER_ACCELERATED
    )

    if renderer == nil then
        print("ERROR: SDL_CreateRenderer failed: " .. ffi.string(sdl.SDL_GetError()))
        sdl.SDL_DestroyWindow(window)
        sdl.SDL_Quit()
        return
    end
    print("[OK] Renderer created")

    -- Create texture for pixel buffer
    pixels = ffi.new("uint8_t[?]", W * H * 4)
    local texture = sdl.SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_STREAMING, W, H)

    if texture == nil then
        print("ERROR: SDL_CreateTexture failed: " .. ffi.string(sdl.SDL_GetError()))
        sdl.SDL_DestroyRenderer(renderer)
        sdl.SDL_DestroyWindow(window)
        sdl.SDL_Quit()
        return
    end
    print("[OK] Texture created")

    -- Initial raytrace
    start_time = sdl.SDL_GetTicks()
    raytrace(W, H, 0)

    -- Main loop
    print("[OK] Event loop...")
    local event = ffi.new("SDL_Event")
    local running = true
    local need_resize = false

    while running do
        -- Poll events
        while sdl.SDL_PollEvent(event) ~= 0 do
            if event.type == SDL_QUIT then
                running = false
            elseif event.type == SDL_KEYDOWN then
                local keyEvent = ffi.cast("SDL_KeyboardEvent*", event)
                if keyEvent.sym == SDLK_ESCAPE then
                    running = false
                end
            elseif event.type == SDL_WINDOWEVENT then
                -- Check for window resize (read byte at offset 12 for event field)
                local windowEvent = event.type
                local eventField = ffi.cast("uint8_t*", event)[12]
                if eventField == SDL_WINDOWEVENT_SIZE_CHANGED then
                    need_resize = true
                end
            end
        end

        -- Handle resize
        if need_resize then
            local w_ptr = ffi.new("int[1]")
            local h_ptr = ffi.new("int[1]")
            sdl.SDL_GetRendererOutputSize(renderer, w_ptr, h_ptr)
            local new_w = w_ptr[0]
            local new_h = h_ptr[0]

            if new_w > 0 and new_h > 0 and (new_w ~= W or new_h ~= H) then
                texture = resize_and_raytrace(new_w, new_h, texture, renderer)
            end
            need_resize = false
        end

        -- Calculate animation angle
        local elapsed_ms = sdl.SDL_GetTicks() - start_time
        local elapsed_s = elapsed_ms / 1000
        local angle = (elapsed_s * 1.5) % (2 * math.pi)

        -- Raytrace current frame
        raytrace(W, H, angle)

        -- Update texture with pixel data
        sdl.SDL_UpdateTexture(texture, nil, pixels, W * 4)

        -- Clear and render
        sdl.SDL_RenderClear(renderer)
        sdl.SDL_RenderCopy(renderer, texture, nil, nil)
        sdl.SDL_RenderPresent(renderer)

        -- Small delay to reduce CPU usage
        sdl.SDL_Delay(16) -- ~60 FPS
    end

    -- Cleanup
    sdl.SDL_DestroyTexture(texture)
    sdl.SDL_DestroyRenderer(renderer)
    sdl.SDL_DestroyWindow(window)
    sdl.SDL_Quit()
    print("[OK] Exited")
end

main()
