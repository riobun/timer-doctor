#ifndef RUNNER_OVERLAY_WINDOW_H_
#define RUNNER_OVERLAY_WINDOW_H_

#include <windows.h>
#include <cstdint>
#include <string>

class OverlayWindow {
 public:
  OverlayWindow();
  ~OverlayWindow();

  void Show(const std::wstring& text);
  void Hide();
  void UpdateText(const std::wstring& text);
  void UpdateStyle(double font_size, int64_t text_color, int64_t bg_color,
                   double bg_opacity);

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam,
                                   LPARAM lParam);
  void Create();
  void ApplyLayout();
  void Paint(HDC hdc);

  HWND hwnd_ = nullptr;
  std::wstring text_;
  double font_size_ = 14.0;
  COLORREF text_color_ = RGB(255, 255, 255);
  COLORREF bg_color_ = RGB(20, 20, 20);
  double bg_opacity_ = 0.5;

  static OverlayWindow* instance_;
};

#endif  // RUNNER_OVERLAY_WINDOW_H_
