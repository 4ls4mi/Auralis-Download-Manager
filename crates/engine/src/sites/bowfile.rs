//! Read Bowfile's public download countdown without running page scripts.
//! The resulting URL is the normal button target on the same share and origin.

use std::time::{Duration, SystemTime};

use reqwest::header::{HeaderMap, SET_COOKIE};
use url::Url;

use crate::html;

const HOST: &str = "bowfile.com";
const MAX_WAIT_SECONDS: u64 = 60;
const MAX_TOKEN_BYTES: usize = 2048;
const MAX_LINK_BYTES: usize = 8192;

fn https_url(url: &Url) -> bool {
    url.scheme() == "https"
        && url.username().is_empty()
        && url.password().is_none()
        && url.as_str().len() <= MAX_LINK_BYTES
}

fn token(url: &Url) -> Option<std::borrow::Cow<'_, str>> {
    if url.query()?.strip_prefix("pt=")?.contains('&') {
        return None;
    }
    let mut pairs = url.query_pairs();
    let (key, token) = pairs.next()?;
    (key == "pt"
        && pairs.next().is_none()
        && (1..=MAX_TOKEN_BYTES).contains(&token.len())
        && token.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'+' | b'/' | b'=' | b'-' | b'_')
        }))
    .then_some(token)
}

pub(crate) fn is_share(url: &Url) -> bool {
    https_url(url)
        && url.host_str() == Some(HOST)
        && url.path().strip_prefix('/').is_some_and(|id| {
            (4..=32).contains(&id.len()) && id.bytes().all(|byte| byte.is_ascii_alphanumeric())
        })
        && (url.query().is_none() || token(url).is_some())
}

pub(crate) fn is_file(url: &Url) -> bool {
    https_url(url)
        && url.fragment().is_none()
        && url.host_str().is_some_and(|host| {
            host.strip_suffix(".bowfile.com")
                .and_then(|prefix| prefix.strip_prefix("fs"))
                .is_some_and(|number| {
                    (1..=8).contains(&number.len())
                        && number.bytes().all(|byte| byte.is_ascii_digit())
                })
        })
        && url.path().strip_prefix("/token/").is_some_and(|path| {
            path.split('/')
                .all(|part| !part.is_empty() && !matches!(part, "." | ".."))
        })
}

/// The button may redirect to a Bowfile file server on the same HTTPS port.
pub(crate) fn is_file_redirect(at: &Url, next: &Url) -> bool {
    is_share(at) && is_file(next) && next.port_or_known_default() == at.port_or_known_default()
}

/// Reuse only the share host's current cookie for the same-origin countdown button.
/// The caller must keep it on that request and discard it before following the file redirect.
pub(crate) fn session_cookie(headers: &HeaderMap, wait: Duration) -> Option<String> {
    let mut session = None;
    for header in headers.get_all(SET_COOKIE) {
        let mut parts = header.to_str().ok()?.split(';');
        let pair = parts.next()?.trim();
        let Some(("filehosting", value)) = pair.split_once('=') else {
            continue;
        };
        if session.is_some()
            || !(1..=MAX_TOKEN_BYTES).contains(&value.len())
            || !value.bytes().all(|byte| {
                byte.is_ascii_alphanumeric()
                    || matches!(byte, b'+' | b'/' | b'=' | b'-' | b'_' | b'.')
            })
        {
            return None;
        }
        let mut root_path = false;
        let mut age = None;
        let mut expires = None;
        for attribute in parts {
            let (name, value) = attribute.split_once('=').unwrap_or((attribute, ""));
            let name = name.trim();
            let value = value.trim();
            if name.eq_ignore_ascii_case("domain") {
                return None;
            }
            if name.eq_ignore_ascii_case("path") {
                if root_path || value != "/" {
                    return None;
                }
                root_path = true;
            }
            if name.eq_ignore_ascii_case("max-age")
                && age
                    .replace(Duration::from_secs(value.parse().ok()?))
                    .is_some()
            {
                return None;
            }
            if name.eq_ignore_ascii_case("expires") && expires.replace(value).is_some() {
                return None;
            }
        }
        let valid_for_wait = match (age, expires) {
            (Some(age), _) => age > wait,
            (None, Some(expires)) => httpdate::parse_http_date(expires)
                .ok()
                .and_then(|expires| expires.duration_since(SystemTime::now()).ok())
                .is_some_and(|remaining| remaining > wait),
            (None, None) => true,
        };
        if !root_path || !valid_for_wait {
            return None;
        }
        session = Some(pair.to_owned());
    }
    session
}

