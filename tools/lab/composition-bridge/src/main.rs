#![cfg_attr(windows, windows_subsystem = "windows")]
//! Development-only composition bridge. Uses the original local IPC and never
//! sends its token into the WebView. Only start/pause for one selected id are
//! accepted; no filesystem operations or arbitrary IPC requests are exposed.
use std::{env, io::{BufRead, BufReader, Write}, process::{Command, Stdio}, sync::{Arc, Mutex}, thread, time::Duration};
use serde_json::{Value, json};

fn action_name(line: &str) -> Option<&'static str> {
    match line { "pause" => Some("pause"), "start" => Some("start"), _ => None }
}
fn request(command: mdm_ipc::Command) -> Result<Value, ()> {
    let raw = mdm_ipc::request_checked(&command).map_err(|_| ())?;
    let value: Value = serde_json::from_str(&raw).map_err(|_| ())?;
    if value.get("error").is_some() { return Err(()); }
    Ok(value)
}
fn live_snapshot(id: u64) -> Result<Option<Value>, ()> {
    let list = request(mdm_ipc::Command { query: Some("list".into()), ..Default::default() })?;
    let visuals = request(mdm_ipc::Command { query: Some("glass-visuals".into()), ..Default::default() })?;
    let downloads = list.get("downloads").and_then(Value::as_array).ok_or(())?;
    let visual_downloads = visuals.get("downloads").and_then(Value::as_array).ok_or(())?;
    let item = downloads.iter().find(|item| item.get("id").and_then(Value::as_u64) == Some(id));
    let visual = visual_downloads.iter().find(|item| item.get("id").and_then(Value::as_u64) == Some(id));
    Ok(item.map(|download| json!({ "download": download, "visual": visual })))
}
fn send_frame(writer: &Arc<Mutex<impl Write>>, frame: &Value) -> Result<(), ()> {
    let mut out = writer.lock().map_err(|_| ())?;
    serde_json::to_writer(&mut *out, frame).map_err(|_| ())?;
    out.write_all(b"\n").map_err(|_| ())?;
    out.flush().map_err(|_| ())
}
fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args = env::args_os();
    let _program = args.next();
    let executable = args.next().ok_or("missing composition lab executable")?;
    let id: u64 = args.next().ok_or("missing download id")?.to_string_lossy().parse()?;
    if args.next().is_some() { return Err("unexpected arguments".into()); }
    let mut child = Command::new(executable).arg("--live").stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;
    let output = child.stdout.take().ok_or("missing child stdout")?;
    let writer = Arc::new(Mutex::new(child.stdin.take().ok_or("missing child stdin")?));
    // Only a process identifier is emitted for the isolated Windows test. No
    // engine token, URL or other download data is written to stdout or logs.
    println!("LAB_PID:{}", child.id());
    let action_writer = Arc::clone(&writer);
    thread::spawn(move || {
        for line in BufReader::new(output).lines() {
            let Ok(line) = line else { break };
            let Some(action) = action_name(&line) else { continue };
            let result = request(mdm_ipc::Command { action: Some(action.into()), ids: vec![id], ..Default::default() });
            let ok = result.ok().and_then(|v| v.get("done").and_then(Value::as_array).map(|done| done.iter().any(|v| v.as_u64()==Some(id)))).unwrap_or(false);
            let response = if ok { json!({"actionResult":{"ok":true}}) } else { json!({"actionResult":{"ok":false,"message":"The original engine did not perform the action"}}) };
            if send_frame(&action_writer, &response).is_err() { break; }
        }
    });
    loop {
        if child.try_wait()?.is_some() { break; }
        if let Ok(Some(snapshot)) = live_snapshot(id) {
            if send_frame(&writer, &snapshot).is_err() { break; }
        }
        thread::sleep(Duration::from_millis(650));
    }
    Ok(())
}
fn main() { if run().is_err() { std::process::exit(1); } }

#[cfg(test)]
mod tests {
    use super::action_name;
    #[test]
    fn accepts_only_transfer_controls() {
        assert_eq!(action_name("pause"),Some("pause"));
        assert_eq!(action_name("start"),Some("start"));
        assert_eq!(action_name("delete"),None);
        assert_eq!(action_name("pause\nstart"),None);
    }
}
