foreach(secret_name
        KEYPATH_WIFI_SSID_1 KEYPATH_WIFI_PASSWORD_1
        KEYPATH_WIFI_SSID_2 KEYPATH_WIFI_PASSWORD_2
        KEYPATH_WIFI_SSID_3 KEYPATH_WIFI_PASSWORD_3
        KEYPATH_FIXTURE_TOKEN)
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

get_filename_component(component_dir "${CMAKE_CURRENT_LIST_FILE}" DIRECTORY)
execute_process(
    COMMAND git -C "${component_dir}" rev-parse --short=12 HEAD
    OUTPUT_VARIABLE KEYPATH_FIXTURE_BUILD_ID
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(KEYPATH_FIXTURE_BUILD_ID STREQUAL "")
    set(KEYPATH_FIXTURE_BUILD_ID "unknown")
endif()
set(shared_source "${component_dir}/../../../src")
set(generated_dir "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${generated_dir}")
configure_file("${component_dir}/fixture_config.h.in" "${generated_dir}/fixture_config.h" @ONLY)

idf_component_register(
    SRCS
        "app_main.c"
        "fixture_board.c"
        "fixture_display.c"
        "fixture_http.c"
        "fixture_qemu_smoke.c"
        "fixture_runtime.c"
        "${shared_source}/fixture_core.c"
        "${shared_source}/fixture_presentation.c"
        "${shared_source}/fixture_splash_model.c"
        "${shared_source}/fixture_ui_model.c"
        "${shared_source}/fixture_visual_model.c"
        "${shared_source}/fixture_wifi_model.c"
    INCLUDE_DIRS
        "."
        "${shared_source}"
        "${generated_dir}"
    REQUIRES
        esp_event
        esp_http_server
        esp_netif
        esp_timer
        esp_wifi
        json
        mdns
        nvs_flash
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)

if("$ENV{KEYPATH_QEMU_SMOKE}" STREQUAL "1")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE KEYPATH_QEMU_SMOKE=1)
endif()
