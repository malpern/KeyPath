#!/usr/bin/env python3
"""Exercise parsed session eligibility and memory-only Kanata output; no OS tap."""
import ctypes
import json
from pathlib import Path
import re
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[3]
library = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build/kanata-host-bridge/libkeypath_kanata_host_bridge.dylib"
bridge = ctypes.CDLL(str(library))
char_buffer = ctypes.POINTER(ctypes.c_char)
bridge.keypath_kanata_bridge_validate_config.argtypes = [ctypes.c_char_p, char_buffer, ctypes.c_size_t]
bridge.keypath_kanata_bridge_validate_config.restype = ctypes.c_bool
bridge.keypath_kanata_bridge_validate_session_config.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint32), ctypes.c_size_t, char_buffer, ctypes.c_size_t]
bridge.keypath_kanata_bridge_validate_session_config.restype = ctypes.c_bool
bridge.keypath_kanata_bridge_create_passthru_runtime.argtypes = [ctypes.c_char_p, ctypes.c_uint16, char_buffer, ctypes.c_size_t]
bridge.keypath_kanata_bridge_create_passthru_runtime.restype = ctypes.c_void_p
bridge.keypath_kanata_bridge_start_passthru_runtime.argtypes = [ctypes.c_void_p, char_buffer, ctypes.c_size_t]
bridge.keypath_kanata_bridge_start_passthru_runtime.restype = ctypes.c_bool
bridge.keypath_kanata_bridge_passthru_is_input_mapped.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
bridge.keypath_kanata_bridge_passthru_is_input_mapped.restype = ctypes.c_bool
bridge.keypath_kanata_bridge_passthru_send_input.argtypes = [ctypes.c_void_p, ctypes.c_uint64, ctypes.c_uint32, ctypes.c_uint32, char_buffer, ctypes.c_size_t]
bridge.keypath_kanata_bridge_passthru_send_input.restype = ctypes.c_bool
bridge.keypath_kanata_bridge_passthru_try_recv_output.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_uint32), ctypes.POINTER(ctypes.c_uint32), char_buffer, ctypes.c_size_t]
bridge.keypath_kanata_bridge_passthru_try_recv_output.restype = ctypes.c_int32
bridge.keypath_kanata_bridge_destroy_passthru_runtime.argtypes = [ctypes.c_void_p]
bridge.keypath_kanata_bridge_destroy_passthru_runtime.restype = None

mapping = (root / "Sources/KeyPathCore/SessionRuntime/SessionKeyMap.swift").read_text().split("keyCodeToUsage:", 1)[1].split("\n    ]", 1)[0]
usages = sorted({int(value) for value in re.findall(r"\d+:\s*(\d+)", mapping)} - {57})
allowed = (ctypes.c_uint32 * len(usages))(*usages)
cases = {
    "single_mapping": ("(defsrc q)(deflayer base a)", True),
    "process_unmapped": ("(defcfg process-unmapped-keys yes)(defsrc q a)(deflayer base a a)", True),
    "home_row_modifier": ("(defsrc q a)(defalias hrm (tap-hold 200 300 q lctl))(deflayer base @hrm a)", True),
    "layer_modifier": ("(defsrc q a)(deflayer base (layer-while-held nav) a)(deflayer nav q left)", True),
    "macro": ("(defsrc q)(deflayer base (macro a b c))", True),
    "caps_remap": ("(defsrc caps)(deflayer base esc)", False),
    "caps_output": ("(defsrc q)(deflayer base caps)", False),
    "consumer_output": ("(defsrc q)(deflayer base volu)", False),
    "mouse_output": ("(defsrc q)(deflayer base mlft)", False),
    "unicode_output": ("(defsrc q)(deflayer base (unicode ä))", False),
    "device_filter": ('(defcfg macos-dev-names-include ("Keyboard"))(defsrc q)(deflayer base a)', False),
}
results = {}
with tempfile.TemporaryDirectory(prefix="keypath-session-bridge-") as directory:
    for name, (config, expected) in cases.items():
        path = Path(directory) / (name + ".kbd")
        path.write_text(config)
        error = ctypes.create_string_buffer(2048)
        valid = bridge.keypath_kanata_bridge_validate_config(str(path).encode(), error, len(error))
        eligible = bridge.keypath_kanata_bridge_validate_session_config(str(path).encode(), allowed, len(allowed), error, len(error))
        results[name] = {"kanataValid": valid, "eligible": eligible, "expected": expected, "passed": valid and eligible == expected}

    path = Path(directory) / "single_mapping.kbd"
    error = ctypes.create_string_buffer(2048)
    runtime = bridge.keypath_kanata_bridge_create_passthru_runtime(str(path).encode(), 0, error, len(error))
    mapped_q = bridge.keypath_kanata_bridge_passthru_is_input_mapped(7, 20)
    unmapped_a = not bridge.keypath_kanata_bridge_passthru_is_input_mapped(7, 4)
    started = runtime and bridge.keypath_kanata_bridge_start_passthru_runtime(runtime, error, len(error))
    emitted = []
    if started:
        for value in [1, 0]:
            assert bridge.keypath_kanata_bridge_passthru_send_input(runtime, value, 7, 20, error, len(error))
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and len(emitted) < 2:
            value, page, usage = ctypes.c_uint64(), ctypes.c_uint32(), ctypes.c_uint32()
            status = bridge.keypath_kanata_bridge_passthru_try_recv_output(runtime, ctypes.byref(value), ctypes.byref(page), ctypes.byref(usage), error, len(error))
            if status == 1:
                emitted.append([value.value, page.value, usage.value])
            elif status < 0:
                break
            else:
                time.sleep(0.005)
    if runtime:
        bridge.keypath_kanata_bridge_destroy_passthru_runtime(runtime)
    results["memory_engine"] = {"mappedQ": mapped_q, "unmappedA": unmapped_a,
                                "passed": bool(started and mapped_q and unmapped_a and emitted == [[1, 7, 4], [0, 7, 4]])}

print(json.dumps({"osEventCapture": False, "osEventPosting": False, "cases": results,
                  "passed": all(case["passed"] for case in results.values())}, indent=2))
sys.exit(0 if all(case["passed"] for case in results.values()) else 1)
