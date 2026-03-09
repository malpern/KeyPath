use std::ffi::{CStr, c_char, c_void};
use std::path::{Path, PathBuf};
use std::str::FromStr;

#[cfg(feature = "passthru-output-spike")]
use std::sync::mpsc::{self, Receiver};
#[cfg(feature = "passthru-output-spike")]
use std::sync::mpsc::SyncSender;
#[cfg(feature = "passthru-output-spike")]
use std::sync::Arc;

const BRIDGE_VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();

#[cfg(target_os = "macos")]
unsafe extern "C" {
    #[link_name = "\u{1}__Z9init_sinkv"]
    fn keypath_driverkit_init_sink() -> i32;
}

#[cfg(feature = "passthru-output-spike")]
struct PassthruRuntime {
    runtime: Arc<parking_lot::Mutex<kanata_state_machine::Kanata>>,
    output_rx: Receiver<kanata_state_machine::oskbd::InputEvent>,
    processing_tx: Option<SyncSender<kanata_state_machine::oskbd::KeyEvent>>,
    tcp_server_address: Option<kanata_state_machine::SocketAddrWrapper>,
    started: bool,
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
        drop(Box::from_raw(runtime.cast::<kanata_state_machine::Kanata>()));
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
                processing_tx: None,
                tcp_server_address,
                started: false,
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
pub extern "C" fn keypath_kanata_bridge_passthru_runtime_layer_count(runtime: *const c_void) -> usize {
    if runtime.is_null() {
        return 0;
    }

    let runtime = unsafe { &*(runtime.cast::<PassthruRuntime>()) };
    runtime.runtime.lock().layer_info.len()
}

#[cfg(not(feature = "passthru-output-spike"))]
#[unsafe(no_mangle)]
pub extern "C" fn keypath_kanata_bridge_passthru_runtime_layer_count(_runtime: *const c_void) -> usize {
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
        write_error(error_buffer, error_buffer_len, "passthru runtime handle was null");
        return -1;
    }

    let runtime = unsafe { &mut *(runtime.cast::<PassthruRuntime>()) };
    match runtime.output_rx.try_recv() {
        Ok(event) => {
            if !value_out.is_null() {
                unsafe { *value_out = event.value; }
            }
            if !page_out.is_null() {
                unsafe { *page_out = event.page; }
            }
            if !code_out.is_null() {
                unsafe { *code_out = event.code; }
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
        write_error(error_buffer, error_buffer_len, "passthru runtime handle was null");
        return false;
    }

    let runtime = unsafe { &mut *(runtime.cast::<PassthruRuntime>()) };
    if runtime.started {
        write_error(error_buffer, error_buffer_len, "");
        return true;
    }

    let (tx, rx) = std::sync::mpsc::sync_channel(100);
    let (ntx, has_tcp_server) = if let Some(address) = runtime.tcp_server_address.clone() {
        let socket_addr = *address.get_ref();
        // This preflight bind catches an obviously unavailable port for diagnostics.
        // TcpServer::new binds again below, so there is still a small TOCTOU window.
        match std::net::TcpListener::bind(socket_addr) {
            Ok(listener) => drop(listener),
            Err(error) => {
                write_error(
                    error_buffer,
                    error_buffer_len,
                    &format!("tcp server port unavailable: {error}"),
                );
                return false;
            }
        }

        let mut server = kanata_state_machine::TcpServer::new(socket_addr, tx.clone());
        server.start(runtime.runtime.clone());
        let (ntx, nrx) = std::sync::mpsc::sync_channel(100);
        kanata_state_machine::Kanata::start_notification_loop(nrx, server.connections);
        (Some(ntx), true)
    } else {
        (None, false)
    };

    // Intentionally avoid `Kanata::event_loop` in this passthrough spike path.
    // On macOS that would construct `KbdIn`, which still uses DriverKit input APIs
    // and can instantiate the pqrs client in the user-session host process.
    kanata_state_machine::Kanata::start_processing_loop(runtime.runtime.clone(), rx, ntx, true);
    runtime.processing_tx = Some(tx);
    runtime.started = true;
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
        write_error(error_buffer, error_buffer_len, "passthru runtime handle was null");
        return false;
    }

    let runtime = unsafe { &mut *(runtime.cast::<PassthruRuntime>()) };
    let Some(tx) = &runtime.processing_tx else {
        write_error(
            error_buffer,
            error_buffer_len,
            "passthru runtime was not started",
        );
        return false;
    };

    let input_event = kanata_state_machine::oskbd::InputEvent { value, page, code };
    let key_event = match kanata_state_machine::oskbd::KeyEvent::try_from(input_event) {
        Ok(event) => event,
        Err(()) => {
            write_error(
                error_buffer,
                error_buffer_len,
                &format!("unrecognized input event: value={value} page={page} code={code}"),
            );
            return false;
        }
    };

    match tx.send(key_event) {
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
            write_error(error_buffer, error_buffer_len, "config path was not valid UTF-8");
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

        assert_eq!(recv_status, 0, "unexpected error: {}", read_error_buffer(&error_buffer));
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

        let page_code =
            kanata_state_machine::PageCode::try_from(kanata_state_machine::str_to_oscode("a").unwrap())
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

        assert_eq!(recv_status, 1, "unexpected error: {}", read_error_buffer(&error_buffer));
        assert_eq!(value, 1);
        assert_eq!(page, page_code.page);
        assert_eq!(code, page_code.code);

        keypath_kanata_bridge_destroy_passthru_runtime(runtime);
    }
}
