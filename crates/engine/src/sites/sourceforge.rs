//! Recover a public SourceForge file's download page from an expired mirror URL.
//! The page issues a fresh mirror address for the same project and path.
use url::Url;

pub(crate) fn origin(url: &Url) -> Option<Url> {
    if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() || url.port().is_some() {
        return None;
    }
    let host = url.host_str()?;
    if host != "downloads.sourceforge.net" && !host.ends_with(".dl.sourceforge.net") {
        return None;
    }
    let path = url.path().strip_prefix("/project/")?;
    let (project, file) = path.split_once('/')?;
    if project.is_empty() || !project.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
        || file.is_empty() || file.ends_with('/') || file.split('/').any(|part| part.is_empty() || part == "." || part == "..") {
        return None;
    }
    Url::parse(&format!("https://sourceforge.net/projects/{project}/files/{file}/download")).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recovers_download_page_without_expired_token() {
        for host in ["downloads.sourceforge.net", "pilotfiber.dl.sourceforge.net"] {
            let input=Url::parse(&format!("https://{host}/project/crdroid/davinci/12.x/example%20file.zip?ts=expired&use_mirror=old")).unwrap();
            assert_eq!(origin(&input).unwrap().as_str(),"https://sourceforge.net/projects/crdroid/files/davinci/12.x/example%20file.zip/download");
        }
    }
    #[test]
    fn does_not_rewrite_other_sites_or_ambiguous_urls() {
        for input in ["https://downloads.sourceforge.net.evil.test/project/p/a.zip", "https://sourceforge.net/project/p/a.zip", "http://downloads.sourceforge.net/project/p/a.zip", "https://downloads.sourceforge.net/project/onlyproject", "https://user@downloads.sourceforge.net/project/p/a.zip"] {
            assert!(origin(&Url::parse(input).unwrap()).is_none(),"{input}");
        }
    }
}
