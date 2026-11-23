//! The timed public file flow over loopback HTTPS. The test CA and DNS
//! overrides are used only by these clients, so the fixture makes no site requests.

use std::{
    io,
    net::{IpAddr, Ipv4Addr},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use mdm_engine::{Destination, Download, Options, Request, probe_kept};
use mdm_labserver::ftp::test_certificate_for_hosts;
use reqwest::header::{HeaderMap, IF_RANGE, RANGE};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
    task::JoinHandle,
};
use tokio_rustls::{TlsAcceptor, server::TlsStream};
use url::Url;

const SITE: &str = "bowfile.com";
const CDN: &str = "fs21.bowfile.com";
const UNRELATED: &str = "files.invalid";
const PAGE: &str = "/abcd";
const TIMED: &str = "/abcd?pt=syntheticopaque%3D";
const FILE: &str = "/token/synthetic-token";
const NAME: &str = "fixture.zip";
const WAIT: Duration = Duration::from_secs(1);
const TEST_TIMEOUT: Duration = Duration::from_secs(12);

const ARCHIVE: &[u8] = &[
    80, 75, 3, 4, 20, 0, 0, 0, 0, 0, 0, 0, 33, 0, 251, 95, 43, 230, 26, 0, 0, 0, 26, 0, 0, 0, 11,
    0, 0, 0, 102, 105, 120, 116, 117, 114, 101, 46, 116, 120, 116, 65, 117, 114, 97, 108, 105, 115,
    32, 100, 111, 119, 110, 108, 111, 97, 100, 32, 102, 105, 120, 116, 117, 114, 101, 46, 10, 80,
    75, 1, 2, 20, 3, 20, 0, 0, 0, 0, 0, 0, 0, 33, 0, 251, 95, 43, 230, 26, 0, 0, 0, 26, 0, 0, 0,
    11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 128, 1, 0, 0, 0, 0, 102, 105, 120, 116, 117, 114, 101, 46,
    116, 120, 116, 80, 75, 5, 6, 0, 0, 0, 0, 1, 0, 1, 0, 57, 0, 0, 0, 67, 0, 0, 0, 0, 0,
];

#[derive(Debug)]
struct SeenRequest {
    method: String,
    path: String,
    host: String,
    cookie: Option<String>,
    range: Option<String>,
    if_range: Option<String>,
    referer: Option<String>,
    at: Instant,
}

impl SeenRequest {
    async fn read(stream: &mut TlsStream<TcpStream>) -> io::Result<Self> {
        let mut head = Vec::new();
        let mut buffer = [0; 1024];
        while !head.windows(4).any(|bytes| bytes == b"\r\n\r\n") {
            let len = stream.read(&mut buffer).await?;
            if len == 0 || head.len() + len > 8192 {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "invalid fixture request headers",
                ));
            }
            head.extend_from_slice(&buffer[..len]);
        }
        let head = String::from_utf8_lossy(&head);
        let mut words = head.lines().next().unwrap_or_default().split_whitespace();
        let header = |name: &str| {
            head.lines()
                .skip(1)
                .take_while(|line| !line.is_empty())
                .filter_map(|line| line.split_once(':'))
                .find(|(key, _)| key.eq_ignore_ascii_case(name))
                .map(|(_, value)| value.trim().to_owned())
        };
        Ok(Self {
            method: words.next().unwrap_or_default().to_owned(),
            path: words.next().unwrap_or_default().to_owned(),
            host: header("host").unwrap_or_default(),
            cookie: header("cookie"),
            range: header("range"),
            if_range: header("if-range"),
            referer: header("referer"),
            at: Instant::now(),
        })
    }
}

struct Fixture {
    port: u16,
    ca: Vec<u8>,
    requests: Arc<Mutex<Vec<SeenRequest>>>,
    server: JoinHandle<()>,
}

#[derive(Clone, Copy)]
enum Redirect {
    Normal,
    OffsiteFromShare,
    OffsiteFromFile,
}

impl Drop for Fixture {
    fn drop(&mut self) {
        self.server.abort();
    }
}

