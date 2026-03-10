#ifndef KEYPATH_KANATA_HOST_BRIDGE_H
#define KEYPATH_KANATA_HOST_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *keypath_kanata_bridge_version(void);
size_t keypath_kanata_bridge_default_cfg_count(void);
bool keypath_kanata_bridge_validate_config(const char *config_path, char *error_buffer, size_t error_buffer_len);
void *keypath_kanata_bridge_create_runtime(const char *config_path, char *error_buffer, size_t error_buffer_len);
bool keypath_kanata_bridge_run_runtime(const char *config_path, unsigned short tcp_port, char *error_buffer, size_t error_buffer_len);
bool keypath_kanata_bridge_initialize_output_sink(char *error_buffer, size_t error_buffer_len);
bool keypath_kanata_bridge_output_ready(void);
bool keypath_kanata_bridge_wait_until_output_ready(unsigned long long timeout_millis);
bool keypath_kanata_bridge_emit_key(unsigned int usage_page, unsigned int usage, bool is_key_down, char *error_buffer, size_t error_buffer_len);
size_t keypath_kanata_bridge_runtime_layer_count(const void *runtime);
void keypath_kanata_bridge_destroy_runtime(void *runtime);
void *keypath_kanata_bridge_create_passthru_runtime(const char *config_path, unsigned short tcp_port, char *error_buffer, size_t error_buffer_len);
size_t keypath_kanata_bridge_passthru_runtime_layer_count(const void *runtime);
bool keypath_kanata_bridge_start_passthru_runtime(void *runtime, char *error_buffer, size_t error_buffer_len);
bool keypath_kanata_bridge_passthru_send_input(void *runtime, unsigned long long value, unsigned int page, unsigned int code, char *error_buffer, size_t error_buffer_len);
int keypath_kanata_bridge_passthru_try_recv_output(void *runtime, unsigned long long *value_out, unsigned int *page_out, unsigned int *code_out, char *error_buffer, size_t error_buffer_len);
void keypath_kanata_bridge_destroy_passthru_runtime(void *runtime);

#ifdef __cplusplus
}
#endif

#endif
