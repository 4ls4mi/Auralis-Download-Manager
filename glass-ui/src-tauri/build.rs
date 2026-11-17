fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        cc::Build::new().cpp(true).file("src/water_surface.cpp").compile("mhg_water_surface");
        println!("cargo:rustc-link-lib=d2d1");
        println!("cargo:rustc-link-lib=comctl32");
        println!("cargo:rustc-link-lib=gdi32");
        println!("cargo:rerun-if-changed=src/water_surface.cpp");
    }
    tauri_build::build();
}
