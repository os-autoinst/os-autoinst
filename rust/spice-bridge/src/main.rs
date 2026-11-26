use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::thread;

mod spice;

pub struct Framebuffer {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

pub type SharedFramebuffer = Arc<Mutex<Framebuffer>>;

#[derive(Serialize, Deserialize, Debug)]
#[serde(tag = "cmd", rename_all = "snake_case")]
enum Command {
    Ping,
    GetFrame,
    KeyEvent { key: String, down: bool },
    MouseEvent { x: i32, y: i32, button_mask: u32 },
}

#[derive(Serialize, Debug)]
struct PingResponse {
    status: String,
    msg: String,
}

#[derive(Serialize, Debug)]
struct FrameResponse {
    status: String,
    width: u32,
    height: u32,
    size: usize,
}

fn handle_client(
    stream: UnixStream,
    fb: SharedFramebuffer,
    input_tx: Sender<spice::SpiceInputEvent>,
) {
    let mut writer = match stream.try_clone() {
        Ok(w) => w,
        Err(e) => {
            eprintln!("Failed to clone stream for writing: {}", e);
            return;
        }
    };
    let reader = BufReader::new(&stream);
    for line in reader.lines() {
        let line = match line {
            Ok(l) => l,
            Err(e) => {
                eprintln!("Error reading from stream: {}", e);
                break;
            }
        };

        if line.trim().is_empty() {
            continue;
        }

        match serde_json::from_str::<Command>(&line) {
            Ok(Command::Ping) => {
                let resp = PingResponse {
                    status: "ok".to_string(),
                    msg: "pong".to_string(),
                };
                let resp_str = serde_json::to_string(&resp).unwrap() + "\n";
                if let Err(e) = writer.write_all(resp_str.as_bytes()) {
                    eprintln!("Failed to write reply: {}", e);
                    break;
                }
            }
            Ok(Command::GetFrame) => {
                let (width, height, data) = {
                    let guard = fb.lock().unwrap();
                    (guard.width, guard.height, guard.data.clone())
                };

                let resp = FrameResponse {
                    status: "ok".to_string(),
                    width,
                    height,
                    size: data.len(),
                };
                let resp_str = serde_json::to_string(&resp).unwrap() + "\n";
                if let Err(e) = writer.write_all(resp_str.as_bytes()) {
                    eprintln!("Failed to write reply: {}", e);
                    break;
                }
                if let Err(e) = writer.write_all(&data) {
                    eprintln!("Failed to write raw frame bytes: {}", e);
                    break;
                }
            }
            Ok(Command::KeyEvent { key, down }) => {
                let scancode = key.parse::<u32>().unwrap_or(0x1c); // default to Enter if not numeric
                let event = if down {
                    spice::SpiceInputEvent::KeyDown { scancode }
                } else {
                    spice::SpiceInputEvent::KeyUp { scancode }
                };
                let _ = input_tx.send(event);

                let resp = serde_json::json!({ "status": "ok" });
                let resp_str = serde_json::to_string(&resp).unwrap() + "\n";
                let _ = writer.write_all(resp_str.as_bytes());
            }
            Ok(Command::MouseEvent { x, y, button_mask }) => {
                let event = spice::SpiceInputEvent::MouseMotion { x, y, button_mask };
                let _ = input_tx.send(event);

                let resp = serde_json::json!({ "status": "ok" });
                let resp_str = serde_json::to_string(&resp).unwrap() + "\n";
                let _ = writer.write_all(resp_str.as_bytes());
            }
            Err(e) => {
                eprintln!("Invalid command: {}", e);
                let resp = serde_json::json!({ "status": "error", "error": format!("Invalid command: {}", e) });
                let resp_str = serde_json::to_string(&resp).unwrap() + "\n";
                let _ = writer.write_all(resp_str.as_bytes());
            }
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let socket_path_str = if args.len() > 1 {
        args[1].clone()
    } else {
        "/tmp/spice-bridge.sock".to_string()
    };

    let spice_port = if args.len() > 2 {
        args[2].parse::<u16>().unwrap_or(5900)
    } else {
        5900
    };

    let fb = Arc::new(Mutex::new(Framebuffer {
        width: 1024,
        height: 768,
        data: vec![0u8; 1024 * 768 * 3],
    }));

    let input_tx = spice::start_spice_client(spice_port, fb.clone());

    let socket_path = Path::new(&socket_path_str);
    if socket_path.exists() {
        fs::remove_file(socket_path).unwrap_or_else(|e| {
            eprintln!("Failed to remove existing socket file: {}", e);
            std::process::exit(1);
        });
    }

    let listener = match UnixListener::bind(socket_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Failed to bind to socket at {}: {}", socket_path_str, e);
            std::process::exit(1);
        }
    };

    println!("SPICE bridge listening on UNIX socket: {}", socket_path_str);

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                let fb_clone = fb.clone();
                let input_tx_clone = input_tx.clone();
                thread::spawn(move || {
                    handle_client(stream, fb_clone, input_tx_clone);
                });
            }
            Err(e) => {
                eprintln!("Connection failed: {}", e);
            }
        }
    }
}
