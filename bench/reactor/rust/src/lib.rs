//! The summary module built as a reactor (a library), for bench's stateful variant (D): the same exports as ../go.
//!
//!   alloc(size) -> ptr            a buffer of size bytes in the module's memory, for the input
//!   run(ptr, len) -> ptr<<32|len  {"title","body"} in, {"text","words","calls"} out
//!
//! Build: cargo build --release --target wasm32-wasip1; the module is target/wasm32-wasip1/release/summary_reactor.wasm.
use serde::Deserialize;
use std::cell::RefCell;

#[derive(Deserialize)]
struct Post {
    #[serde(default)]
    title: String,
    #[serde(default)]
    body: String,
}

#[derive(Default)]
struct State {
    input: Vec<u8>,
    output: Vec<u8>,
    calls: u64, // the state: survives between calls because the instance does
}

thread_local! {
    static STATE: RefCell<State> = RefCell::new(State::default());
}

#[no_mangle]
pub extern "C" fn alloc(size: u32) -> u32 {
    STATE.with_borrow_mut(|s| {
        s.input = vec![0; size as usize];
        s.input.as_ptr() as u32
    })
}

#[no_mangle]
pub extern "C" fn run(_ptr: u32, len: u32) -> u64 {
    STATE.with_borrow_mut(|s| {
        s.calls += 1;
        let res = match serde_json::from_slice::<Post>(&s.input[..len as usize]) {
            Err(e) => serde_json::json!({ "code": "bad_input", "message": e.to_string() }),
            Ok(post) => {
                let words: Vec<&str> = post.body.split_whitespace().collect();
                let mut short = words[..words.len().min(12)].join(" ");
                if words.len() > 12 {
                    short.push_str(" …");
                }
                let text = if post.title.is_empty() { short } else { format!("{}: {}", post.title, short) };
                serde_json::json!({ "text": text, "words": words.len(), "calls": s.calls })
            }
        };
        s.output = serde_json::to_vec(&res).unwrap();
        ((s.output.as_ptr() as u64) << 32) | s.output.len() as u64
    })
}
