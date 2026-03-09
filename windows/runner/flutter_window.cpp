#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include <flutter/method_result_functions.h>

// ── helpers ──────────────────────────────────────────────────────────────────

static std::wstring ToWide(const std::string& utf8) {
  if (utf8.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, nullptr, 0);
  std::wstring result(n - 1, 0);
  MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), -1, &result[0], n);
  return result;
}

static std::string GetStr(const flutter::EncodableMap& m,
                           const std::string& key) {
  auto it = m.find(flutter::EncodableValue(key));
  if (it != m.end()) {
    if (auto* s = std::get_if<std::string>(&it->second)) return *s;
  }
  return {};
}

static double GetDouble(const flutter::EncodableMap& m, const std::string& key,
                        double def) {
  auto it = m.find(flutter::EncodableValue(key));
  if (it != m.end()) {
    if (auto* d = std::get_if<double>(&it->second)) return *d;
  }
  return def;
}

// Colors arrive as int64 when ARGB value exceeds INT32_MAX (i.e. alpha=0xFF).
static int64_t GetInt64(const flutter::EncodableMap& m, const std::string& key,
                        int64_t def) {
  auto it = m.find(flutter::EncodableValue(key));
  if (it != m.end()) {
    if (auto* i = std::get_if<int32_t>(&it->second))
      return static_cast<int64_t>(static_cast<uint32_t>(*i));
    if (auto* i = std::get_if<int64_t>(&it->second)) return *i;
  }
  return def;
}

// ── FlutterWindow ─────────────────────────────────────────────────────────────

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // ── overlay setup ──────────────────────────────────────────────────────────
  overlay_window_ = std::make_unique<OverlayWindow>();

  overlay_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "timer_doctor/overlay",
          &flutter::StandardMethodCodec::GetInstance());

  overlay_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        flutter::EncodableMap empty;
        const auto* raw =
            std::get_if<flutter::EncodableMap>(call.arguments());
        const auto& args = raw ? *raw : empty;
        const std::string& method = call.method_name();

        if (method == "show") {
          overlay_window_->Show(ToWide(GetStr(args, "text")));
          result->Success();
        } else if (method == "hide") {
          overlay_window_->Hide();
          result->Success();
        } else if (method == "updateText") {
          overlay_window_->UpdateText(ToWide(GetStr(args, "text")));
          result->Success();
        } else if (method == "updateStyle") {
          double fs = GetDouble(args, "fontSize", 14.0);
          int64_t tc = GetInt64(args, "textColor", 0xFFFFFFFF);
          int64_t bc = GetInt64(args, "bgColor", 0xFF141414);
          double bo = GetDouble(args, "bgOpacity", 0.5);
          overlay_window_->UpdateStyle(fs, tc, bc, bo);
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  // ── end overlay setup ──────────────────────────────────────────────────────

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  overlay_channel_.reset();
  overlay_window_.reset();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
