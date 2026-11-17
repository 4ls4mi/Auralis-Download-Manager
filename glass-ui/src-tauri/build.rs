fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        cc::Build::new().cpp(true).flag_if_supported("/std:c++20").file("src/water_surface.cpp").file("src/water_d3d11.cpp").file("src/water_composition.cpp").compile("mhg_water_surface");
        println!("cargo:rustc-link-lib=d2d1");
        println!("cargo:rustc-link-lib=comctl32");
        println!("cargo:rustc-link-lib=gdi32");
        println!("cargo:rustc-link-lib=d3d11");
        println!("cargo:rustc-link-lib=d3dcompiler");
        println!("cargo:rustc-link-lib=windowsapp");
        println!("cargo:rustc-link-lib=dwmapi");
        println!("cargo:rustc-link-lib=CoreMessaging");
        println!("cargo:rerun-if-changed=src/water_composition.cpp");
        println!("cargo:rerun-if-changed=src/water_d3d11.cpp");
        println!("cargo:rerun-if-changed=src/water_surface.cpp");
    }
    tauri_build::build();
}
