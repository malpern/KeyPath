use std::ffi::{c_char, c_void, CStr};
use std::path::{Path, PathBuf};
use std::str::FromStr;

#[cfg(feature = "passthru-output-spike")]
use std::sync::atomic::{AtomicBool, Ordering};
#[cfg(feature = "passthru-output-spike")]
use std::sync::mpsc::SyncSender;
#[cfg(feature = "passthru-output-spike")]
use std::sync::mpsc::{self, Receiver};
#[cfg(feature = "passthru-output-spike")]
use std::sync::Arc;

const BRIDGE_VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();

#[cfg(target_os = "macos")]
mod session_config;

/// Validate the supported session profile using Kanata's actual parsed action
/// tree. The host supplies its key map, so this cannot drift from CG translation.
#[cfg(target_os = "macos")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_validate_session_config(
    config_path: *const c_char,
    supported_usages: *const u32,
    supported_count: usize,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    let Some(path) = parse_config_path(config_path, error_buffer, error_buffer_len) else {
        return false;
    };
    if supported_usages.is_null() || supported_count == 0 || supported_count > 512 {
        write_error(error_buffer, error_buffer_len, "invalid session key map");
        return false;
    }
    let usages = unsafe { std::slice::from_raw_parts(supported_usages, supported_count) };
    match kanata_parser::cfg::new_from_file(Path::new(&path)) {
        Ok(cfg) if session_config::supported(&cfg, usages) => {
            write_error(error_buffer, error_buffer_len, "");
            true
        }
        Ok(_) => {
            write_error(error_buffer, error_buffer_len, "configuration requires the advanced driver backend (device filters, Caps Lock remapping, unsupported keys or actions)");
            false
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "configuration could not be parsed by Kanata",
            );
            false
        }
    }
}

/// Additive admission API. supported_usages is the OUTPUT key map; managed Caps
/// supplies logical HID 57 input without authorizing Caps Lock or F18 output.
#[cfg(target_os = "macos")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_validate_session_config_with_managed_caps(
    config_path: *const c_char,
    supported_usages: *const u32,
    supported_count: usize,
    managed_caps: bool,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    let Some(path) = parse_config_path(config_path, error_buffer, error_buffer_len) else {
        return false;
    };
    if supported_usages.is_null() || supported_count == 0 || supported_count > 512 {
        write_error(error_buffer, error_buffer_len, "invalid session key map");
        return false;
    }
    let usages = unsafe { std::slice::from_raw_parts(supported_usages, supported_count) };
    match kanata_parser::cfg::new_from_file(Path::new(&path)) {
        Ok(cfg)
            if if managed_caps {
                session_config::supported_with_managed_caps(&cfg, usages)
            } else {
                session_config::supported(&cfg, usages)
            } =>
        {
            write_error(error_buffer, error_buffer_len, "");
            true
        }
        Ok(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                if managed_caps {
                    "configuration is unsafe for managed Caps Lock (Caps/F18 output, reserved input, unresolved source/repeat, overrides/chords, or unsupported keys/actions)"
                } else {
                    "configuration requires the advanced driver backend (device filters, Caps Lock remapping, unsupported keys or actions)"
                },
            );
            false
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "configuration could not be parsed by Kanata",
            );
            false
        }
    }
}

#[cfg(target_os = "macos")]
unsafe extern "C" {
    #[link_name = "\u{1}__Z9init_sinkv"]
    fn keypath_driverkit_init_sink() -> i32;
}

#[cfg(feature = "passthru-output-spike")]
struct PassthruRuntime {
    runtime: Arc<parking_lot::Mutex<kanata_state_machine::Kanata>>,
    output_rx: Receiver<kanata_state_machine::oskbd::InputEvent>,
    processing_tx: parking_lot::Mutex<Option<SyncSender<kanata_state_machine::oskbd::KeyEvent>>>,
    tcp_server_address: Option<kanata_state_machine::SocketAddrWrapper>,
    started: AtomicBool,
}

