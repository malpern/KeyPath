foreach(secret_name
        KEYPATH_WIFI_SSID_1 KEYPATH_WIFI_PASSWORD_1
        KEYPATH_WIFI_SSID_3 KEYPATH_WIFI_PASSWORD_3
        KEYPATH_WIFI_SSID_4 KEYPATH_WIFI_PASSWORD_4
        KEYPATH_HACKER_DOJO_USERNAME KEYPATH_HACKER_DOJO_PASSWORD
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
set(shared_source "${component_dir}/../../../src")
set(fixture_sources
    "${component_dir}/app_main.c"
    "${component_dir}/fixture_board.c"
    "${component_dir}/fixture_display.c"
    "${component_dir}/fixture_http.c"
    "${component_dir}/fixture_qemu_smoke.c"
    "${component_dir}/fixture_runtime.c"
    "${shared_source}/fixture_button_feedback.c"
    "${shared_source}/fixture_core.c"
    "${shared_source}/fixture_demo.c"
    "${shared_source}/fixture_presentation.c"
    "${shared_source}/fixture_splash_model.c"
    "${shared_source}/fixture_ui_model.c"
    "${shared_source}/fixture_visual_model.c"
    "${shared_source}/fixture_wifi_model.c"
)
file(GLOB fixture_headers
    "${component_dir}/*.h"
    "${shared_source}/*.h"
)
list(SORT fixture_headers)

# Identify the exact source state, including uncommitted work, without embedding secrets.
set(fixture_source_fingerprint "")
foreach(source_path IN LISTS fixture_sources)
    file(SHA256 "${source_path}" source_hash)
    string(APPEND fixture_source_fingerprint "${source_hash}\n")
endforeach()
foreach(header_path IN LISTS fixture_headers)
    file(SHA256 "${header_path}" header_hash)
    string(APPEND fixture_source_fingerprint "${header_hash}\n")
endforeach()
foreach(configuration_path
        "${component_dir}/../sdkconfig.defaults"
        "${component_dir}/../partitions.csv"
        "${component_dir}/CMakeLists.txt"
        "${component_dir}/fixture_config.h.in")
    file(SHA256 "${configuration_path}" configuration_hash)
    string(APPEND fixture_source_fingerprint "${configuration_hash}\n")
endforeach()

# The source hashes are evaluated at configure time. Tell CMake that edits to
# any fingerprinted input must trigger a reconfigure so OTA verification never
# mistakes a newly built image for the previous source revision.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${fixture_sources}
    ${fixture_headers}
)
string(SHA256 fixture_source_hash "${fixture_source_fingerprint}")
string(SUBSTRING "${fixture_source_hash}" 0 12 KEYPATH_FIXTURE_BUILD_ID)

set(generated_dir "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${generated_dir}")
configure_file("${component_dir}/fixture_config.h.in" "${generated_dir}/fixture_config.h" @ONLY)

idf_component_register(
    SRCS ${fixture_sources}
    INCLUDE_DIRS
        "."
        "${shared_source}"
        "${generated_dir}"
    REQUIRES
        app_update
        esp_event
        esp_http_server
        esp_netif
        esp_timer
        esp_wifi
        json
        mbedtls
        mdns
        nvs_flash
        wpa_supplicant
)

target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)

if("$ENV{KEYPATH_QEMU_SMOKE}" STREQUAL "1")
    target_compile_definitions(${COMPONENT_LIB} PRIVATE KEYPATH_QEMU_SMOKE=1)
endif()
