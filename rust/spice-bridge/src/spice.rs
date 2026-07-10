use crate::SharedFramebuffer;
use std::ffi::{CStr, CString, c_void};
use std::ptr;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::thread;

#[allow(clippy::all)]
#[allow(non_upper_case_globals)]
#[allow(non_camel_case_types)]
#[allow(non_snake_case)]
#[allow(unsafe_op_in_unsafe_fn)]
#[allow(dead_code)]
pub mod ffi {
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
}
use ffi::*;

#[derive(Debug)]
pub enum SpiceInputEvent {
    KeyDown { scancode: u32 },
    KeyUp { scancode: u32 },
    MouseMotion { x: i32, y: i32, button_mask: u32 },
}

struct InputsChannelPtr(pub *mut SpiceInputsChannel);
unsafe impl Send for InputsChannelPtr {}
unsafe impl Sync for InputsChannelPtr {}

// Thread-safe wrapper struct to pass our Context safely into C FFI callbacks
struct SpiceContext {
    pub fb: SharedFramebuffer,
    pub input_channel: Mutex<Option<InputsChannelPtr>>,
}

struct KeyIdleData {
    channel: *mut SpiceInputsChannel,
    scancode: u32,
    down: bool,
}

unsafe extern "C" fn on_key_idle(data: gpointer) -> gboolean {
    unsafe {
        let raw = data as *mut KeyIdleData;
        let info = Box::from_raw(raw);
        if info.down {
            spice_inputs_channel_key_press(info.channel, info.scancode as guint);
        } else {
            spice_inputs_channel_key_release(info.channel, info.scancode as guint);
        }
    }
    0
}

struct MouseIdleData {
    channel: *mut SpiceInputsChannel,
    x: i32,
    y: i32,
    button_mask: u32,
}

unsafe extern "C" fn on_mouse_idle(data: gpointer) -> gboolean {
    unsafe {
        let raw = data as *mut MouseIdleData;
        let info = Box::from_raw(raw);
        spice_inputs_channel_position(
            info.channel,
            info.x as gint,
            info.y as gint,
            0,
            info.button_mask as gint,
        );
        if info.button_mask > 0 {
            spice_inputs_channel_button_press(info.channel, 1, 1);
        }
    }
    0
}

pub fn start_spice_client(port: u16, fb: SharedFramebuffer) -> Sender<SpiceInputEvent> {
    let (tx, rx) = mpsc::channel::<SpiceInputEvent>();

    let context = Arc::new(SpiceContext {
        fb,
        input_channel: Mutex::new(None),
    });

    let ctx_clone_for_glib = context.clone();

    // Start GLib main loop in background thread
    thread::spawn(move || {
        println!("Initializing SPICE Session and GLib Main Loop...");
        let main_loop = glib::MainLoop::new(None, false);

        unsafe {
            let session = spice_session_new();
            let uri = CString::new(format!("spice://127.0.0.1:{}", port)).unwrap();
            let uri_prop = CString::new("uri").unwrap();
            glib::gobject_ffi::g_object_set(
                session as *mut _,
                uri_prop.as_ptr(),
                uri.as_ptr(),
                ptr::null_mut::<std::ffi::c_void>(),
            );

            // Convert our context Arc into a raw pointer to pass through C
            let user_data = Arc::into_raw(ctx_clone_for_glib) as *mut c_void;

            let channel_new_signal = CString::new("channel-new").unwrap();
            g_signal_connect_data(
                session as *mut _,
                channel_new_signal.as_ptr(),
                Some(std::mem::transmute::<*const (), unsafe extern "C" fn()>(
                    on_channel_new as *const (),
                )),
                user_data,
                None,
                0,
            );

            println!("Connecting to SPICE server at {}...", uri.to_str().unwrap());
            let connected = spice_session_connect(session);

            if connected == 0 {
                eprintln!("Failed to initiate SPICE session connection.");
            } else {
                println!("SPICE session initiated successfully!");
            }

            // Run GLib event loop
            main_loop.run();

            // Cleanup when loop exits
            let _ = Arc::from_raw(user_data as *const SpiceContext);
            glib::gobject_ffi::g_object_unref(session as *mut _);
        }
    });

    // Input Routing thread
    let ctx_clone_for_inputs = context.clone();
    thread::spawn(move || {
        while let Ok(event) = rx.recv() {
            let channel_ptr = {
                let guard = ctx_clone_for_inputs.input_channel.lock().unwrap();
                guard.as_ref().map(|p| p.0)
            };

            if let Some(channel) = channel_ptr {
                unsafe {
                    match event {
                        SpiceInputEvent::KeyDown { scancode } => {
                            let data = Box::into_raw(Box::new(KeyIdleData {
                                channel,
                                scancode,
                                down: true,
                            })) as gpointer;
                            g_idle_add(Some(on_key_idle), data);
                        }
                        SpiceInputEvent::KeyUp { scancode } => {
                            let data = Box::into_raw(Box::new(KeyIdleData {
                                channel,
                                scancode,
                                down: false,
                            })) as gpointer;
                            g_idle_add(Some(on_key_idle), data);
                        }
                        SpiceInputEvent::MouseMotion { x, y, button_mask } => {
                            let data = Box::into_raw(Box::new(MouseIdleData {
                                channel,
                                x,
                                y,
                                button_mask,
                            })) as gpointer;
                            g_idle_add(Some(on_mouse_idle), data);
                        }
                    }
                }
            } else {
                println!("Input dropped: SPICE Inputs channel not connected yet.");
            }
        }
    });

    tx
}

