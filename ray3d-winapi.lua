#!/usr/bin/env luajit
-- canvas_ray.lua - Simple raytracer with dynamic resolution
-- Run: wine luajit.exe canvas_ray.lua

local ffi = require "ffi"

ffi.cdef [[
  typedef void* HINSTANCE;
  typedef void* HWND;
  typedef void* HDC;
  typedef void* HBRUSH;
  typedef unsigned int UINT;
  typedef long LONG;
  typedef int INT;
  typedef unsigned long ULONG;
  typedef int BOOL;
  typedef void* LPVOID;
  typedef const wchar_t* LPCWSTR;
  typedef __int64 LPARAM;
  typedef __int64 WPARAM;
  typedef long LRESULT;

  typedef struct {
    UINT cbSize; UINT style;
    LRESULT (*lpfnWndProc)(HWND, UINT, WPARAM, LPARAM);
    INT cbClsExtra; INT cbWndExtra; HINSTANCE hInstance;
    void* hIcon; void* hCursor; HBRUSH hbrBackground;
    LPCWSTR lpszMenuName; LPCWSTR lpszClassName; void* hIconSm;
  } WNDCLASSEXW;

  typedef struct { LONG left; LONG top; LONG right; LONG bottom; } RECT;
  typedef struct { HWND hwnd; UINT message; WPARAM wParam; LPARAM lParam; ULONG time; INT x; INT y; UINT lPrivate; } MSG;
  typedef struct { HDC hdc; BOOL fErase; RECT rcPaint; BOOL fRestore; BOOL fIncUpdate; unsigned char rgbReserved[32]; } PAINTSTRUCT;
  typedef struct { ULONG biSize; LONG biWidth; LONG biHeight; unsigned short biPlanes; unsigned short biBitCount; ULONG biCompression; ULONG biSizeImage; LONG biXPelsPerMeter; LONG biYPelsPerMeter; ULONG biClrUsed; ULONG biClrImportant; } BITMAPINFOHEADER;
  typedef struct { BITMAPINFOHEADER bmiHeader; ULONG bmiColors[1]; } BITMAPINFO;

  HWND CreateWindowExW(ULONG, LPCWSTR, LPCWSTR, ULONG, INT, INT, INT, INT, HWND, void*, HINSTANCE, LPVOID);
  BOOL RegisterClassExW(const WNDCLASSEXW*);
  LRESULT DefWindowProcW(HWND, UINT, WPARAM, LPARAM);
  BOOL GetMessageW(void*, HWND, UINT, UINT);
  BOOL TranslateMessage(const void*);
  LRESULT DispatchMessageW(const void*);
  HINSTANCE GetModuleHandleW(LPCWSTR);
  BOOL ShowWindow(HWND, INT);
  BOOL UpdateWindow(HWND);
  void PostQuitMessage(INT);
  HDC BeginPaint(HWND, PAINTSTRUCT*);
  BOOL EndPaint(HWND, const PAINTSTRUCT*);
  BOOL GetClientRect(HWND, RECT*);
  BOOL InvalidateRect(HWND, const RECT*, BOOL);
  INT StretchDIBits(HDC, INT, INT, INT, INT, INT, INT, INT, INT, const void*, const BITMAPINFO*, UINT, ULONG);
  typedef void* HCURSOR;
  HCURSOR LoadCursorW(HINSTANCE, LPCWSTR);
  typedef void* HBRUSH;
  HBRUSH CreateSolidBrush(ULONG);
  INT FillRect(HDC, const RECT*, HBRUSH);
  BOOL DeleteObject(void*);
  typedef unsigned int UINT_PTR;
  UINT_PTR SetTimer(HWND, UINT_PTR, UINT, void*);
  BOOL KillTimer(HWND, UINT_PTR);
  ULONG GetTickCount(void);
]]

local kernel32 = ffi.load("kernel32")
local user32 = ffi.load("user32")
local gdi32 = ffi.load("gdi32")

local function wstr(str)
    if not str then return nil end
    local len = #str
    local b = ffi.new("wchar_t[?]", len + 1)
    for i = 0, len - 1 do b[i] = string.byte(str, i + 1) end
    b[len] = 0
    return b
end

-- Canvas size (dynamic - matches window client area)
local W, H = 800, 600
local pixels = nil
local bmi = nil
local start_time = nil -- Will be set on WM_CREATE

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

            local idx = (y * w + x) * 4
            pixels[idx + 0] = color.b
            pixels[idx + 1] = color.g
            pixels[idx + 2] = color.r
            pixels[idx + 3] = 0
        end
    end
    -- print("[OK] Raytraced " .. w .. "x" .. h)
end

