//! The embedded host must serve the same authenticated control protocol and
//! release its data lock after a clean shutdown, without launching a child app.
use std::time::{Duration, Instant};

#[test]
fn embedded_service_uses_existing_ipc_and_shuts_down_cleanly() {
    let dir = tempfile::tempdir().expect("temporary data directory");
    mdm_ipc::set_data_dir(dir.path().to_owned());
    let worker = std::thread::spawn(mdm_app::run_embedded_downloader);
    let query = mdm_ipc::Command {
        query: Some("glass-backend".into()),
        ..Default::default()
    };
    let until = Instant::now() + Duration::from_secs(60);
    let answer = loop {
        if let Ok(reply) = mdm_ipc::request_checked(&query) {
            break reply;
        }
        assert!(
            !worker.is_finished(),
            "embedded downloader exited during startup"
        );
        assert!(Instant::now() < until, "embedded downloader did not start");
        std::thread::sleep(Duration::from_millis(200));
    };
    let answer: serde_json::Value = serde_json::from_str(&answer).expect("backend identity");
    assert_eq!(answer["headless"], true);
    assert_eq!(answer["glass"], true);
    assert!(
        mdm_ipc::instance_lock().is_none(),
        "data lock must remain held"
    );
    // Preferences export must omit device-bound credentials, and restoration
    // must apply supported preferences without requiring a second process.
    let reply = mdm_ipc::request_checked(&mdm_ipc::Command {
        query: Some("glass-backup-settings".into()),
        ..Default::default()
    })
    .expect("export preferences");
    let mut backup: serde_json::Value = serde_json::from_str(&reply).expect("backup json");
    let settings = backup["settings"].as_object_mut().expect("settings object");
    for key in ["proxy_pass", "site_logins", "debrid_accounts"] {
        assert!(!settings.contains_key(key), "credential leaked: {key}");
    }
    settings.insert("show_complete".into(), serde_json::json!(true));
    let reply = mdm_ipc::request_checked(&mdm_ipc::Command {
        action: Some("glass-restore-settings".into()),
        queue: Some(backup["settings"].to_string()),
        ..Default::default()
    })
    .expect("restore preferences");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&reply).expect("restore json")["ok"],
        true
    );
    let current = mdm_ipc::request_checked(&mdm_ipc::Command {
        query: Some("glass-settings".into()),
        ..Default::default()
    })
    .expect("current preferences");
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&current).expect("settings json")["show_complete"],
        true
    );
    mdm_ipc::send(&mdm_ipc::Command {
        exit: true,
        ..Default::default()
    })
    .expect("request shutdown");
    let until = Instant::now() + Duration::from_secs(30);
    while !worker.is_finished() && Instant::now() < until {
        std::thread::sleep(Duration::from_millis(100));
    }
    assert!(worker.is_finished(), "embedded downloader did not stop");
    worker
        .join()
        .expect("service thread panicked")
        .expect("service failed");
    assert!(
        mdm_ipc::instance_lock().is_some(),
        "data lock should be released"
    );
}
