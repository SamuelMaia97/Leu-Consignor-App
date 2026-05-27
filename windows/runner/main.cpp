#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kAppProtocolScheme[] = L"leuconsignor";

void SetRegistryStringValue(HKEY key, const wchar_t* name,
                            const std::wstring& value) {
  const DWORD size_bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  RegSetValueExW(key, name, 0, REG_SZ,
                 reinterpret_cast<const BYTE*>(value.c_str()), size_bytes);
}

void RegisterAppProtocolHandler() {
  wchar_t executable_path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }

  const std::wstring scheme_key =
      std::wstring(L"Software\\Classes\\") + kAppProtocolScheme;
  HKEY root_key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, scheme_key.c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE | KEY_CREATE_SUB_KEY, nullptr, &root_key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }

  SetRegistryStringValue(root_key, nullptr, L"URL:Leu Consignor App Protocol");
  SetRegistryStringValue(root_key, L"URL Protocol", L"");

  HKEY command_key = nullptr;
  const std::wstring command_subkey = scheme_key + L"\\shell\\open\\command";
  if (RegCreateKeyExW(HKEY_CURRENT_USER, command_subkey.c_str(), 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &command_key,
                      nullptr) == ERROR_SUCCESS) {
    const std::wstring command =
        std::wstring(L"\"") + executable_path + L"\" \"%1\"";
    SetRegistryStringValue(command_key, nullptr, command);
    RegCloseKey(command_key);
  }

  RegCloseKey(root_key);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Attach to console when present, useful for `flutter run` and diagnostics.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so plugins can use it safely.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  RegisterAppProtocolHandler();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  std::vector<std::string> sanitized_arguments;
  sanitized_arguments.reserve(command_line_arguments.size());
  bool protocol_callback_launch = false;

  for (const std::string& arg : command_line_arguments) {
    // Ignore custom protocol callback URIs so they don't become unexpected
    // startup arguments/routes inside Flutter.
    if (arg.rfind("leuconsignor://", 0) == 0) {
      protocol_callback_launch = true;
      continue;
    }
    sanitized_arguments.push_back(arg);
  }

  if (protocol_callback_launch && sanitized_arguments.empty()) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  project.set_dart_entrypoint_arguments(std::move(sanitized_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Leu Consignor App", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