-- Helper to allocate and raytrace at new resolution
local function resize_and_raytrace(w, h)
    W, H = w, h
    pixels = ffi.new("uint8_t[?]", w * h * 4)

    bmi = ffi.new("BITMAPINFO")
    bmi.bmiHeader.biSize = ffi.sizeof("BITMAPINFOHEADER")
    bmi.bmiHeader.biWidth = w
    bmi.bmiHeader.biHeight = -h
    bmi.bmiHeader.biPlanes = 1
    bmi.bmiHeader.biBitCount = 32
    bmi.bmiHeader.biCompression = 0

    raytrace(w, h, 0)
end

-- Initialize with fixed 400x300 resolution
pixels = ffi.new("uint8_t[?]", W * H * 4)

bmi = ffi.new("BITMAPINFO")
bmi.bmiHeader.biSize = ffi.sizeof("BITMAPINFOHEADER")
bmi.bmiHeader.biWidth = W
bmi.bmiHeader.biHeight = -H
bmi.bmiHeader.biPlanes = 1
bmi.bmiHeader.biBitCount = 32
bmi.bmiHeader.biCompression = 0

-- Raytrace once at startup
-- raytrace(W, H, 0)

local function WndProc(hWnd, msg, wParam, lParam)
    if msg == 1 then                      -- WM_CREATE
        start_time = tonumber(kernel32.GetTickCount())
        user32.SetTimer(hWnd, 1, 16, nil) -- Timer every 16ms (~60 FPS target)
        return 0
    elseif msg == 275 then                -- WM_TIMER
        if start_time then
            local elapsed_ms = tonumber(kernel32.GetTickCount()) - start_time
            local elapsed_s = elapsed_ms / 1000
            local angle = (elapsed_s * 1.5) % (2 * math.pi) -- Complete rotation every ~4.2 seconds
            resize_and_raytrace(W, H)
            -- Recalculate with new angle for next frame
            raytrace(W, H, angle)
            user32.InvalidateRect(hWnd, nil, 0)
        end
        return 0
    elseif msg == 2 then -- WM_DESTROY
        user32.KillTimer(hWnd, 1)
        user32.PostQuitMessage(0)
        return 0
    elseif msg == 256 then     -- WM_KEYDOWN
        if wParam == 0x1B then -- VK_ESCAPE
            user32.PostQuitMessage(0)
            return 0
        end
    elseif msg == 15 then -- WM_PAINT
        local ps = ffi.new("PAINTSTRUCT")
        local hdc = user32.BeginPaint(hWnd, ps)

        -- Display at 1:1 (no oversampling)
        if pixels and bmi then
            gdi32.StretchDIBits(hdc, 0, 0, W, H,
                0, 0, W, H, pixels, bmi, 0, 0x00CC0020)
        end

        user32.EndPaint(hWnd, ps)
        return 0
    elseif msg == 5 then -- WM_SIZE
        local rc = ffi.new("RECT")
        user32.GetClientRect(hWnd, rc)
        local new_w = tonumber(rc.right)
        local new_h = tonumber(rc.bottom)

        if new_w > 0 and new_h > 0 and (new_w ~= W or new_h ~= H) then
            resize_and_raytrace(new_w, new_h)
        end

        user32.InvalidateRect(hWnd, nil, 0)
        return 0
    elseif msg == 2 then -- WM_DESTROY
        user32.PostQuitMessage(0)
        return 0
    end
    return user32.DefWindowProcW(hWnd, msg, wParam, lParam)
end

local WndProc_C = ffi.cast("LRESULT (*)(HWND, UINT, WPARAM, LPARAM)", WndProc)

local function main()
    print("=== Raytracer (Dynamic Resolution) ===")
    local hInstance = kernel32.GetModuleHandleW(nil)
    local className = wstr("RayCanvas")

    local wc = ffi.new("WNDCLASSEXW")
    wc.cbSize = ffi.sizeof("WNDCLASSEXW")
    wc.style = 0
    wc.lpfnWndProc = WndProc_C
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hInstance
    wc.hIcon = nil
    wc.hCursor = user32.LoadCursorW(nil, ffi.cast("LPCWSTR", 32512))
    wc.hbrBackground = ffi.cast("HBRUSH", 16)
    wc.lpszMenuName = nil
    wc.lpszClassName = className
    wc.hIconSm = nil

    if user32.RegisterClassExW(wc) == 0 then
        print("ERROR: RegisterClassExW")
        return
    end
    print("[OK] Class registered")

    local hwnd = user32.CreateWindowExW(0, className, wstr("Raytracer"),
        0x00CF0000, 100, 100, 640, 480,
        nil, nil, hInstance, nil)
    if hwnd == nil then
        print("ERROR: CreateWindowExW")
        return
    end
    print("[OK] Window created")

    user32.ShowWindow(hwnd, 1)
    user32.UpdateWindow(hwnd)

    print("[OK] Message loop...")
    local msg = ffi.new("MSG")
    while user32.GetMessageW(msg, nil, 0, 0) ~= 0 do
        user32.TranslateMessage(msg)
        user32.DispatchMessageW(msg)
    end
    print("[OK] Exited")
end

main()
