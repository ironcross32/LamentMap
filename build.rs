use embed_manifest::manifest::{ActiveCodePage, DpiAwareness, HeapType, Setting, SupportedOS::*};
use embed_manifest::{embed_manifest, new_manifest};

fn main() {
    let target = std::env::var("TARGET").unwrap_or_default();
    if target.contains("windows") {
        let manifest = new_manifest("LamentMapper.AccessibleWildernessMap")
            .supported_os(Windows7..=Windows10)
            .active_code_page(ActiveCodePage::Utf8)
            .heap_type(HeapType::SegmentHeap)
            .dpi_awareness(DpiAwareness::PerMonitorV2)
            .long_path_aware(Setting::Enabled);
        if let Err(error) = embed_manifest(manifest) {
            panic!("could not embed required Windows application manifest: {error}");
        }
    }
    println!("cargo:rerun-if-changed=build.rs");
}