// FFI Callback: Invoked when SPICE session creates a new channel
extern "C" fn on_channel_new(
    _session: *mut SpiceSession,
    channel: *mut SpiceChannel,
    user_data: gpointer,
) {
    unsafe {
        let _channel_type = spice_channel_get_type();

        let type_instance = channel as *mut glib::gobject_ffi::GTypeInstance;
        let type_class = (*type_instance).g_class;
        let type_id = (*type_class).g_type;
        let type_name_ptr = glib::gobject_ffi::g_type_name(type_id);
        if type_name_ptr.is_null() {
            return;
        }

        let type_name = CStr::from_ptr(type_name_ptr).to_string_lossy();
        println!("New SPICE channel created: {}", type_name);

        let ctx = &*(user_data as *const SpiceContext);

        if type_name == "SpiceDisplayChannel" {
            let display_channel = channel as *mut SpiceDisplayChannel;

            // Connect to display-primary-create (resolution change)
            let sig_create = CString::new("display-primary-create").unwrap();
            g_signal_connect_data(
                display_channel as *mut _,
                sig_create.as_ptr(),
                Some(std::mem::transmute::<*const (), unsafe extern "C" fn()>(
                    on_display_primary_create as *const (),
                )),
                user_data,
                None,
                0,
            );

            // Connect to display-mark (frame buffer updated)
            let sig_mark = CString::new("display-mark").unwrap();
            g_signal_connect_data(
                display_channel as *mut _,
                sig_mark.as_ptr(),
                Some(std::mem::transmute::<*const (), unsafe extern "C" fn()>(
                    on_display_mark as *const (),
                )),
                user_data,
                None,
                0,
            );

            // Connect to display-invalidate (region invalidated/drawn)
            let sig_invalidate = CString::new("display-invalidate").unwrap();
            g_signal_connect_data(
                display_channel as *mut _,
                sig_invalidate.as_ptr(),
                Some(std::mem::transmute::<*const (), unsafe extern "C" fn()>(
                    on_display_invalidate as *const (),
                )),
                user_data,
                None,
                0,
            );

            // Explicitly connect the channel
            spice_channel_connect(channel);
        } else if type_name == "SpiceInputsChannel" {
            let inputs_channel = channel as *mut SpiceInputsChannel;
            let mut guard = ctx.input_channel.lock().unwrap();
            *guard = Some(InputsChannelPtr(inputs_channel));

            // Explicitly connect the channel
            spice_channel_connect(channel);
            println!("SPICE Inputs channel attached and ready.");
        }
    }
}

extern "C" fn on_display_primary_create(
    _channel: *mut SpiceDisplayChannel,
    format: gint,
    width: gint,
    height: gint,
    _stride: gint,
    _shmid: gint,
    _imgdata: gpointer,
    user_data: gpointer,
) {
    println!(
        "SPICE primary surface created: {}x{} format={}",
        width, height, format
    );
    let ctx = unsafe { &*(user_data as *const SpiceContext) };
    let mut fb = ctx.fb.lock().unwrap();
    fb.width = width as u32;
    fb.height = height as u32;
    let required_len = (width * height * 3) as usize;
    if fb.data.len() != required_len {
        fb.data.resize(required_len, 0);
    }
}

extern "C" fn on_display_mark(
    channel: *mut SpiceDisplayChannel,
    _mark_true: gint,
    user_data: gpointer,
) {
    extract_frame(channel, user_data);
}

