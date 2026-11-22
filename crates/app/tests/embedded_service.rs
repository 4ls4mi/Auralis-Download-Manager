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
    let manifest_dir = dir.path().join("backup-ui");
    mdm_ipc::private_dir(&manifest_dir).expect("backup UI directory");
    let manifest = manifest_dir.join("settings.json");
    mdm_ipc::private_write(
        &manifest,
        br#"{"appearance":{"mh-glass-theme":"ocean"},"startup":{"enabled":false,"mode":"window"}}"#,
    )
    .expect("backup UI manifest");
    let archive = dir.path().join("fixture.auralis-backup");
    let saved = backup_job(mdm_ipc::Command {
        action: Some("glass-export-full-backup".into()),
        dir: Some(archive.to_string_lossy().into_owned()),
        queue: Some(manifest.to_string_lossy().into_owned()),
        ..Default::default()
    });
    assert_eq!(saved["path"], archive.to_string_lossy().as_ref());
    assert!(archive.is_file());
    let target = dir.path().join("restored-files");
    let restored = backup_job(mdm_ipc::Command {
        action: Some("glass-import-full-backup".into()),
        dir: Some(archive.to_string_lossy().into_owned()),
        queue: Some(target.to_string_lossy().into_owned()),
        ..Default::default()
    });
    assert_eq!(restored["restored_to"], target.to_string_lossy().as_ref());
    assert_eq!(restored["ui"]["mh-glass-theme"], "ocean");
    assert_eq!(restored["startup"]["mode"], "window");
    assert_eq!(restored["downloads"], 0);

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

fn backup_job(command: mdm_ipc::Command) -> serde_json::Value {
    fn request(command: &mdm_ipc::Command) -> serde_json::Value {
        let reply = mdm_ipc::request_checked(command).expect("backup IPC");
        let value: serde_json::Value = serde_json::from_str(&reply).expect("backup reply");
        assert!(value["error"].is_null(), "backup failed: {value}");
        value
    }
    let start = request(&command);
    let id = start["id"].as_u64().expect("backup job ID");
    let status = mdm_ipc::Command {
        query: Some("glass-full-backup-status".into()),
        ids: vec![id],
        ..Default::default()
    };
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let result = request(&status);
        if result["pending"] != true {
            return result;
        }
        assert!(Instant::now() < deadline, "backup did not finish");
        std::thread::sleep(Duration::from_millis(100));
    }
}
