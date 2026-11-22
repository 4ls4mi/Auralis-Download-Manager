//! Retrieve metadata from a public URL that the user explicitly chose.
//! This request is independent of the failed download and never reuses its credentials.

use mdm_engine::{dns::DnsChoice, net::Route};
use std::{
    net::{IpAddr, SocketAddr},
    time::Duration,
};
use url::{Host, Url};

const MAX_REDIRECTS: usize = 5;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(15);
const TOTAL_TIMEOUT: Duration = Duration::from_secs(30);

fn public_address(ip: IpAddr) -> bool {
    if !crate::trackers::public(ip) {
        return false;
    }
    match ip {
        IpAddr::V4(ip) => !ip.is_documentation(),
        IpAddr::V6(ip) => {
            if let Some(mapped) = ip.to_ipv4_mapped() {
                return public_address(IpAddr::V4(mapped));
            }
            let segments = ip.segments();
            // Limit native addresses to global unicast, excluding tunneling and documentation.
            segments[0] & 0xe000 == 0x2000
                && segments[0] != 0x2002
                && !(segments[0] == 0x2001 && (segments[1] < 0x200 || segments[1] == 0xdb8))
                && segments[0] != 0x3fff
        }
    }
}

fn check_url(url: &Url) -> Result<(), String> {
    if !matches!(url.scheme(), "http" | "https")
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err("Enter a public HTTP or HTTPS torrent link without credentials".into());
    }
    let public_host = match url.host() {
        Some(Host::Ipv4(ip)) => public_address(IpAddr::V4(ip)),
        Some(Host::Ipv6(ip)) => public_address(IpAddr::V6(ip)),
        Some(Host::Domain(host)) => {
            let host = host.trim_end_matches('.');
            host.contains('.') && !host.ends_with(".localhost") && !host.ends_with(".local")
        }
        None => false,
    };
    if !public_host {
        return Err("Torrent metadata must come from a public internet address".into());
    }
    Ok(())
}

pub fn parse(raw: &str) -> Result<Url, String> {
    let raw = raw.trim();
    if raw.len() > 8192 {
        return Err("Torrent link is too long".into());
    }
    let mut url = Url::parse(raw).map_err(|_| "Enter a valid HTTP or HTTPS torrent link")?;
    check_url(&url)?;
    url.set_fragment(None);
    Ok(url)
}

fn redirect(url: &Url, location: &str) -> Result<Url, String> {
    if location.len() > 8192 {
        return Err("Torrent metadata redirect is too long".into());
    }
    let mut next = url
        .join(location)
        .map_err(|_| "Invalid torrent metadata redirect")?;
    check_url(&next)?;
    if url.scheme() == "https" && next.scheme() != "https" {
        return Err("A secure torrent metadata link cannot redirect to plain HTTP".into());
    }
    next.set_fragment(None);
    Ok(next)
}

async fn fetch(mut url: Url, dns: &DnsChoice, route: &Route) -> Result<crate::Meta, String> {
    for hop in 0..=MAX_REDIRECTS {
        check_url(&url)?;
        let host = url.host_str().ok_or("Torrent link has no host")?;
        let port = url
            .port_or_known_default()
            .ok_or("Torrent link has no port")?;
        let addresses = mdm_engine::dns::lookup(dns, host, port, &[], route)
            .await
            .map_err(|_| "Could not resolve the torrent metadata host")?;
        if addresses.is_empty() || addresses.iter().any(|ip| !public_address(*ip)) {
            return Err(
                "Torrent metadata host did not resolve to public internet addresses".into(),
            );
        }
        let addresses: Vec<_> = addresses
            .into_iter()
            .map(|ip| SocketAddr::new(ip, port))
            .collect();
        // Resolve once, then pin the connection to those validated addresses, including after
        // each redirect. A proxy could resolve to a different address, so use the chosen adapter
        // directly for this explicit check. Send no referrer, cookie, or authorization headers.
        let builder = reqwest::Client::builder()
            .no_proxy()
            .referer(false)
            .redirect(reqwest::redirect::Policy::none())
            .timeout(REQUEST_TIMEOUT);
        let builder = if url.domain().is_some() {
            builder.resolve_to_addrs(host, &addresses)
        } else {
            builder
        };
        let client = mdm_engine::net::bind_client(builder, route, false)
            .map_err(|error| error.to_string())?
            .build()
            .map_err(|_| "Could not set up the torrent metadata request")?;
        let mut response = client
            .get(url.clone())
            .send()
            .await
            .map_err(|_| "Could not connect to the torrent metadata host")?;
        if response.status().is_redirection() {
            if hop == MAX_REDIRECTS {
                return Err("Too many torrent metadata redirects".into());
            }
            let location = response
                .headers()
                .get(reqwest::header::LOCATION)
                .and_then(|value| value.to_str().ok())
                .ok_or("Torrent metadata redirect has no valid address")?;
            url = redirect(&url, location)?;
            continue;
        }
        if !response.status().is_success() {
            return Err(format!(
                "Torrent metadata server returned HTTP {}",
                response.status().as_u16()
            ));
        }
        if response
            .content_length()
            .is_some_and(|length| length > crate::MAX_TORRENT_FILE)
        {
            return Err("Torrent metadata is too large".into());
        }
        let mut bytes = Vec::new();
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|_| "Could not read torrent metadata")?
        {
            if bytes.len().saturating_add(chunk.len()) > crate::MAX_TORRENT_FILE as usize {
                return Err("Torrent metadata is too large".into());
            }
            bytes.extend_from_slice(&chunk);
        }
        return crate::metadata_from_bytes(&bytes).map_err(|error| error.to_string());
    }
    Err("Too many torrent metadata redirects".into())
}

pub async fn metadata(url: Url, dns: &DnsChoice, route: &Route) -> Result<crate::Meta, String> {
    tokio::time::timeout(TOTAL_TIMEOUT, fetch(url, dns, route))
        .await
        .map_err(|_| "Checking the torrent metadata link timed out".to_owned())?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_allows_public_http_sources() {
        assert!(parse("https://example.org/metadata.torrent").is_ok());
        assert!(parse("http://1.1.1.1/file").is_ok());
        assert!(parse("https://[2606:4700:4700::1111]/file").is_ok());
        for value in [
            "ftp://example.org/file",
            "https://user:secret@example.org/file",
            "http://localhost/file",
            "http://print-server/file",
            "http://demo.local/file",
            "http://demo.localhost./file",
            "http://127.1/file",
            "http://2130706433/file",
            "http://10.0.0.1/file",
            "http://169.254.169.254/file",
            "http://100.64.1.2/file",
            "http://192.0.2.1/file",
            "http://[::ffff:192.168.0.1]/file",
            "http://[fe80::a]/file",
            "http://[64:ff9b::a9fe:a9fe]/file",
            "http://[2002:a9fe:a9fe::]/file",
            "http://[2001:0::1]/file",
        ] {
            assert!(parse(value).is_err(), "{value}");
        }
    }

    #[test]
    fn redirects_are_revalidated_and_do_not_downgrade_tls() {
        let url = parse("https://example.org/first").unwrap();
        assert_eq!(
            redirect(&url, "/next#fragment").unwrap().as_str(),
            "https://example.org/next"
        );
        assert!(redirect(&url, "https://cdn.example.org/next").is_ok());
        assert!(redirect(&url, "http://example.org/next").is_err());
        assert!(redirect(&url, "//name:secret@example.org/next").is_err());
        assert!(redirect(&url, "//127.0.0.1/next").is_err());
    }
}
