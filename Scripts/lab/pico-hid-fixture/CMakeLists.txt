cmake_minimum_required(VERSION 3.13)

if(NOT DEFINED PICO_SDK_PATH)
  if(DEFINED ENV{PICO_SDK_PATH})
    set(PICO_SDK_PATH "$ENV{PICO_SDK_PATH}")
  else()
    message(FATAL_ERROR "Set PICO_SDK_PATH to a Raspberry Pi Pico SDK checkout")
  endif()
endif()

set(PICO_BOARD pico2_w CACHE STRING "Pico board")
include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(keypath_pico_hid_fixture C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
pico_sdk_init()

foreach(secret_name KEYPATH_WIFI_SSID KEYPATH_WIFI_PASSWORD KEYPATH_FIXTURE_TOKEN)
  if(NOT DEFINED ENV{${secret_name}} OR "$ENV{${secret_name}}" STREQUAL "")
    message(FATAL_ERROR "${secret_name} must be supplied in the build environment")
  endif()
  set(secret_value "$ENV{${secret_name}}")
  string(REPLACE "\\" "\\\\" secret_value "${secret_value}")
  string(REPLACE "\"" "\\\"" secret_value "${secret_value}")
  set(${secret_name}_ESCAPED "${secret_value}")
endforeach()

string(LENGTH "$ENV{KEYPATH_FIXTURE_TOKEN}" fixture_token_length)
if(fixture_token_length LESS 16)
  message(FATAL_ERROR "KEYPATH_FIXTURE_TOKEN must contain at least 16 characters")
endif()

configure_file(src/fixture_config.h.in ${CMAKE_CURRENT_BINARY_DIR}/generated/fixture_config.h @ONLY)

add_executable(keypath_pico_hid_fixture
    src/fixture_core.c
    src/fixture_demo.c
  src/http_server.c
  src/main.c
  src/usb_descriptors.c
)

target_include_directories(keypath_pico_hid_fixture PRIVATE
  src
  ${CMAKE_CURRENT_BINARY_DIR}/generated
)

target_compile_definitions(keypath_pico_hid_fixture PRIVATE
  KEYPATH_FIXTURE_FIRMWARE_VERSION="0.1.0"
)

target_compile_options(keypath_pico_hid_fixture PRIVATE -Wall -Wextra -Werror)
target_link_libraries(keypath_pico_hid_fixture PRIVATE
  pico_stdlib
  pico_unique_id
  pico_cyw43_arch_lwip_poll
  pico_lwip_mdns
  tinyusb_device
  tinyusb_board
  hardware_watchdog
)

pico_enable_stdio_usb(keypath_pico_hid_fixture 0)
pico_enable_stdio_uart(keypath_pico_hid_fixture 0)
pico_add_extra_outputs(keypath_pico_hid_fixture)
