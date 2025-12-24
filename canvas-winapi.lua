#!/usr/bin/env luajit
-- canvas.lua - Simple 2D canvas with rectangle drawing
-- Run: wine luajit.exe canvas.lua

local ffi = require "ffi"

ffi.cdef [[
  typedef void* HINSTANCE;
  typedef void* HWND;
  typedef void* HDC;
  typedef void* HBRUSH;
  typedef void* HPEN;
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
  BOOL Rectangle(HDC, INT, INT, INT, INT);
  HBRUSH CreateSolidBrush(ULONG);
  HPEN CreatePen(INT, INT, ULONG);
  void* SelectObject(HDC, void*);
  BOOL DeleteObject(void*);
  BOOL GetClientRect(HWND, RECT*);
  typedef void* HCURSOR;
  HCURSOR LoadCursorW(HINSTANCE, LPCWSTR);
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

local function WndProc(hWnd, msg, wParam, lParam)
    if msg == 15 then -- WM_PAINT
        local ps = ffi.new("PAINTSTRUCT")
        local hdc = user32.BeginPaint(hWnd, ps)

        -- Create red brush and pen
        local hBrush = gdi32.CreateSolidBrush(0x000000FF) -- RGB(255, 0, 0) = red
        local hPen = gdi32.CreatePen(0, 2, 0x00000000)    -- PS_SOLID, black border

        local oldBrush = gdi32.SelectObject(hdc, hBrush)
        local oldPen = gdi32.SelectObject(hdc, hPen)

        -- Draw rectangle from (50, 50) to (250, 200)
        gdi32.Rectangle(hdc, 50, 50, 250, 200)

        -- Restore and cleanup
        gdi32.SelectObject(hdc, oldBrush)
        gdi32.SelectObject(hdc, oldPen)
        gdi32.DeleteObject(hBrush)
        gdi32.DeleteObject(hPen)

        user32.EndPaint(hWnd, ps)
        return 0
    elseif msg == 256 then     -- WM_KEYDOWN
        if wParam == 0x1B then -- VK_ESCAPE
            user32.PostQuitMessage(0)
            return 0
        end
    elseif msg == 2 then -- WM_DESTROY
        user32.PostQuitMessage(0)
        return 0
    end
    return user32.DefWindowProcW(hWnd, msg, wParam, lParam)
end

local WndProc_C = ffi.cast("LRESULT (*)(HWND, UINT, WPARAM, LPARAM)", WndProc)

local function main()
    print("=== 2D Canvas - Rectangle Demo ===")
    local hInstance = kernel32.GetModuleHandleW(nil)
    local className = wstr("CanvasClass")

    local wc = ffi.new("WNDCLASSEXW")
    wc.cbSize = ffi.sizeof("WNDCLASSEXW")
    wc.style = 0
    wc.lpfnWndProc = WndProc_C
    wc.cbClsExtra = 0
    wc.cbWndExtra = 0
    wc.hInstance = hInstance
    wc.hIcon = nil
    wc.hCursor = user32.LoadCursorW(nil, ffi.cast("LPCWSTR", 32512)) -- IDC_ARROW
    wc.hbrBackground = ffi.cast("HBRUSH", 6)                         -- WHITE_BRUSH
    wc.lpszMenuName = nil
    wc.lpszClassName = className
    wc.hIconSm = nil

    if user32.RegisterClassExW(wc) == 0 then
        print("ERROR: RegisterClassExW")
        return
    end
    print("[OK] Class registered")

    local hwnd = user32.CreateWindowExW(0, className, wstr("2D Canvas"), 0x00CF0000, 100, 100, 400, 300, nil, nil,
        hInstance, nil)
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