/// The verified countdown publishes the download button at zero and advances once a second.
/// Decline pages whose structure or wait cannot be established.
pub(crate) fn target(at: &Url, page: &str) -> Option<(Duration, Url)> {
    if !is_share(at) || interactive_wall(page) {
        return None;
    }
    let lower = page.to_ascii_lowercase();
    let mut result = None;
    let mut after = 0;
    for (start, tag) in html::tags(page, "script") {
        if start < after || inside_comment(page, start) {
            continue;
        }
        let from = start + tag.len();
        let Some(close) = lower[from..].find("</script>") else {
            break;
        };
        let end = from + close;
        after = end + "</script>".len();
        let script = &page[from..end];
        if html::attribute(tag, "src").is_some()
            || html::attribute(tag, "type").is_some_and(|kind| {
                !matches!(kind.as_str(), "text/javascript" | "application/javascript")
            })
            || !script.contains("triggerFreeDownload")
            || !script.contains(".download-timer")
        {
            continue;
        }
        let Some((wait, address)) = timer(script) else {
            continue;
        };
        let next = Url::parse(&address).ok()?;
        if !is_share(&next)
            || next.fragment().is_some()
            || at.origin() != next.origin()
            || at.path() != next.path()
            || token(&next).is_none()
            || token(at) == token(&next)
            || result.is_some()
        {
            return None;
        }
        result = Some((wait, next));
    }
    result
}

fn inside_comment(page: &str, at: usize) -> bool {
    let before = &page[..at];
    before.rfind("<!--") > before.rfind("-->")
}

fn interactive_wall(page: &str) -> bool {
    html::tags(page, "form").any(|(at, tag)| {
        !inside_comment(page, at)
            && html::attribute(tag, "id")
                .is_some_and(|id| matches!(id.as_str(), "challenge-form" | "login-required"))
    }) || html::tags(page, "div").any(|(at, tag)| {
        !inside_comment(page, at)
            && (html::attribute(tag, "id").as_deref() == Some("login-required")
                || (html::attribute(tag, "data-sitekey").is_some()
                    && html::attribute(tag, "class").is_some_and(|classes| {
                        classes.split_ascii_whitespace().any(|class| {
                            matches!(class, "g-recaptcha" | "h-captcha" | "cf-turnstile")
                        })
                    })))
    }) || html::tags(page, "script").any(|(at, tag)| {
        !inside_comment(page, at)
            && html::attribute(tag, "src").is_some_and(|src| {
                src.starts_with("/cdn-cgi/challenge-platform/")
                    || src.starts_with("https://challenges.cloudflare.com/turnstile/")
            })
    })
}

fn timer(script: &str) -> Option<(Duration, String)> {
    let tokens = javascript_tokens(script)?;
    let declaration = after_unique(&tokens, &["var", "seconds", "="])?;
    let [seconds, ";", ..] = declaration else {
        return None;
    };
    let seconds: u64 = seconds.parse().ok()?;
    if seconds > MAX_WAIT_SECONDS
        || after_unique(&tokens, &["function", "triggerFreeDownload", "(", ")", "{"]).is_none()
        || !tokens.windows(6).any(|part| {
            matches!(
                part,
                [
                    "setInterval",
                    "(",
                    "'display()'" | "\"display()\"",
                    ",",
                    "1000",
                    ")"
                ]
            )
        })
    {
        return None;
    }
    let display = block(after_unique(
        &tokens,
        &["function", "display", "(", ")", "{"],
    )?)?;
    if after_unique(display, &["seconds", "-", "-", ";"]).is_none() {
        return None;
    }
    let ready = block(after_unique(
        display,
        &["if", "(", "seconds", "=", "=", "0", ")", "{"],
    )?)?;
    let [
        "$",
        "(",
        "'.download-timer'" | "\".download-timer\"",
        ")",
        ".",
        "html",
        "(",
        literal,
        ")",
        ";",
    ] = ready
    else {
        return None;
    };
    let button: String = serde_json::from_str(literal).ok()?;
    let mut tags = html::tags(&button, "button");
    let (0, tag) = tags.next()? else {
        return None;
    };
    if tags.next().is_some()
        || html::attribute(tag, "id").as_deref() != Some("dl")
        || html::attribute(tag, "disabled").is_some()
    {
        return None;
    }
    let action = html::decode(&html::attribute(tag, "onclick")?);
    let parts = javascript_tokens(&action)?;
    let ["window", ".", "location", ".", "href", "=", address, ";"] = parts.as_slice() else {
        return None;
    };
    let address = serde_json::from_str(address).ok()?;
    Some((Duration::from_secs(seconds), address))
}

