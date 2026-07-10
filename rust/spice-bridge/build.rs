use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    // Locate the spice-client-glib-2.0 library using pkg-config
    let library = pkg_config::Config::new()
        .atleast_version("0.35")
        .probe("spice-client-glib-2.0")
        .expect("Failed to find spice-client-glib-2.0 via pkg-config");

    // Generate bindings
    let mut builder = bindgen::Builder::default()
        .header("wrapper.h")
        // Disable layout tests since opaque GLib types cause `rustc` overflow errors
        .layout_tests(false)
        .opaque_type(".*_G.*Class")
        .opaque_type(".*_G.*Iface")
        .opaque_type(".*_G.*Interface")
        .opaque_type(".*_Spice.*Class")
        // Tell cargo to invalidate the built crate whenever any of the included header files changed.
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()));

    // Pass the include paths from pkg-config to bindgen
    for path in library.include_paths {
        builder = builder.clang_arg(format!("-I{}", path.display()));
    }

    let bindings = builder
        .generate()
        .expect("Unable to generate bindings for spice-client-glib");

    // Write the bindings to the $OUT_DIR/bindings.rs file.
    let out_path = PathBuf::from(env::var("OUT_DIR").unwrap());
    bindings
        .write_to_file(out_path.join("bindings.rs"))
        .expect("Couldn't write bindings!");
}