extern "C" fn on_display_invalidate(
    channel: *mut SpiceDisplayChannel,
    _x: gint,
    _y: gint,
    _w: gint,
    _h: gint,
    user_data: gpointer,
) {
    extract_frame(channel, user_data);
}

#[repr(C)]
pub struct LocalSpiceDisplayPrimary {
    pub format: i32,
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub shmid: i32,
    pub data: *mut u8,
    pub marked: i32,
}

fn extract_frame(channel: *mut SpiceDisplayChannel, user_data: gpointer) {
    unsafe {
        let mut primary: LocalSpiceDisplayPrimary = std::mem::zeroed();
        let success = spice_display_get_primary(
            channel as *mut SpiceChannel,
            0,
            &mut primary as *mut _ as *mut _,
        );

        if success != 0 && !primary.data.is_null() {
            let ctx = &*(user_data as *const SpiceContext);
            let mut fb = ctx.fb.lock().unwrap();

            fb.width = primary.width as u32;
            fb.height = primary.height as u32;
            let w = primary.width as usize;
            let h = primary.height as usize;
            let stride = primary.stride as usize;

            let required_len = w * h * 3;
            if fb.data.len() != required_len {
                fb.data.resize(required_len, 0);
            }

            match primary.format {
                32 | 96 => {
                    // SPICE_SURFACE_FMT_32_xRGB or SPICE_SURFACE_FMT_32_ARGB: 4 bytes per pixel (BGRA)
                    for y in 0..h {
                        let src_row = primary.data.add(y * stride);
                        for x in 0..w {
                            let src_pixel = src_row.add(x * 4);
                            let dest_idx = (y * w + x) * 3;
                            let b = *src_pixel;
                            let g = *src_pixel.add(1);
                            let r = *src_pixel.add(2);
                            fb.data[dest_idx] = r;
                            fb.data[dest_idx + 1] = g;
                            fb.data[dest_idx + 2] = b;
                        }
                    }
                }
                80 => {
                    // SPICE_SURFACE_FMT_16_565: 2 bytes per pixel (RGB 565)
                    for y in 0..h {
                        let src_row = primary.data.add(y * stride);
                        for x in 0..w {
                            let src_pixel = src_row.add(x * 2);
                            let dest_idx = (y * w + x) * 3;
                            let val = u16::from_le_bytes([*src_pixel, *src_pixel.add(1)]);
                            let r = (((val >> 11) & 0x1F) as u32 * 255 / 31) as u8;
                            let g = (((val >> 5) & 0x3F) as u32 * 255 / 63) as u8;
                            let b = ((val & 0x1F) as u32 * 255 / 31) as u8;
                            fb.data[dest_idx] = r;
                            fb.data[dest_idx + 1] = g;
                            fb.data[dest_idx + 2] = b;
                        }
                    }
                }
                16 => {
                    // SPICE_SURFACE_FMT_16_555: 2 bytes per pixel (RGB 555)
                    for y in 0..h {
                        let src_row = primary.data.add(y * stride);
                        for x in 0..w {
                            let src_pixel = src_row.add(x * 2);
                            let dest_idx = (y * w + x) * 3;
                            let val = u16::from_le_bytes([*src_pixel, *src_pixel.add(1)]);
                            let r = (((val >> 10) & 0x1F) as u32 * 255 / 31) as u8;
                            let g = (((val >> 5) & 0x1F) as u32 * 255 / 31) as u8;
                            let b = ((val & 0x1F) as u32 * 255 / 31) as u8;
                            fb.data[dest_idx] = r;
                            fb.data[dest_idx + 1] = g;
                            fb.data[dest_idx + 2] = b;
                        }
                    }
                }
                _ => {
                    eprintln!(
                        "Unsupported SPICE primary surface format: {}",
                        primary.format
                    );
                }
            }
        }
    }
}

#[allow(dead_code)]
pub fn update_mock_framebuffer(fb: &SharedFramebuffer) {
    let mut guard = fb.lock().unwrap();
    let w = guard.width as usize;
    let h = guard.height as usize;
    if guard.data.len() != w * h * 3 {
        guard.data = vec![0u8; w * h * 3];
    }
    static mut OFFSET: u8 = 0;
    unsafe {
        OFFSET = OFFSET.wrapping_add(2);
        let off = OFFSET as usize;
        for y in 0..h {
            for x in 0..w {
                let idx = (y * w + x) * 3;
                guard.data[idx] = ((x + off) % 256) as u8; // R
                guard.data[idx + 1] = ((y + off) % 256) as u8; // G
                guard.data[idx + 2] = ((x + y + off) % 256) as u8; // B
            }
        }
    }
}
