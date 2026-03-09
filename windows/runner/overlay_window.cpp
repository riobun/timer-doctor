#include "overlay_window.h"

#include <algorithm>

static const wchar_t kClassName[] = L"TimerDoctorOverlay";

OverlayWindow* OverlayWindow::instance_ = nullptr;

OverlayWindow::OverlayWindow() {
  instance_ = this;
}

OverlayWindow::~OverlayWindow() {
  if (hwnd_) {
    DestroyWindow(hwnd_);
  }
  instance_ = nullptr;
}

void OverlayWindow::Show(const std::wstring& text) {
  text_ = text;
  if (!hwnd_) Create();
  if (!hwnd_) return;
  ApplyLayout();
  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
}

void OverlayWindow::Hide() {
  if (hwnd_) ShowWindow(hwnd_, SW_HIDE);
}

void OverlayWindow::UpdateText(const std::wstring& text) {
  text_ = text;
  if (hwnd_ && IsWindowVisible(hwnd_)) ApplyLayout();
}

void OverlayWindow::UpdateStyle(double font_size, int64_t text_color,
                                 int64_t bg_color, double bg_opacity) {
  font_size_ = font_size;
  auto tc = static_cast<uint32_t>(text_color);
  auto bc = static_cast<uint32_t>(bg_color);
  text_color_ = RGB((tc >> 16) & 0xFF, (tc >> 8) & 0xFF, tc & 0xFF);
  bg_color_ = RGB((bc >> 16) & 0xFF, (bc >> 8) & 0xFF, bc & 0xFF);
  bg_opacity_ = bg_opacity;
  if (hwnd_ && IsWindowVisible(hwnd_)) ApplyLayout();
}

void OverlayWindow::Create() {
  HINSTANCE hInst = GetModuleHandle(nullptr);

  WNDCLASSEX wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = WndProc;
  wc.hInstance = hInst;
  wc.hCursor = LoadCursor(nullptr, IDC_SIZEALL);
  wc.hbrBackground = nullptr;
  wc.lpszClassName = kClassName;
  RegisterClassEx(&wc);

  int screenW = GetSystemMetrics(SM_CXSCREEN);
  hwnd_ = CreateWindowEx(
      WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClassName, L"", WS_POPUP,
      screenW / 2 - 100, 40, 200, 34,
      nullptr, nullptr, hInst, nullptr);
}

void OverlayWindow::ApplyLayout() {
  if (!hwnd_) return;

  // Measure text size using a temporary DC
  HDC hdc = GetDC(hwnd_);
  int logPixY = GetDeviceCaps(hdc, LOGPIXELSY);
  int ptHeight = -(int)(font_size_ * logPixY / 72.0);
  HFONT hFont = CreateFont(
      ptHeight, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HFONT hOldFont = (HFONT)SelectObject(hdc, hFont);

  SIZE textSize = {};
  if (!text_.empty()) {
    GetTextExtentPoint32W(hdc, text_.c_str(), (int)text_.length(), &textSize);
  }

  SelectObject(hdc, hOldFont);
  DeleteObject(hFont);
  ReleaseDC(hwnd_, hdc);

  const int hPad = 24;
  const int vPad = 10;
  int h = ((int)textSize.cy > 0 ? (int)textSize.cy : 20) + vPad;

  int screenW = GetSystemMetrics(SM_CXSCREEN);
  int maxW = (int)(screenW * 0.88);
  int panelW = (std::min)((int)textSize.cx + hPad, maxW);
  if (panelW < 60) panelW = 60;

  // Keep horizontal position clamped to screen
  RECT rc;
  GetWindowRect(hwnd_, &rc);
  int x = (std::max)(0, (std::min)((int)rc.left, screenW - panelW));
  int y = rc.top;

  // Clear old region before resize
  SetWindowRgn(hwnd_, nullptr, FALSE);
  SetWindowPos(hwnd_, HWND_TOPMOST, x, y, panelW, h, SWP_NOACTIVATE);

  // Pill-shaped clip region
  HRGN rgn = CreateRoundRectRgn(0, 0, panelW + 1, h + 1, h + 1, h + 1);
  SetWindowRgn(hwnd_, rgn, TRUE);

  // Semi-transparent via layered window
  SetLayeredWindowAttributes(hwnd_, 0, (BYTE)(bg_opacity_ * 255), LWA_ALPHA);

  InvalidateRect(hwnd_, nullptr, TRUE);
  UpdateWindow(hwnd_);
}

void OverlayWindow::Paint(HDC hdc) {
  RECT rc;
  GetClientRect(hwnd_, &rc);

  // Background fill
  HBRUSH hBrush = CreateSolidBrush(bg_color_);
  FillRect(hdc, &rc, hBrush);
  DeleteObject(hBrush);

  if (text_.empty()) return;

  int logPixY = GetDeviceCaps(hdc, LOGPIXELSY);
  int ptHeight = -(int)(font_size_ * logPixY / 72.0);
  HFONT hFont = CreateFont(
      ptHeight, 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HFONT hOldFont = (HFONT)SelectObject(hdc, hFont);

  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, text_color_);

  // Center text; clip with ellipsis if too wide
  DrawTextW(hdc, text_.c_str(), -1, &rc,
            DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_END_ELLIPSIS);

  SelectObject(hdc, hOldFont);
  DeleteObject(hFont);
}

LRESULT CALLBACK OverlayWindow::WndProc(HWND hwnd, UINT msg, WPARAM wParam,
                                         LPARAM lParam) {
  switch (msg) {
    case WM_PAINT: {
      if (instance_) {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        instance_->Paint(hdc);
        EndPaint(hwnd, &ps);
      }
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_NCHITTEST:
      return HTCAPTION;  // entire window is draggable
    case WM_DESTROY:
      if (instance_) instance_->hwnd_ = nullptr;
      return 0;
    default:
      return DefWindowProc(hwnd, msg, wParam, lParam);
  }
}
