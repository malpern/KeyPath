#!/usr/bin/env python3

import ctypes
import os
import sys


def main() -> int:
    if len(sys.argv) not in (2, 3, 4):
        print(
            "usage: verify-kanata-host-bridge.py <bridge-dylib-path> [config-path] [--passthru]",
            file=sys.stderr,
        )
        return 2

    enable_passthru = "--passthru" in sys.argv[2:]
    config_arg = next((arg for arg in sys.argv[2:] if arg != "--passthru"), None)
    if enable_passthru and config_arg is None:
        print("--passthru requires a config path", file=sys.stderr)
        return 2

    dylib_path = sys.argv[1]
    if not os.path.isfile(dylib_path):
        print(f"missing bridge dylib: {dylib_path}", file=sys.stderr)
        return 1

    try:
        bridge = ctypes.CDLL(dylib_path)
    except OSError as exc:
        print(f"failed to load bridge dylib: {exc}", file=sys.stderr)
        return 1

    bridge.keypath_kanata_bridge_version.restype = ctypes.c_char_p
    bridge.keypath_kanata_bridge_default_cfg_count.restype = ctypes.c_size_t
    bridge.keypath_kanata_bridge_validate_config.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]
    bridge.keypath_kanata_bridge_validate_config.restype = ctypes.c_bool
    bridge.keypath_kanata_bridge_create_runtime.argtypes = [
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_size_t,
    ]
    bridge.keypath_kanata_bridge_create_runtime.restype = ctypes.c_void_p
    bridge.keypath_kanata_bridge_runtime_layer_count.argtypes = [ctypes.c_void_p]
    bridge.keypath_kanata_bridge_runtime_layer_count.restype = ctypes.c_size_t
    bridge.keypath_kanata_bridge_destroy_runtime.argtypes = [ctypes.c_void_p]
    bridge.keypath_kanata_bridge_destroy_runtime.restype = None

    version = bridge.keypath_kanata_bridge_version()
    default_cfg_count = bridge.keypath_kanata_bridge_default_cfg_count()

    version_text = version.decode("utf-8") if version else "<null>"
    print(f"bridge version: {version_text}")
    print(f"default cfg count: {default_cfg_count}")

    # Resolve the full session ABI before any creation. Feature-disabled builds
    # export create/start stubs, but omit the session input-map function.
    if enable_passthru:
        try:
            for name in (
                "create_passthru_runtime", "passthru_runtime_layer_count",
                "start_passthru_runtime", "passthru_send_input",
                "passthru_try_recv_output", "destroy_passthru_runtime",
                "passthru_is_input_mapped",
            ):
                getattr(bridge, "keypath_kanata_bridge_" + name)
        except AttributeError as exc:
            print(f"passthru symbols unavailable: {exc}", file=sys.stderr)
            return 1

    if config_arg is not None:
        error_buffer = ctypes.create_string_buffer(2048)
        config_path = config_arg.encode("utf-8")
        valid = bridge.keypath_kanata_bridge_validate_config(
            config_path,
            error_buffer,
            len(error_buffer),
        )
        print(f"config valid: {valid}")
        if not valid:
            print(f"config error: {error_buffer.value.decode('utf-8')}")
            return 1
        else:
            runtime_error = ctypes.create_string_buffer(2048)
            runtime = bridge.keypath_kanata_bridge_create_runtime(
                config_path,
                runtime_error,
                len(runtime_error),
            )
            print(f"runtime created: {bool(runtime)}")
            if runtime:
                print(f"runtime layer count: {bridge.keypath_kanata_bridge_runtime_layer_count(runtime)}")
                bridge.keypath_kanata_bridge_destroy_runtime(runtime)
            else:
                print(f"runtime error: {runtime_error.value.decode('utf-8')}")
                return 1

        if enable_passthru:
            try:
                bridge.keypath_kanata_bridge_create_passthru_runtime.argtypes = [
                    ctypes.c_char_p,
                    ctypes.c_ushort,
                    ctypes.c_char_p,
                    ctypes.c_size_t,
                ]
                bridge.keypath_kanata_bridge_create_passthru_runtime.restype = ctypes.c_void_p
                bridge.keypath_kanata_bridge_passthru_runtime_layer_count.argtypes = [ctypes.c_void_p]
                bridge.keypath_kanata_bridge_passthru_runtime_layer_count.restype = ctypes.c_size_t
                bridge.keypath_kanata_bridge_passthru_try_recv_output.argtypes = [
                    ctypes.c_void_p,
                    ctypes.POINTER(ctypes.c_ulonglong),
                    ctypes.POINTER(ctypes.c_uint),
                    ctypes.POINTER(ctypes.c_uint),
                    ctypes.c_char_p,
                    ctypes.c_size_t,
                ]
                bridge.keypath_kanata_bridge_passthru_try_recv_output.restype = ctypes.c_int
                bridge.keypath_kanata_bridge_destroy_passthru_runtime.argtypes = [ctypes.c_void_p]
                bridge.keypath_kanata_bridge_destroy_passthru_runtime.restype = None
            except AttributeError as exc:
                print(f"passthru symbols unavailable: {exc}")
                return 1
            else:
                passthru_error = ctypes.create_string_buffer(2048)
                passthru_runtime = bridge.keypath_kanata_bridge_create_passthru_runtime(
                    config_path,
                    0,
                    passthru_error,
                    len(passthru_error),
                )
                print(f"passthru runtime created: {bool(passthru_runtime)}")
                if passthru_runtime:
                    print(
                        "passthru runtime layer count: "
                        f"{bridge.keypath_kanata_bridge_passthru_runtime_layer_count(passthru_runtime)}"
                    )
                    value_out = ctypes.c_ulonglong()
                    page_out = ctypes.c_uint()
                    code_out = ctypes.c_uint()
                    recv_error = ctypes.create_string_buffer(2048)
                    recv_status = bridge.keypath_kanata_bridge_passthru_try_recv_output(
                        passthru_runtime,
                        ctypes.byref(value_out),
                        ctypes.byref(page_out),
                        ctypes.byref(code_out),
                        recv_error,
                        len(recv_error),
                    )
                    print(f"passthru receive status: {recv_status}")
                    if recv_status == 1:
                        print(
                            "passthru output event: "
                            f"value={value_out.value} page={page_out.value} code={code_out.value}"
                        )
                    elif recv_status < 0:
                        print(f"passthru receive error: {recv_error.value.decode('utf-8')}")
                    bridge.keypath_kanata_bridge_destroy_passthru_runtime(passthru_runtime)
                    if recv_status < 0:
                        return 1
                else:
                    print(f"passthru runtime error: {passthru_error.value.decode('utf-8')}")
                    return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
