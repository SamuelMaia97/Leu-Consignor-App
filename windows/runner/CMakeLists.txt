cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard settings from the top-level CMakeLists.txt.
apply_standard_settings(${BINARY_NAME})

# Avoid Windows min/max macro conflicts with C++ standard library code.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Link against Flutter and Windows libraries used by the generated runner.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Ensure Flutter assets and generated files are assembled before the runner.
add_dependencies(${BINARY_NAME} flutter_assemble)
