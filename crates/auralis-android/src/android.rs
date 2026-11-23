#![allow(
    unsafe_code,
    reason = "The JVM looks up the exported native symbols by name."
)]

use std::path::Path;
use std::sync::{Mutex, OnceLock, PoisonError};

use jni::errors::{Result as JniResult, ThrowRuntimeExAndDefault};
use jni::objects::{JClass, JObject, JString};
use jni::{Env, EnvUnowned, jni_sig, jni_str, sys::jint};

use crate::downloader::Downloader;

static DOWNLOADER: OnceLock<Downloader> = OnceLock::new();
static INITIALIZING: Mutex<()> = Mutex::new(());

fn downloader() -> Result<&'static Downloader, String> {
    DOWNLOADER
        .get()
        .ok_or_else(|| "The download engine has not been initialized.".into())
}

fn reply<'local>(env: &mut Env<'local>, result: Result<(), String>) -> JniResult<JString<'local>> {
    match result {
        Ok(()) => Ok(JString::null()),
        Err(error) => env.new_string(error),
    }
}

fn initialize(env: &mut Env<'_>, context: JObject<'_>) -> JniResult<Result<(), String>> {
    let _guard = INITIALIZING.lock().unwrap_or_else(PoisonError::into_inner);
    if DOWNLOADER.get().is_some() {
        return Ok(Ok(()));
    }
    if context.is_null() {
        return Ok(Err("Android application context is unavailable.".into()));
    }
    let application = env
        .call_method(
            &context,
            jni_str!("getApplicationContext"),
            jni_sig!(() -> android.content.Context),
            &[],
        )?
        .l()?;
    if application.is_null() {
        return Ok(Err("Android application context is unavailable.".into()));
    }
    let files = env
        .call_method(
            &application,
            jni_str!("getFilesDir"),
            jni_sig!(() -> java.io.File),
            &[],
        )?
        .l()?;
    if files.is_null() {
        return Ok(Err("Android app storage is unavailable.".into()));
    }
    let path = env
        .call_method(
            &files,
            jni_str!("getAbsolutePath"),
            jni_sig!(() -> JString),
            &[],
        )?
        .l()?;
    let path = env.cast_local::<JString>(path)?.try_to_string(env)?;
    let downloader = match Downloader::new(Path::new(&path)) {
        Ok(downloader) => downloader,
        Err(error) => return Ok(Err(error)),
    };
    rustls_platform_verifier::android::init_with_env(env, application)?;
    let _ = DOWNLOADER.set(downloader);
    Ok(Ok(()))
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_alsami_auralis_NativeDownloader_initialize<'local>(
    mut unowned: EnvUnowned<'local>,
    _class: JClass<'local>,
    context: JObject<'local>,
) -> JString<'local> {
    unowned
        .with_env(|env| -> JniResult<_> {
            let result = initialize(env, context)?;
            reply(env, result)
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_alsami_auralis_NativeDownloader_start<'local>(
    mut unowned: EnvUnowned<'local>,
    _class: JClass<'local>,
    id: JString<'local>,
    url: JString<'local>,
    target: JString<'local>,
    connections: jint,
) -> JString<'local> {
    unowned
        .with_env(|env| -> JniResult<_> {
            if id.is_null() || url.is_null() || target.is_null() {
                return env.new_string("Download link, identifier, or destination is missing.");
            }
            let id = id.try_to_string(env)?;
            let url = url.try_to_string(env)?;
            let target = target.try_to_string(env)?;
            let result = downloader()
                .and_then(|engine| engine.start(id, &url, Path::new(&target), connections));
            reply(env, result)
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_alsami_auralis_NativeDownloader_snapshot<'local>(
    mut unowned: EnvUnowned<'local>,
    _class: JClass<'local>,
    id: JString<'local>,
) -> JString<'local> {
    unowned
        .with_env(|env| -> JniResult<_> {
            if id.is_null() {
                return Ok(JString::null());
            }
            let id = id.try_to_string(env)?;
            if let Some(progress) = DOWNLOADER.get().and_then(|engine| engine.snapshot(&id)) {
                if let Ok(json) = serde_json::to_string(&progress) {
                    return env.new_string(json);
                }
            }
            Ok(JString::null())
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_alsami_auralis_NativeDownloader_pause<'local>(
    mut unowned: EnvUnowned<'local>,
    _class: JClass<'local>,
    id: JString<'local>,
) -> JString<'local> {
    unowned
        .with_env(|env| -> JniResult<_> {
            if id.is_null() {
                return env.new_string("Download not found.");
            }
            let id = id.try_to_string(env)?;
            reply(env, downloader().and_then(|engine| engine.pause(&id)))
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_com_alsami_auralis_NativeDownloader_forget<'local>(
    mut unowned: EnvUnowned<'local>,
    _class: JClass<'local>,
    id: JString<'local>,
) {
    unowned
        .with_env(|env| -> JniResult<_> {
            if let Some(engine) = DOWNLOADER.get()
                && !id.is_null()
            {
                engine.forget(&id.try_to_string(env)?);
            }
            Ok(())
        })
        .resolve::<ThrowRuntimeExAndDefault>();
}