impl Fixture {
    async fn start(redirect: Redirect) -> Self {
        let (tls, ca) = test_certificate_for_hosts(&[SITE, CDN, UNRELATED]).unwrap();
        let acceptor = TlsAcceptor::from(Arc::new(tls));
        let tcp = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).await.unwrap();
        let port = tcp.local_addr().unwrap().port();
        let requests = Arc::new(Mutex::new(Vec::new()));
        let log = Arc::clone(&requests);
        let server = tokio::spawn(async move {
            while let Ok((stream, _)) = tcp.accept().await {
                let acceptor = acceptor.clone();
                let log = Arc::clone(&log);
                tokio::spawn(async move {
                    let Ok(mut stream) = acceptor.accept(stream).await else {
                        return;
                    };
                    let Ok(request) = SeenRequest::read(&mut stream).await else {
                        return;
                    };
                    let response = {
                        let mut requests = log.lock().unwrap();
                        let response = reply(&request, port, redirect, &requests);
                        requests.push(request);
                        response
                    };
                    let _ = stream.write_all(&response).await;
                    let _ = stream.shutdown().await;
                });
            }
        });
        Self {
            port,
            ca,
            requests,
            server,
        }
    }

    fn share(&self) -> Url {
        format!("https://{SITE}:{}{PAGE}", self.port)
            .parse()
            .unwrap()
    }

    fn options(&self) -> Options {
        Options {
            hosts: [SITE, CDN, UNRELATED]
                .into_iter()
                .map(|host| (host.to_owned(), vec![IpAddr::V4(Ipv4Addr::LOCALHOST)]))
                .collect(),
            extra_roots: vec![self.ca.clone()],
            max_connections: 1,
            max_retries: 0,
            connect_timeout: Duration::from_secs(4),
            read_timeout: Duration::from_secs(4),
            ..Options::default()
        }
    }

    fn assert_delivery(&self) {
        let requests = self.requests.lock().unwrap();
        assert_eq!(requests.len(), 3, "{requests:?}");
        let [share, timed, file] = requests.as_slice() else {
            unreachable!();
        };
        assert_eq!(share.host, format!("{SITE}:{}", self.port));
        assert_eq!(share.path, PAGE);
        assert!(share.cookie.is_none());
        assert_eq!(timed.host, share.host);
        assert_eq!(timed.path, TIMED);
        assert_eq!(timed.cookie.as_deref(), Some("filehosting=session"));
        assert!(timed.range.is_none());
        assert!(timed.at.duration_since(share.at) >= WAIT, "{requests:?}");
        assert_eq!(file.host, format!("{CDN}:{}", self.port));
        assert_eq!(file.path, FILE);
        assert!(file.cookie.is_none());
        assert_eq!(
            file.referer.as_deref(),
            Some(format!("https://{SITE}:{}/", self.port).as_str()),
        );
        assert!(requests.iter().all(|r| r.method == "GET"), "{requests:?}");
    }
}

fn reply(
    request: &SeenRequest,
    port: u16,
    redirect: Redirect,
    requests: &[SeenRequest],
) -> Vec<u8> {
    let hostname = request.host.split(':').next().unwrap_or_default();
    match (request.method.as_str(), hostname, request.path.as_str()) {
        ("GET", SITE, PAGE) => {
            let page = format!(
                r#"<html><title>{NAME}</title><script>
var seconds = 1;
var started = false;
function display() {{
    $('.btn-free-element').hide();
    $('.download-timer').show();
    if (seconds == 0) {{
        $('.download-timer').html("<button class='btn btn--primary' id='dl' onclick='window.location.href = \"https://{SITE}:{port}{TIMED}\";'><span class='btn__text'>DOWNLOAD / VIEW NOW</span></button>");
    }} else {{
        $('.download-timer-seconds').html(seconds);
    }}
    seconds--;
}}
function triggerFreeDownload() {{ setInterval('display()',1000); }}
</script><body><button onclick="triggerFreeDownload()">Free download</button></body></html>"#
            );
            response(
                "200 OK",
                "Content-Type: text/html; charset=UTF-8\r\nSet-Cookie: filehosting=session; Path=/; Max-Age=60; Secure; HttpOnly\r\n",
                page.as_bytes(),
            )
        }
        ("GET", SITE, TIMED)
            if request.cookie.as_deref() == Some("filehosting=session")
                && request.range.is_none()
                && request.if_range.is_none()
                && requests.iter().any(|first| {
                    first.path == PAGE && request.at.duration_since(first.at) >= WAIT
                }) =>
        {
            let redirect_host = if matches!(redirect, Redirect::OffsiteFromShare) {
                UNRELATED
            } else {
                CDN
            };
            response(
                "302 Found",
                &format!("Location: https://{redirect_host}:{port}{FILE}\r\n"),
                b"",
            )
        }
        ("GET", CDN, FILE) if matches!(redirect, Redirect::OffsiteFromFile) => response(
            "302 Found",
            &format!("Location: https://{UNRELATED}:{port}{FILE}\r\n"),
            b"",
        ),
        ("GET", CDN, FILE)
            if request.cookie.is_none()
                && request.range.as_deref() == Some("bytes=0-0")
                && request.if_range.as_deref() == Some("\"fixture\"") =>
        {
            response(
                "206 Partial Content",
                &format!(
                    "Content-Type: application/zip\r\nContent-Range: bytes 0-0/{}\r\n",
                    ARCHIVE.len()
                ),
                &ARCHIVE[..1],
            )
        }
        ("GET", CDN, FILE) if request.cookie.is_none() => response(
            "200 OK",
            "Content-Type: application/zip\r\nContent-Disposition: attachment; filename=\"fixture.zip\"\r\n",
            ARCHIVE,
        ),
        _ => response(
            "400 Bad Request",
            "Content-Type: text/plain\r\n",
            b"fixture rejected the request",
        ),
    }
}