#[cfg(all(feature = "passthru-output-spike", target_os = "macos"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_is_input_mapped(page: u32, code: u32) -> bool {
    use kanata_parser::keys::{OsCode, PageCode};
    OsCode::try_from(PageCode { page, code }).is_ok_and(kanata_state_machine::is_mapped_input)
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_version() -> *const c_char {
    BRIDGE_VERSION.as_ptr().cast()
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_default_cfg_count() -> usize {
    kanata_state_machine::default_cfg().len()
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_validate_config(
    config_path: *const c_char,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    let path = match parse_config_path(config_path, error_buffer, error_buffer_len) {
        Some(path) => path,
        None => return false,
    };

    match kanata_parser::cfg::new_from_file(Path::new(&path)) {
        Ok(_) => {
            write_error(error_buffer, error_buffer_len, "");
            true
        }
        Err(error) => {
            write_error(error_buffer, error_buffer_len, &error.to_string());
            false
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_create_runtime(
    config_path: *const c_char,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> *mut c_void {
    let path = match parse_config_path(config_path, error_buffer, error_buffer_len) {
        Some(path) => path,
        None => return std::ptr::null_mut(),
    };

    let args = kanata_state_machine::ValidatedArgs {
        paths: vec![PathBuf::from(path)],
        tcp_server_address: None,
        nodelay: true,
    };

    match kanata_state_machine::Kanata::new(&args) {
        Ok(runtime) => {
            write_error(error_buffer, error_buffer_len, "");
            Box::into_raw(Box::new(runtime)).cast()
        }
        Err(error) => {
            write_error(error_buffer, error_buffer_len, &error.to_string());
            std::ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_runtime_layer_count(runtime: *const c_void) -> usize {
    if runtime.is_null() {
        return 0;
    }

    let runtime = unsafe { &*(runtime.cast::<kanata_state_machine::Kanata>()) };
    runtime.layer_info.len()
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_destroy_runtime(runtime: *mut c_void) {
    if runtime.is_null() {
        return;
    }

    unsafe {
        drop(Box::from_raw(
            runtime.cast::<kanata_state_machine::Kanata>(),
        ));
    }
}

#[cfg(feature = "passthru-output-spike")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_create_passthru_runtime(
    config_path: *const c_char,
    tcp_port: u16,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> *mut c_void {
    let path = match parse_config_path(config_path, error_buffer, error_buffer_len) {
        Some(path) => path,
        None => return std::ptr::null_mut(),
    };

    let tcp_server_address = if tcp_port == 0 {
        None
    } else {
        match kanata_state_machine::SocketAddrWrapper::from_str(&tcp_port.to_string()) {
            Ok(address) => Some(address),
            Err(error) => {
                write_error(error_buffer, error_buffer_len, &error.to_string());
                return std::ptr::null_mut();
            }
        }
    };

    let args = kanata_state_machine::ValidatedArgs {
        paths: vec![PathBuf::from(path)],
        tcp_server_address: tcp_server_address.clone(),
        nodelay: true,
    };

    let (tx_kout, rx_kout) = mpsc::channel();
    match kanata_state_machine::Kanata::new_with_output_channel(&args, Some(tx_kout)) {
        Ok(runtime) => {
            write_error(error_buffer, error_buffer_len, "");
            Box::into_raw(Box::new(PassthruRuntime {
                runtime,
                output_rx: rx_kout,
                processing_tx: parking_lot::Mutex::new(None),
                tcp_server_address,
                started: AtomicBool::new(false),
            }))
            .cast()
        }
        Err(error) => {
            write_error(error_buffer, error_buffer_len, &error.to_string());
            std::ptr::null_mut()
        }
    }
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_create_passthru_runtime(
    _config_path: *const c_char,
    _tcp_port: u16,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> *mut c_void {
    write_error(
        error_buffer,
        error_buffer_len,
        "passthru output spike feature is not enabled in this bridge build",
    );
    std::ptr::null_mut()
}

#[cfg(feature = "passthru-output-spike")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_destroy_passthru_runtime(runtime: *mut c_void) {
    if runtime.is_null() {
        return;
    }

    unsafe {
        drop(Box::from_raw(runtime.cast::<PassthruRuntime>()));
    }
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_destroy_passthru_runtime(_runtime: *mut c_void) {}

#[cfg(feature = "passthru-output-spike")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_runtime_layer_count(
    runtime: *const c_void,
) -> usize {
    if runtime.is_null() {
        return 0;
    }

    let runtime = unsafe { &*(runtime.cast::<PassthruRuntime>()) };
    runtime.runtime.lock().layer_info.len()
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_runtime_layer_count(
    _runtime: *const c_void,
) -> usize {
    0
}

#[cfg(feature = "passthru-output-spike")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_try_recv_output(
    runtime: *mut c_void,
    value_out: *mut u64,
    page_out: *mut u32,
    code_out: *mut u32,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> i32 {
    if runtime.is_null() {
        write_error(
            error_buffer,
            error_buffer_len,
            "passthru runtime handle was null",
        );
        return -1;
    }

    let runtime = unsafe { &*(runtime.cast::<PassthruRuntime>()) };
    match runtime.output_rx.try_recv() {
        Ok(event) => {
            if !value_out.is_null() {
                unsafe {
                    *value_out = event.value;
                }
            }
            if !page_out.is_null() {
                unsafe {
                    *page_out = event.page;
                }
            }
            if !code_out.is_null() {
                unsafe {
                    *code_out = event.code;
                }
            }
            write_error(error_buffer, error_buffer_len, "");
            1
        }
        Err(mpsc::TryRecvError::Empty) => {
            write_error(error_buffer, error_buffer_len, "");
            0
        }
        Err(mpsc::TryRecvError::Disconnected) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "passthru output channel disconnected",
            );
            -1
        }
    }
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_try_recv_output(
    _runtime: *mut c_void,
    _value_out: *mut u64,
    _page_out: *mut u32,
    _code_out: *mut u32,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> i32 {
    write_error(
        error_buffer,
        error_buffer_len,
        "passthru output spike feature is not enabled in this bridge build",
    );
    -1
}

#[cfg(feature = "passthru-output-spike")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_start_passthru_runtime(
    runtime: *mut c_void,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    if runtime.is_null() {
        write_error(
            error_buffer,
            error_buffer_len,
            "passthru runtime handle was null",
        );
        return false;
    }

    let runtime = unsafe { &*(runtime.cast::<PassthruRuntime>()) };
    if runtime.started.load(Ordering::Acquire) {
        write_error(error_buffer, error_buffer_len, "");
        return true;
    }

    let (tx, rx) = std::sync::mpsc::sync_channel(100);
    let (ntx, has_tcp_server) = if let Some(address) = runtime.tcp_server_address.clone() {
        let socket_addr = *address.get_ref();

        let mut server = kanata_state_machine::TcpServer::new(socket_addr, tx.clone());
        server.start(runtime.runtime.clone());
        let (ntx, nrx) = std::sync::mpsc::sync_channel(100);
        kanata_state_machine::Kanata::start_notification_loop(nrx, server.connections);
        (Some(ntx), true)
    } else {
        (None, false)
    };

    // Assign processing_tx BEFORE starting the processing loop so the channel
    // is available to send_input as soon as the loop thread begins.
    *runtime.processing_tx.lock() = Some(tx);

    // Intentionally avoid `Kanata::event_loop` in this passthrough spike path.
    // On macOS that would construct `KbdIn`, which still uses DriverKit input APIs
    // and can instantiate the pqrs client in the user-session host process.
    kanata_state_machine::Kanata::start_processing_loop(runtime.runtime.clone(), rx, ntx, true);
    runtime.started.store(true, Ordering::Release);
    let _ = has_tcp_server;
    write_error(error_buffer, error_buffer_len, "");
    true
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_start_passthru_runtime(
    _runtime: *mut c_void,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    write_error(
        error_buffer,
        error_buffer_len,
        "passthru output spike feature is not enabled in this bridge build",
    );
    false
}

#[cfg(feature = "passthru-output-spike")]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_send_input(
    runtime: *mut c_void,
    value: u64,
    page: u32,
    code: u32,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    if runtime.is_null() {
        write_error(
            error_buffer,
            error_buffer_len,
            "passthru runtime handle was null",
        );
        return false;
    }

    let runtime = unsafe { &*(runtime.cast::<PassthruRuntime>()) };
    let tx_guard = runtime.processing_tx.lock();
    let Some(tx) = tx_guard.as_ref() else {
        write_error(
            error_buffer,
            error_buffer_len,
            "passthru runtime was not started",
        );
        return false;
    };

    // DriverKit's InputEvent conversion recognizes only physical down/up.
    // The session ABI carries explicit repeats, so decode its values here.
    let key_value = match value {
        0 => kanata_state_machine::oskbd::KeyValue::Release,
        1 => kanata_state_machine::oskbd::KeyValue::Press,
        2 => kanata_state_machine::oskbd::KeyValue::Repeat,
        _ => {
            write_error(
                error_buffer,
                error_buffer_len,
                "invalid session input value",
            );
            return false;
        }
    };
    let oscode =
        match kanata_state_machine::OsCode::try_from(kanata_state_machine::PageCode { page, code })
        {
            Ok(code) => code,
            Err(_) => {
                write_error(
                    error_buffer,
                    error_buffer_len,
                    "unrecognized session input usage",
                );
                return false;
            }
        };
    let key_event = kanata_state_machine::oskbd::KeyEvent::new(oscode, key_value);

    // A session event-tap callback must never wait for a full processing queue.
    // Let the host fail open if the engine falls behind instead of blocking the
    // WindowServer callback and losing its tap to a timeout.
    match tx.try_send(key_event) {
        Ok(()) => {
            write_error(error_buffer, error_buffer_len, "");
            true
        }
        Err(error) => {
            write_error(error_buffer, error_buffer_len, &error.to_string());
            false
        }
    }
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_send_input(
    _runtime: *mut c_void,
    _value: u64,
    _page: u32,
    _code: u32,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    write_error(
        error_buffer,
        error_buffer_len,
        "passthru output spike feature is not enabled in this bridge build",
    );
    false
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_run_runtime(
    config_path: *const c_char,
    tcp_port: u16,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    let path = match parse_config_path(config_path, error_buffer, error_buffer_len) {
        Some(path) => path,
        None => return false,
    };

    let tcp_server_address = if tcp_port == 0 {
        None
    } else {
        match kanata_state_machine::SocketAddrWrapper::from_str(&tcp_port.to_string()) {
            Ok(address) => Some(address),
            Err(error) => {
                write_error(error_buffer, error_buffer_len, &error.to_string());
                return false;
            }
        }
    };

    let args = kanata_state_machine::ValidatedArgs {
        paths: vec![PathBuf::from(path)],
        tcp_server_address,
        nodelay: true,
    };

    let kanata_arc = match kanata_state_machine::Kanata::new_arc(&args) {
        Ok(kanata_arc) => kanata_arc,
        Err(error) => {
            write_error(error_buffer, error_buffer_len, &error.to_string());
            return false;
        }
    };

    let (tx, rx) = std::sync::mpsc::sync_channel(100);

    let (server, ntx, nrx) = if let Some(address) = args.tcp_server_address.clone() {
        let socket_addr = *address.get_ref();
        match std::net::TcpListener::bind(socket_addr) {
            Ok(listener) => drop(listener),
            Err(error) => {
                write_error(
                    error_buffer,
                    error_buffer_len,
                    &format!("tcp server port {tcp_port} unavailable: {error}"),
                );
                return false;
            }
        }

        let mut server = kanata_state_machine::TcpServer::new(socket_addr, tx.clone());
        server.start(kanata_arc.clone());
        let (ntx, nrx) = std::sync::mpsc::sync_channel(100);
        (Some(server), Some(ntx), Some(nrx))
    } else {
        (None, None, None)
    };

    kanata_state_machine::Kanata::start_processing_loop(kanata_arc.clone(), rx, ntx, args.nodelay);

    if let (Some(server), Some(nrx)) = (server, nrx) {
        kanata_state_machine::Kanata::start_notification_loop(nrx, server.connections);
    }

    match kanata_state_machine::Kanata::event_loop(kanata_arc, tx) {
        Ok(()) => {
            write_error(error_buffer, error_buffer_len, "");
            true
        }
        Err(error) => {
            write_error(error_buffer, error_buffer_len, &error.to_string());
            false
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_emit_key(
    usage_page: u32,
    usage: u32,
    is_key_down: bool,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    let mut event = karabiner_driverkit::DKEvent {
        value: if is_key_down { 1 } else { 0 },
        page: usage_page,
        code: usage,
        device_hash: 0,
    };

    match karabiner_driverkit::send_key(&mut event) {
        0 => {
            write_error(error_buffer, error_buffer_len, "");
            true
        }
        1 => {
            write_error(
                error_buffer,
                error_buffer_len,
                &format!("unrecognized usage page/code: page={usage_page} usage={usage}"),
            );
            false
        }
        2 => {
            write_error(
                error_buffer,
                error_buffer_len,
                "DriverKit virtual keyboard not ready (sink disconnected)",
            );
            false
        }
        code => {
            write_error(
                error_buffer,
                error_buffer_len,
                &format!("unexpected karabiner-driverkit send_key result: {code}"),
            );
            false
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_initialize_output_sink(
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    #[cfg(target_os = "macos")]
    unsafe {
        match keypath_driverkit_init_sink() {
            0 => {
                write_error(error_buffer, error_buffer_len, "");
                true
            }
            code => {
                write_error(
                    error_buffer,
                    error_buffer_len,
                    &format!("DriverKit sink initialization failed with code {code}"),
                );
                false
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        write_error(
            error_buffer,
            error_buffer_len,
            "output sink initialization is only supported on macOS",
        );
        false
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_output_ready() -> bool {
    karabiner_driverkit::is_sink_ready()
}

#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_wait_until_output_ready(timeout_millis: u64) -> bool {
    let start = std::time::Instant::now();
    let timeout = std::time::Duration::from_millis(timeout_millis);

    loop {
        if keypath_kanata_bridge_output_ready() {
            return true;
        }

        if start.elapsed() >= timeout {
            return false;
        }

        std::thread::sleep(std::time::Duration::from_millis(100));
    }
}

fn parse_config_path(
    config_path: *const c_char,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> Option<String> {
    if config_path.is_null() {
        write_error(error_buffer, error_buffer_len, "config path was null");
        return None;
    }

    match unsafe { CStr::from_ptr(config_path) }.to_str() {
        Ok(path) => Some(path.to_owned()),
        Err(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "config path was not valid UTF-8",
            );
            None
        }
    }
}

fn write_error(buffer: *mut c_char, buffer_len: usize, message: &str) {
    if buffer.is_null() || buffer_len == 0 {
        return;
    }

    let bytes = message.as_bytes();
    let copy_len = bytes.len().min(buffer_len.saturating_sub(1));
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buffer.cast::<u8>(), copy_len);
        *buffer.add(copy_len) = 0;
    }
}

#[cfg(all(test, feature = "passthru-output-spike", target_os = "macos"))]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::time::{Duration, Instant};

    fn passthru_cfg_path() -> CString {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../External/kanata/cfg_samples/minimal.kbd");
        CString::new(path.to_str().expect("utf-8 path")).expect("cstring path")
    }

    fn passthru_emit_cfg_path() -> CString {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../External/kanata/cfg_samples/simple.kbd");
        CString::new(path.to_str().expect("utf-8 path")).expect("cstring path")
    }

    fn read_error_buffer(buffer: &[c_char]) -> String {
        unsafe { CStr::from_ptr(buffer.as_ptr()) }
            .to_string_lossy()
            .into_owned()
    }

    #[test]
    fn passthru_virtual_switch_follows_tcp_app_context_without_event_loop() {
        use kanata_keyberon::layout::State;
        use std::io::{BufRead, BufReader, Write};
        use std::net::{TcpListener, TcpStream};

        let path = std::env::temp_dir().join(format!("keypath-switch-{}.kbd", std::process::id()));
        std::fs::write(&path, "(defvirtualkeys vk_test XX)(defalias kp-a (switch ((input virtual vk_test)) b break () a break))(defsrc a)(deflayer base @kp-a)").unwrap();
        let cfg_path = CString::new(path.to_str().unwrap()).unwrap();
        let mut error = vec![0 as c_char; 512];
        let usages = [4u32, 5];
        assert!(keypath_kanata_bridge_validate_session_config(
            cfg_path.as_ptr(),
            usages.as_ptr(),
            usages.len(),
            error.as_mut_ptr(),
            error.len()
        ));
        let reservation = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = reservation.local_addr().unwrap().port();
        drop(reservation);
        let handle = keypath_kanata_bridge_create_passthru_runtime(
            cfg_path.as_ptr(),
            port,
            error.as_mut_ptr(),
            error.len(),
        );
        assert!(!handle.is_null(), "{}", read_error_buffer(&error));
        assert!(keypath_kanata_bridge_start_passthru_runtime(
            handle,
            error.as_mut_ptr(),
            error.len()
        ));
        let runtime = unsafe { &*handle.cast::<PassthruRuntime>() };
        let mut stream = TcpStream::connect(("127.0.0.1", port)).unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let mut reader = BufReader::new(stream.try_clone().unwrap());
        let mut initial = String::new();
        reader.read_line(&mut initial).unwrap();
        assert!(initial.contains("LayerChange"));

        let output = |expected_value, expected_code| {
            let event = runtime
                .output_rx
                .recv_timeout(Duration::from_secs(2))
                .unwrap();
            assert_eq!(
                (event.value, event.page, event.code),
                (expected_value, 7, expected_code)
            );
        };
        let physical = |value| {
            let mut error = vec![0 as c_char; 512];
            assert!(keypath_kanata_bridge_passthru_send_input(
                handle,
                value,
                7,
                4,
                error.as_mut_ptr(),
                error.len()
            ));
        };
        // No frontmost-app signal uses the literal fallback.
        physical(1);
        output(1, 4);
        physical(0);
        output(0, 4);
        for (action, expected_active, expected_code) in [("Press", true, 5), ("Release", false, 4)]
        {
            writeln!(
                stream,
                "{{\"ActOnFakeKey\":{{\"name\":\"vk_test\",\"action\":\"{action}\"}}}}"
            )
            .unwrap();
            let deadline = Instant::now() + Duration::from_secs(2);
            loop {
                let k = runtime.runtime.lock();
                let index = k.virtual_keys["vk_test"] as u16;
                let active = k.layout.b().states.iter().any(|state| matches!(state, State::NoOpInput { coord } if *coord == (kanata_parser::cfg::FAKE_KEY_ROW, index)));
                if active == expected_active {
                    break;
                }
                drop(k);
                assert!(
                    Instant::now() < deadline,
                    "TCP virtual {action} was not processed"
                );
                std::thread::yield_now();
            }
            // XX supplies condition state without emitting a synthetic key.
            assert!(matches!(
                runtime.output_rx.try_recv(),
                Err(mpsc::TryRecvError::Empty)
            ));
            physical(1);
            output(1, expected_code);
            physical(0);
            output(0, expected_code);
        }
        drop(stream);
        drop(reader);
        keypath_kanata_bridge_destroy_passthru_runtime(handle);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn passthru_release_layer_restores_base_and_preserves_held_key_release() {
        use kanata_state_machine::oskbd::{KeyEvent, KeyValue};
        use kanata_state_machine::OsCode;

        let path =
            std::env::temp_dir().join(format!("keypath-release-layer-{}.kbd", std::process::id()));
        std::fs::write(
            &path,
            r#"
            (defsrc a b c esc)
            (deflayer base (multi lctl (layer-while-held nav)) b c esc)
            (deflayer nav _ d e (multi (release-layer nav) XX (push-msg "layer:base")))
        "#,
        )
        .unwrap();
        let cfg_path = CString::new(path.to_str().unwrap()).unwrap();
        let mut error = vec![0 as c_char; 512];
        let usages = [4u32, 5, 6, 7, 8, 41, 224];
        assert!(
            keypath_kanata_bridge_validate_session_config(
                cfg_path.as_ptr(),
                usages.as_ptr(),
                usages.len(),
                error.as_mut_ptr(),
                error.len()
            ),
            "{}",
            read_error_buffer(&error)
        );
        let handle = keypath_kanata_bridge_create_passthru_runtime(
            cfg_path.as_ptr(),
            0,
            error.as_mut_ptr(),
            error.len(),
        );
        assert!(!handle.is_null(), "{}", read_error_buffer(&error));
        let runtime = unsafe { &*handle.cast::<PassthruRuntime>() };
        // Advance real Kanata with explicit ticks. This needs neither wall-clock
        // sleeps nor the macOS input event loop/DriverKit input backend.
        let input = |code, value| {
            let mut k = runtime.runtime.lock();
            k.handle_input_event(&KeyEvent::new(code, value)).unwrap();
            k.tick_ms(2, &None).unwrap();
        };
        let output = |value, code| {
            let event = runtime
                .output_rx
                .try_recv()
                .expect("expected emitted keyboard event");
            assert_eq!((event.value, event.page, event.code), (value, 7, code));
        };
        let layer = || {
            let k = runtime.runtime.lock();
            k.layer_info[k.layout.b().current_layer()].name.clone()
        };
        input(OsCode::KEY_A, KeyValue::Press);
        output(1, 224);
        assert_eq!(layer(), "nav");
        input(OsCode::KEY_B, KeyValue::Press);
        output(1, 7); // b maps to d while nav is held.
        input(OsCode::KEY_ESC, KeyValue::Press);
        assert_eq!(layer(), "base");
        assert!(matches!(
            runtime.output_rx.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        {
            let k = runtime.runtime.lock();
            let held: Vec<_> = k.layout.b().keycodes().collect();
            assert!(held.contains(&kanata_keyberon::key_code::KeyCode::LCtrl));
            assert!(held.contains(&kanata_keyberon::key_code::KeyCode::D));
        }
        // A new physical key uses base even while the former layer activator
        // and a nav-mapped key remain physically held.
        input(OsCode::KEY_C, KeyValue::Press);
        output(1, 6);
        input(OsCode::KEY_C, KeyValue::Release);
        output(0, 6);
        input(OsCode::KEY_ESC, KeyValue::Release);
        assert!(matches!(
            runtime.output_rx.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        input(OsCode::KEY_B, KeyValue::Release);
        output(0, 7); // Release the original nav output, not base b.
        input(OsCode::KEY_A, KeyValue::Release);
        output(0, 224);
        assert_eq!(runtime.runtime.lock().layout.b().keycodes().count(), 0);
        assert!(matches!(
            runtime.output_rx.try_recv(),
            Err(mpsc::TryRecvError::Empty)
        ));
        keypath_kanata_bridge_destroy_passthru_runtime(handle);
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn create_passthru_runtime_returns_handle_and_empty_output_queue() {
        let cfg_path = passthru_cfg_path();
        let mut error_buffer = vec![0 as c_char; 512];

        let runtime = keypath_kanata_bridge_create_passthru_runtime(
            cfg_path.as_ptr(),
            0,
            error_buffer.as_mut_ptr(),
            error_buffer.len(),
        );

        assert!(
            !runtime.is_null(),
            "expected passthru runtime, got error: {}",
            read_error_buffer(&error_buffer)
        );

        let mut value = 99u64;
        let mut page = 99u32;
        let mut code = 99u32;
        let recv_status = keypath_kanata_bridge_passthru_try_recv_output(
            runtime,
            &mut value,
            &mut page,
            &mut code,
            error_buffer.as_mut_ptr(),
            error_buffer.len(),
        );

        assert_eq!(
            recv_status,
            0,
            "unexpected error: {}",
            read_error_buffer(&error_buffer)
        );
        assert_eq!(read_error_buffer(&error_buffer), "");
        assert_eq!(value, 99);
        assert_eq!(page, 99);
        assert_eq!(code, 99);

        keypath_kanata_bridge_destroy_passthru_runtime(runtime);
    }

    #[test]
    fn passthru_runtime_processes_injected_input_without_event_loop() {
        let cfg_path = passthru_emit_cfg_path();
        let mut error_buffer = vec![0 as c_char; 512];

        let runtime = keypath_kanata_bridge_create_passthru_runtime(
            cfg_path.as_ptr(),
            0,
            error_buffer.as_mut_ptr(),
            error_buffer.len(),
        );
        assert!(
            !runtime.is_null(),
            "expected passthru runtime, got error: {}",
            read_error_buffer(&error_buffer)
        );

        assert!(keypath_kanata_bridge_start_passthru_runtime(
            runtime,
            error_buffer.as_mut_ptr(),
            error_buffer.len(),
        ));
        assert_eq!(read_error_buffer(&error_buffer), "");

        let page_code = kanata_state_machine::PageCode::try_from(
            kanata_state_machine::str_to_oscode("a").unwrap(),
        )
        .expect("page code");
        assert!(keypath_kanata_bridge_passthru_send_input(
            runtime,
            1,
            page_code.page,
            page_code.code,
            error_buffer.as_mut_ptr(),
            error_buffer.len(),
        ));
        assert_eq!(read_error_buffer(&error_buffer), "");

        let mut value = 0u64;
        let mut page = 0u32;
        let mut code = 0u32;
        let deadline = Instant::now() + Duration::from_millis(250);
        let mut recv_status = 0;
        while Instant::now() < deadline {
            recv_status = keypath_kanata_bridge_passthru_try_recv_output(
                runtime,
                &mut value,
                &mut page,
                &mut code,
                error_buffer.as_mut_ptr(),
                error_buffer.len(),
            );
            if recv_status != 0 {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }

        assert_eq!(
            recv_status,
            1,
            "unexpected error: {}",
            read_error_buffer(&error_buffer)
        );
        assert_eq!(value, 1);
        assert_eq!(page, page_code.page);
        assert_eq!(code, page_code.code);

        for expected in [2u64, 0u64] {
            assert!(keypath_kanata_bridge_passthru_send_input(
                runtime,
                expected,
                page_code.page,
                page_code.code,
                error_buffer.as_mut_ptr(),
                error_buffer.len(),
            ));
            let deadline = Instant::now() + Duration::from_millis(250);
            let mut status = 0;
            while Instant::now() < deadline {
                status = keypath_kanata_bridge_passthru_try_recv_output(
                    runtime,
                    &mut value,
                    &mut page,
                    &mut code,
                    error_buffer.as_mut_ptr(),
                    error_buffer.len(),
                );
                if status != 0 {
                    break;
                }
                std::thread::sleep(Duration::from_millis(1));
            }
            assert_eq!(status, 1);
            assert_eq!(
                (value, page, code),
                (expected, page_code.page, page_code.code)
            );
        }
        assert!(!keypath_kanata_bridge_passthru_send_input(
            runtime,
            3,
            page_code.page,
            page_code.code,
            error_buffer.as_mut_ptr(),
            error_buffer.len(),
        ));

        keypath_kanata_bridge_destroy_passthru_runtime(runtime);
    }
}

#[cfg(all(test, target_os = "macos"))]
mod managed_caps_admission_tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn additive_managed_caps_api_preserves_legacy_result_and_reports_failures() {
        let path =
            std::env::temp_dir().join(format!("keypath-managed-caps-{}.kbd", std::process::id()));
        let c_path = CString::new(path.to_str().unwrap()).unwrap();
        let usages = [4, 41, 224];
        let mut error = [0 as c_char; 256];
        std::fs::write(&path, "(defsrc caps)(deflayer base esc)").unwrap();
        assert!(!keypath_kanata_bridge_validate_session_config(
            c_path.as_ptr(),
            usages.as_ptr(),
            usages.len(),
            error.as_mut_ptr(),
            error.len()
        ));
        assert!(
            !keypath_kanata_bridge_validate_session_config_with_managed_caps(
                c_path.as_ptr(),
                usages.as_ptr(),
                usages.len(),
                false,
                error.as_mut_ptr(),
                error.len()
            )
        );
        assert!(
            keypath_kanata_bridge_validate_session_config_with_managed_caps(
                c_path.as_ptr(),
                usages.as_ptr(),
                usages.len(),
                true,
                error.as_mut_ptr(),
                error.len()
            )
        );
        assert_eq!(error[0], 0);
        std::fs::write(&path, "(defsrc caps)(deflayer base (macro caps))").unwrap();
        assert!(
            !keypath_kanata_bridge_validate_session_config_with_managed_caps(
                c_path.as_ptr(),
                usages.as_ptr(),
                usages.len(),
                true,
                error.as_mut_ptr(),
                error.len()
            )
        );
        assert!(unsafe { CStr::from_ptr(error.as_ptr()) }
            .to_str()
            .unwrap()
            .contains("unsafe for managed Caps Lock"));
        std::fs::write(&path, "(invalid").unwrap();
        assert!(
            !keypath_kanata_bridge_validate_session_config_with_managed_caps(
                c_path.as_ptr(),
                usages.as_ptr(),
                usages.len(),
                true,
                error.as_mut_ptr(),
                error.len()
            )
        );
        assert!(unsafe { CStr::from_ptr(error.as_ptr()) }
            .to_str()
            .unwrap()
            .contains("could not be parsed"));
        std::fs::remove_file(path).unwrap();
    }
}
