use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::process::{Child, Command};
use std::thread;
use std::time::Duration;

struct ChildGuard {
    child: Child,
    socket_path: String,
}

impl Drop for ChildGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let path = Path::new(&self.socket_path);
        if path.exists() {
            let _ = fs::remove_file(path);
        }
    }
}

#[test]
fn test_spice_bridge_ipc() {
    let socket_path = "/tmp/test-rust-spice-bridge-full.sock";

    let binary_path = "../../target/debug/spice-bridge";
    let binary_path_fallback = "./target/debug/spice-bridge";
    let binary_path_workspace_fallback = "target/debug/spice-bridge";

    let mut actual_path = binary_path;
    if !Path::new(actual_path).exists() {
        actual_path = binary_path_fallback;
    }
    if !Path::new(actual_path).exists() {
        actual_path = binary_path_workspace_fallback;
    }

    if Path::new(socket_path).exists() {
        let _ = fs::remove_file(socket_path);
    }

    let child = Command::new(actual_path)
        .arg(socket_path)
        .spawn()
        .expect("Failed to spawn spice-bridge process");

    let _guard = ChildGuard {
        child,
        socket_path: socket_path.to_string(),
    };

    // Wait for the socket to be created
    let mut connected = false;
    let mut stream = None;
    for _ in 0..50 {
        if Path::new(socket_path).exists() {
            if let Ok(s) = UnixStream::connect(socket_path) {
                connected = true;
                stream = Some(s);
                break;
            }
        }
        thread::sleep(Duration::from_millis(50));
    }

    assert!(connected, "Failed to connect to SPICE bridge socket!");
    let stream = stream.unwrap();
    let mut writer = stream.try_clone().unwrap();
    let mut reader = BufReader::new(stream);

    // 1. Send ping command
    let ping_cmd = "{\"cmd\":\"ping\"}\n";
    writer
        .write_all(ping_cmd.as_bytes())
        .expect("Failed to write to stream");
    let mut response = String::new();
    reader
        .read_line(&mut response)
        .expect("Failed to read response");
    assert!(
        response.contains("\"status\":\"ok\""),
        "Ping status was not ok"
    );
    assert!(
        response.contains("\"msg\":\"pong\""),
        "Ping message was not pong"
    );

    // 2. Send key event command
    let key_cmd = "{\"cmd\":\"key_event\",\"key\":\"28\",\"down\":true}\n";
    writer
        .write_all(key_cmd.as_bytes())
        .expect("Failed to write to stream");
    response.clear();
    reader
        .read_line(&mut response)
        .expect("Failed to read response");
    assert!(
        response.contains("\"status\":\"ok\""),
        "Key event response status was not ok"
    );

    // 3. Send mouse event command
    let mouse_cmd = "{\"cmd\":\"mouse_event\",\"x\":100,\"y\":200,\"button_mask\":1}\n";
    writer
        .write_all(mouse_cmd.as_bytes())
        .expect("Failed to write to stream");
    response.clear();
    reader
        .read_line(&mut response)
        .expect("Failed to read response");
    assert!(
        response.contains("\"status\":\"ok\""),
        "Mouse event response status was not ok"
    );

    // 4. Send get_frame command
    let frame_cmd = "{\"cmd\":\"get_frame\"}\n";
    writer
        .write_all(frame_cmd.as_bytes())
        .expect("Failed to write to stream");
    response.clear();
    reader
        .read_line(&mut response)
        .expect("Failed to read response");
    assert!(
        response.contains("\"status\":\"ok\""),
        "GetFrame response status was not ok"
    );
    assert!(
        response.contains("\"width\":1024"),
        "GetFrame width mismatch"
    );
    assert!(
        response.contains("\"height\":768"),
        "GetFrame height mismatch"
    );

    // Read full raw frame data (1024 * 768 * 3 bytes)
    let mut frame_bytes = vec![0u8; 1024 * 768 * 3];
    reader
        .read_exact(&mut frame_bytes)
        .expect("Failed to read raw frame bytes");
    assert_eq!(frame_bytes.len(), 1024 * 768 * 3);
}