fn response(status: &str, headers: &str, body: &[u8]) -> Vec<u8> {
    let head = format!(
        "HTTP/1.1 {status}\r\n{headers}Content-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let mut response = head.into_bytes();
    response.extend_from_slice(body);
    response
}

fn request(s: &Fixture, dir: &tempfile::TempDir) -> Request {
    Request {
        url: s.share(),
        headers: Default::default(),
        dest: Destination::Dir(dir.path().to_path_buf()),
    }
}

#[tokio::test]
async fn downloads_the_archive_after_the_wait_without_leaking_the_session() {
    let server = Fixture::start(Redirect::Normal).await;
    let folder = tempfile::tempdir().unwrap();
    let out = tokio::time::timeout(
        TEST_TIMEOUT,
        Download::start(request(&server, &folder), server.options()).wait(),
    )
    .await
    .expect("the fixture download finishes")
    .unwrap();
    assert_eq!(out.path, folder.path().join(NAME));
    assert_eq!(std::fs::read(out.path).unwrap(), ARCHIVE);
    server.assert_delivery();
}

#[tokio::test]
async fn start_reuses_the_open_probe_answer_without_redeeming_the_address_again() {
    let server = Fixture::start(Redirect::Normal).await;
    let folder = tempfile::tempdir().unwrap();
    let options = server.options();
    let (info, kept) = tokio::time::timeout(
        TEST_TIMEOUT,
        probe_kept(server.share(), Default::default(), &options),
    )
    .await
    .expect("the fixture probe finishes")
    .unwrap();
    assert_eq!(info.file_name, NAME);
    assert_eq!(info.size, Some(ARCHIVE.len() as u64));
    assert!(kept.is_some(), "keep the file response for Start");
    assert!(std::fs::read_dir(folder.path()).unwrap().next().is_none());
    server.assert_delivery();

    let out = tokio::time::timeout(
        TEST_TIMEOUT,
        Download::start_with(request(&server, &folder), options, kept).wait(),
    )
    .await
    .expect("the kept response finishes")
    .unwrap();
    assert_eq!(std::fs::read(out.path).unwrap(), ARCHIVE);
    server.assert_delivery();
}

#[tokio::test]
async fn a_redirect_to_an_unrelated_host_is_never_requested() {
    let server = Fixture::start(Redirect::OffsiteFromShare).await;
    let folder = tempfile::tempdir().unwrap();
    let out = tokio::time::timeout(
        TEST_TIMEOUT,
        Download::start(request(&server, &folder), server.options()).wait(),
    )
    .await
    .expect("the fixture download stops");
    assert!(out.is_err());
    let requests = server.requests.lock().unwrap();
    assert_eq!(requests.len(), 2, "{requests:?}");
    assert_eq!(requests[0].path, PAGE);
    assert_eq!(requests[1].path, TIMED);
    assert!(std::fs::read_dir(folder.path()).unwrap().next().is_none());
}

#[tokio::test]
async fn a_file_server_redirect_to_an_unrelated_host_is_never_requested() {
    let server = Fixture::start(Redirect::OffsiteFromFile).await;
    let folder = tempfile::tempdir().unwrap();
    let out = tokio::time::timeout(
        TEST_TIMEOUT,
        Download::start(request(&server, &folder), server.options()).wait(),
    )
    .await
    .expect("the fixture download stops");
    assert!(out.is_err());
    // These three requests are the share, its timed button, and the file server.
    // In particular the unrelated host never receives the redirected request.
    server.assert_delivery();
    assert!(std::fs::read_dir(folder.path()).unwrap().next().is_none());
}

#[tokio::test]
async fn only_the_archive_request_receives_range_headers() {
    let server = Fixture::start(Redirect::Normal).await;
    let mut headers = HeaderMap::new();
    headers.insert(RANGE, "bytes=0-0".parse().unwrap());
    headers.insert(IF_RANGE, "\"fixture\"".parse().unwrap());
    let (info, _) = tokio::time::timeout(
        TEST_TIMEOUT,
        probe_kept(server.share(), headers, &server.options()),
    )
    .await
    .expect("the ranged fixture probe finishes")
    .unwrap();
    assert_eq!(info.size, Some(ARCHIVE.len() as u64));
    server.assert_delivery();
    let requests = server.requests.lock().unwrap();
    assert!(requests[0].range.is_none() && requests[0].if_range.is_none());
    assert_eq!(requests[2].range.as_deref(), Some("bytes=0-0"));
    assert_eq!(requests[2].if_range.as_deref(), Some("\"fixture\""));
}
