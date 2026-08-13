use lament_mapper::audio::{SoundPack, build_pack};
use std::path::PathBuf;

fn main() {
    let mut arguments = std::env::args_os().skip(1);
    let command = arguments.next();
    let result = match command.as_deref().and_then(|value| value.to_str()) {
        Some("--validate") => {
            let pack = arguments.next().map(PathBuf::from);
            if pack.is_none() || arguments.next().is_some() {
                usage();
            }
            SoundPack::load(&pack.unwrap()).map(|_| "sound pack is complete".to_owned())
        }
        Some(_) => {
            let source = PathBuf::from(command.unwrap());
            let output = arguments.next().map(PathBuf::from);
            if output.is_none() || arguments.next().is_some() {
                usage();
            }
            let output = output.unwrap();
            build_pack(&source, &output)
                .and_then(|()| SoundPack::load(&output).map(|_| ()))
                .map(|()| format!("built and validated {}", output.display()))
        }
        None => usage(),
    };
    if let Err(error) = &result {
        eprintln!("could not build sound pack: {error}");
        std::process::exit(1);
    }
    println!("{}", result.unwrap());
}

fn usage() -> ! {
    eprintln!("usage: pack-sounds <source-directory> <sounds.pack> | pack-sounds --validate <sounds.pack>");
    std::process::exit(2);
}
