# Third-party notices

LamentMapper is built with open-source Rust crates listed in `Cargo.lock`.
Their license texts and notices remain governed by their respective projects.
Notable runtime components include:

- wxDragon 0.9.18 and wxWidgets, for the native Windows interface.
- Rodio 0.22.2 and its audio dependencies, for playback and Ogg Vorbis decoding.
- flexi_logger 0.31.10, for bounded rotating logs.
- Prism 0.17.3, dynamically loaded at runtime and distributed under its own
  license and notices from the official SDK.
- XChaCha20-Poly1305 and SHA-256 implementations from the RustCrypto projects.

The portable release also contains the Prism license/notice material staged
from its official SDK when available. Consult each upstream project for the
complete and authoritative license terms.
