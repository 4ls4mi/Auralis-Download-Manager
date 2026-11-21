use mdm_engine::{Destination,Download,Options,Request};
use tokio::io::{AsyncReadExt,AsyncWriteExt};

#[tokio::test]
async fn server_checksum_is_detected_verified_and_available_in_snapshot() {
    let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr=listener.local_addr().unwrap();
    let server=tokio::spawn(async move {
        let (mut socket,_)=listener.accept().await.unwrap();
        let mut request=[0u8;4096];let _=socket.read(&mut request).await.unwrap();
        socket.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Type: application/octet-stream\r\nDigest: SHA-256=ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=\r\nConnection: close\r\n\r\nabc").await.unwrap();
    });
    let dir=tempfile::tempdir().unwrap();
    let download=Download::start(Request{url:format!("http://{addr}/file.bin").parse().unwrap(),headers:Default::default(),dest:Destination::Dir(dir.path().to_owned())},Options::default());
    let snap=tokio::time::timeout(std::time::Duration::from_secs(15),async {loop {let s=download.snapshot();if matches!(s.state,mdm_engine::download::State::Done|mdm_engine::download::State::Failed){break s}tokio::time::sleep(std::time::Duration::from_millis(20)).await}}).await.unwrap();
    assert_eq!(snap.state, mdm_engine::download::State::Done, "events: {:?}", snap.events);
    assert_eq!(snap.checksum.unwrap().display(),"sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    assert!(snap.events.iter().any(|e|e.text.contains("Checksum verified")));
    let result=download.wait().await.unwrap();assert_eq!(std::fs::read(result.path).unwrap(),b"abc");server.await.unwrap();
}
