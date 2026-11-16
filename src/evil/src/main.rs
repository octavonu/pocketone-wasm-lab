//! evil, a lab plugin in Rust: a hostile plugin, small. "run" tries every way out of the box it can and reports what
//! it got; its input names a listening host:port to try to reach ({"target": "127.0.0.1:8090"}). Each entry is
//! "refused: ..." or "GOT: ...". "listen" listens on a port ({"addr": "127.0.0.1:18777"}), to see whether the outside
//! can reach it; "exit" tries to end the host. The same plugin in Go (fat_evil, ~11 MB, from ext/wasm's
//! testdata/evil) is over the default MaxRunningMB and isn't loaded at all.
//!
//! Build: cargo build --release --target wasm32-wasip1
use serde_json::{json, Map, Value};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::time::Duration;
use std::{env, fs, process};

fn main() {
    // `<name> --describe`: the manifest, kept as plugin.json beside the source
    if env::args().nth(1).as_deref() == Some("--describe") {
        print!("{}", include_str!("../plugin.json"));
        return;
    }
    let mut raw = String::new();
    std::io::stdin().read_to_string(&mut raw).ok();
    let input: Value = serde_json::from_str(&raw).unwrap_or(json!({}));
    match env::args().nth(1).as_deref() {
        Some("exit") => process::exit(0),
        Some("listen") => listen(input["addr"].as_str().unwrap_or("127.0.0.1:18777")),
        _ => run(input["target"].as_str().unwrap_or("127.0.0.1:8090")),
    }
}

fn run(target: &str) {
    let mut r = Map::new();
    let mut try_ = |name: &str, got: Result<String, String>| {
        let v = match got {
            Err(e) => format!("refused: {e}"),
            Ok(s) if s.is_empty() => "refused: nothing there".into(),
            Ok(s) => format!("GOT: {}", s.chars().take(80).collect::<String>()),
        };
        r.insert(name.into(), v.into());
    };
    let err = |e: std::io::Error| e.to_string();

    try_("read /etc/passwd", fs::read_to_string("/etc/passwd").map_err(err));
    try_("list /", list("/"));
    try_("list .", list("."));
    try_("write a file", fs::write("/tmp/evil", "x").map(|_| "wrote /tmp/evil".into()).map_err(err));
    try_("environment", Ok(env::vars().map(|(k, v)| format!("{k}={v}")).collect::<Vec<_>>().join(" ")));
    try_("args beyond the function", Ok(env::args().skip(2).collect::<Vec<_>>().join(" ")));
    try_("hostname", fs::read_to_string("/etc/hostname").map_err(err));
    try_("tcp to the target", TcpStream::connect(target).map(|_| "connected".into()).map_err(err));
    try_("http GET", TcpStream::connect(target)
        .and_then(|mut c| {
            c.write_all(format!("GET / HTTP/1.0\r\nHost: {target}\r\n\r\n").as_bytes())?;
            let mut first = [0u8; 64];
            let n = c.read(&mut first)?;
            Ok(String::from_utf8_lossy(&first[..n]).lines().next().unwrap_or("").to_string())
        })
        .map_err(err));
    print!("{}", Value::Object(r));
}

fn listen(addr: &str) {
    let l = match TcpListener::bind(addr) {
        Ok(l) => l,
        Err(e) => return print!("refused: {e}"),
    };
    l.set_nonblocking(true).ok();
    for _ in 0..10 {
        if let Ok((_, from)) = l.accept() {
            return print!("GOT: a connection from {from}");
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    print!("listened at {addr}, nobody came");
}

fn list(dir: &str) -> Result<String, String> {
    let names: Vec<String> = fs::read_dir(dir)
        .map_err(|e| e.to_string())?
        .filter_map(|e| e.ok().map(|e| e.file_name().to_string_lossy().into_owned()))
        .collect();
    Ok(names.join(" "))
}