fn after_unique<'a>(tokens: &'a [&'a str], pattern: &[&str]) -> Option<&'a [&'a str]> {
    let mut depth: usize = 0;
    let mut tail = None;
    for (index, token) in tokens.iter().enumerate() {
        if depth == 0 && tokens[index..].starts_with(pattern) {
            if tail.replace(&tokens[index + pattern.len()..]).is_some() {
                return None;
            }
        }
        match *token {
            "{" => depth += 1,
            "}" => depth = depth.checked_sub(1)?,
            _ => {}
        }
    }
    tail.filter(|_| depth == 0)
}

fn block<'a>(tokens: &'a [&'a str]) -> Option<&'a [&'a str]> {
    let mut depth = 0;
    for (index, token) in tokens.iter().enumerate() {
        match *token {
            "{" => depth += 1,
            "}" if depth == 0 => return Some(&tokens[..index]),
            "}" => depth -= 1,
            _ => {}
        }
    }
    None
}

/// Find literal JavaScript tokens for this fixed script shape. Comments and string content
/// do not contribute declarations, selectors, or control flow.
fn javascript_tokens(mut text: &str) -> Option<Vec<&str>> {
    let mut tokens = Vec::new();
    loop {
        text = text.trim_ascii_start();
        let Some(first) = text.bytes().next() else {
            break;
        };
        if let Some(comment) = text.strip_prefix("//") {
            text = comment.split_once('\n').map_or("", |(_, rest)| rest);
            continue;
        }
        if let Some(comment) = text.strip_prefix("/*") {
            text = comment.split_once("*/")?.1;
            continue;
        }
        let word = |byte: u8| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'$');
        let end = if matches!(first, b'\'' | b'"' | 0x60) {
            let mut escaped = false;
            text.bytes().enumerate().skip(1).find_map(|(index, byte)| {
                if escaped {
                    escaped = false;
                } else if byte == b'\\' {
                    escaped = true;
                } else if byte == first {
                    return Some(index + 1);
                }
                None
            })?
        } else if word(first) {
            text.bytes().take_while(|byte| word(*byte)).count()
        } else {
            text.chars().next()?.len_utf8()
        };
        let (token, rest) = text.split_at(end);
        tokens.push(token);
        text = rest;
    }
    Some(tokens)
}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::header::HeaderValue;

    fn url(value: &str) -> Url {
        Url::parse(value).unwrap()
    }

    fn page(seconds: u64, address: &str) -> String {
        let address = serde_json::to_string(address).unwrap();
        let button = serde_json::to_string(&format!(
            "<button class='btn btn--primary' id='dl' onclick='window.location.href = {address};'>Download</button>"
        ))
        .unwrap();
        format!(
            r#"<script>
            var seconds = {seconds};
            var started = false;
            function display() {{
                $('.btn-free-element').hide();
                $('.download-timer').show();
                if (seconds == 0) {{
                    $('.download-timer').html({button});
                }} else {{
                    $('.download-timer-seconds').html(seconds);
                }}
                seconds--;
            }}
            function triggerFreeDownload() {{
                display();
                setInterval('display()', 1000);
            }}
        </script>"#
        )
    }

    #[test]
    fn shares_and_file_servers_are_restricted() {
        let share = url("https://bowfile.com:8443/abcd?pt=Beginning%2B");
        assert!(is_share(&share));
        assert!(is_share(&url("https://bowfile.com/abcd")));
        assert!(is_share(&url(
            "https://bowfile.com/abcd?pt=Beginning#popup1"
        )));
        for wrong in [
            "http://bowfile.com/abcd",
            "https://bowfile.com.example.test/abcd",
            "https://user@bowfile.com/abcd",
            "https://bowfile.com/abcd/other",
            "https://bowfile.com/abcd?pt=test&",
            "https://bowfile.com/abcd?pt=%00",
            "https://bowfile.com/abcd?pt=",
        ] {
            assert!(!is_share(&url(wrong)));
        }
        let file = url("https://fs21.bowfile.com:8443/token/fixture");
        assert!(is_file(&file) && is_file_redirect(&share, &file));
        for wrong in [
            "https://fs21.bowfile.com/token/fixture",
            "https://fs21.bowfile.com.example.test:8443/token/fixture",
            "https://fs-test.bowfile.com:8443/token/fixture",
            "https://fs21.bowfile.com:8443/token/",
            "https://fs21.bowfile.com:8443/token/fixture#ignored",
            "https://fs21.bowfile.com:8443/other/fixture",
        ] {
            assert!(!is_file_redirect(&share, &url(wrong)));
        }
    }

    #[test]
    fn the_public_button_keeps_the_entire_countdown() {
        let share = url("https://bowfile.com:8443/abcd?pt=Beginning%2B#popup1");
        let next = "https://bowfile.com:8443/abcd?pt=Ending%2B%2F%3D";
        for wait in [3, 19, MAX_WAIT_SECONDS] {
            assert_eq!(
                target(&share, &page(wait, next)),
                Some((Duration::from_secs(wait), url(next))),
            );
        }
        assert!(target(&share, &page(MAX_WAIT_SECONDS + 1, next)).is_none());
        assert!(target(&share, &page(3, next).replace("1000", "2000")).is_none());
    }

    #[test]
    fn same_share_origin_and_a_new_token_are_required() {
        let share = url("https://bowfile.com:8443/abcd?pt=Beginning");
        for wrong in [
            "https://bowfile.com:8443/abcd?pt=%42eginning",
            "https://bowfile.com:8444/abcd?pt=Ending",
            "https://bowfile.com:8443/efgh?pt=Ending",
            "https://bowfile.com:8443/abcd",
            "https://bowfile.com:8443/abcd?pt=Ending&pt=Other",
            "https://bowfile.com:8443/abcd?pt=Ending#ignored",
            "https://fs21.bowfile.com:8443/abcd?pt=Ending",
            "https://bad.example.test:8443/abcd?pt=Ending",
        ] {
            assert!(target(&share, &page(3, wrong)).is_none());
        }
    }

    #[test]
    fn unrelated_links_comments_and_login_widgets_are_not_downloads() {
        let share = url("https://bowfile.com/abcd?pt=Beginning");
        let next = "https://bowfile.com/abcd?pt=Ending";
        let valid = page(3, next);
        let with_ad = format!(
            r#"<a href="https://other.example.test/advertising">An ad</a>
            <script>const ad = "triggerFreeDownload .download-timer";</script>
            <!-- <div class="g-recaptcha" data-sitekey="dummy"></div> -->
            {valid}"#
        );
        assert_eq!(target(&share, &with_ad).unwrap().1, url(next));
        assert!(target(&share, &format!("<!--{valid}-->")).is_none());
        assert!(target(&share, &valid.replace("id='dl'", "id='other'")).is_none());
        for protection in [
            "<form id='challenge-form'></form>",
            "<div class='cf-turnstile' data-sitekey='dummy'></div>",
            "<div id='login-required'></div>",
        ] {
            assert!(target(&share, &format!("{protection}{valid}")).is_none());
        }
    }

    #[test]
    fn session_cookies_must_last_through_the_wait_and_stay_on_the_share_host() {
        let wait = Duration::from_secs(3);
        let cookie = |attributes| {
            let mut headers = HeaderMap::new();
            headers.append(
                SET_COOKIE,
                HeaderValue::from_static("preference=irrelevant; Path=/"),
            );
            headers.append(
                SET_COOKIE,
                HeaderValue::from_str(&format!("filehosting=Session123; {attributes}")).unwrap(),
            );
            session_cookie(&headers, wait)
        };
        for attributes in [
            "Path=/; HttpOnly",
            "path=/; Max-Age=14; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure",
            "Path=/; Expires=Tue, 19 Jan 2038 03:14:07 GMT",
        ] {
            assert_eq!(
                cookie(attributes).as_deref(),
                Some("filehosting=Session123")
            );
        }
        for attributes in [
            "Path=/; Domain=bowfile.com",
            "Path=/elsewhere",
            "Max-Age=10",
            "Path=/; Max-Age=-1",
            "Path=/; Max-Age=3",
            "Path=/; Max-Age=10; Max-Age=1",
            "Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT",
        ] {
            assert!(cookie(attributes).is_none());
        }
    }
}
