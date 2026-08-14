use crate::feedback::SoundOutput;
use crate::model::Terrain;
use chacha20poly1305::aead::{Aead, KeyInit, Payload};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};
use rodio::{Decoder, DeviceSinkBuilder, MixerDeviceSink, Player};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Cursor;
use std::path::Path;
use thiserror::Error;

const MAGIC: &[u8; 8] = b"LMAPSNDS";
const PACK_VERSION: u16 = 1;
const HEADER_LENGTH: usize = 8 + 2 + 24;
const KEY_LEFT: [u8; 32] = [
    0x51, 0xa7, 0x19, 0x33, 0xe2, 0x0d, 0x91, 0x68, 0x44, 0xb3, 0x7a, 0x10, 0x29, 0xc0, 0x5f, 0xae, 0x12,
    0x67, 0xf1, 0x8b, 0x3e, 0xd4, 0x70, 0x2a, 0x99, 0x05, 0xce, 0x61, 0x47, 0xbb, 0x84, 0x1c,
];
const KEY_RIGHT: [u8; 32] = [
    0xed, 0x20, 0x73, 0xfa, 0x49, 0xb8, 0x0e, 0x91, 0xd2, 0x54, 0x13, 0xa7, 0xb6, 0x1f, 0xc8, 0x65, 0x80,
    0xda, 0x34, 0x16, 0xa1, 0x4b, 0xee, 0x93, 0x07, 0xbc, 0x52, 0xf8, 0x30, 0x6d, 0x19, 0xc3,
];

pub const EXTRA_CUE_IDS: [&str; 5] = ["landmark", "player", "boundary", "unseen", "new_map"];

pub fn required_cue_ids() -> Vec<&'static str> {
    Terrain::ALL
        .iter()
        .map(|terrain| terrain.cue_id())
        .chain(EXTRA_CUE_IDS)
        .collect()
}

fn pack_key() -> [u8; 32] {
    let mut key = [0u8; 32];
    for index in 0..key.len() {
        key[index] = KEY_LEFT[index] ^ KEY_RIGHT[index];
    }
    key
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    cues: Vec<ManifestCue>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct ManifestCue {
    id: String,
    offset: u64,
    length: u64,
    sha256: String,
}

#[derive(Debug, Error)]
pub enum PackError {
    #[error("sound pack I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("sound pack has an invalid header")]
    Header,
    #[error("unsupported sound pack version {0}")]
    Version(u16),
    #[error("sound pack authentication failed")]
    Authentication,
    #[error("sound pack manifest is invalid: {0}")]
    Manifest(String),
    #[error("sound pack has duplicate cue {0}")]
    DuplicateCue(String),
    #[error("sound pack is missing cue {0}")]
    MissingCue(String),
    #[error("sound pack contains unknown cue {0}")]
    UnknownCue(String),
    #[error("sound pack cue ranges are invalid")]
    InvalidRange,
    #[error("sound pack cue {0} has an invalid SHA-256 digest")]
    Hash(String),
    #[error("sound pack cue {0} is not valid Ogg Vorbis audio")]
    Decode(String),
    #[error("sound pack encryption failed")]
    Encryption,
}

#[derive(Default)]
pub struct SoundPack {
    cues: HashMap<String, Vec<u8>>,
}

impl SoundPack {
    pub fn load(path: &Path) -> Result<Self, PackError> {
        Self::from_bytes(&fs::read(path)?)
    }

    pub fn from_bytes(encoded: &[u8]) -> Result<Self, PackError> {
        let plaintext = decrypt(encoded, &pack_key())?;
        if plaintext.len() < 4 {
            return Err(PackError::Manifest("missing manifest length".into()));
        }
        let manifest_length = u32::from_le_bytes(plaintext[..4].try_into().unwrap()) as usize;
        let data_start = 4usize
            .checked_add(manifest_length)
            .ok_or(PackError::InvalidRange)?;
        if data_start > plaintext.len() {
            return Err(PackError::InvalidRange);
        }
        let manifest: Manifest = serde_json::from_slice(&plaintext[4..data_start])
            .map_err(|error| PackError::Manifest(error.to_string()))?;
        let data = &plaintext[data_start..];
        validate_manifest(&manifest, data.len())?;
        let mut cues = HashMap::new();
        for cue in manifest.cues {
            let start = usize::try_from(cue.offset).map_err(|_| PackError::InvalidRange)?;
            let length = usize::try_from(cue.length).map_err(|_| PackError::InvalidRange)?;
            let bytes = data[start..start + length].to_vec();
            if hex::encode(Sha256::digest(&bytes)) != cue.sha256 {
                return Err(PackError::Hash(cue.id));
            }
            Decoder::try_from(Cursor::new(bytes.clone())).map_err(|_| PackError::Decode(cue.id.clone()))?;
            cues.insert(cue.id, bytes);
        }
        Ok(Self { cues })
    }

    pub fn is_complete(&self) -> bool {
        required_cue_ids().iter().all(|id| self.cues.contains_key(*id))
    }

    fn cue(&self, id: &str) -> Option<&[u8]> {
        self.cues.get(id).map(Vec::as_slice)
    }
}

fn validate_manifest(manifest: &Manifest, data_length: usize) -> Result<(), PackError> {
    let required: HashSet<_> = required_cue_ids().into_iter().collect();
    let mut found = HashSet::new();
    let mut expected_offset = 0usize;
    for cue in &manifest.cues {
        if !required.contains(cue.id.as_str()) {
            return Err(PackError::UnknownCue(cue.id.clone()));
        }
        if !found.insert(cue.id.as_str()) {
            return Err(PackError::DuplicateCue(cue.id.clone()));
        }
        let offset = usize::try_from(cue.offset).map_err(|_| PackError::InvalidRange)?;
        let length = usize::try_from(cue.length).map_err(|_| PackError::InvalidRange)?;
        if length == 0 || offset != expected_offset {
            return Err(PackError::InvalidRange);
        }
        expected_offset = offset.checked_add(length).ok_or(PackError::InvalidRange)?;
        if expected_offset > data_length {
            return Err(PackError::InvalidRange);
        }
    }
    if expected_offset != data_length {
        return Err(PackError::InvalidRange);
    }
    for id in required {
        if !found.contains(id) {
            return Err(PackError::MissingCue(id.into()));
        }
    }
    Ok(())
}

fn decrypt(encoded: &[u8], key: &[u8; 32]) -> Result<Vec<u8>, PackError> {
    if encoded.len() < HEADER_LENGTH || &encoded[..8] != MAGIC {
        return Err(PackError::Header);
    }
    let version = u16::from_le_bytes(encoded[8..10].try_into().unwrap());
    if version != PACK_VERSION {
        return Err(PackError::Version(version));
    }
    let cipher = XChaCha20Poly1305::new(Key::from_slice(key));
    cipher
        .decrypt(
            XNonce::from_slice(&encoded[10..HEADER_LENGTH]),
            Payload {
                msg: &encoded[HEADER_LENGTH..],
                aad: &encoded[..10],
            },
        )
        .map_err(|_| PackError::Authentication)
}

pub fn build_pack(source_directory: &Path, output: &Path) -> Result<(), PackError> {
    let mut data = Vec::new();
    let mut cues = Vec::new();
    for id in required_cue_ids() {
        let bytes = fs::read(source_directory.join(format!("{id}.ogg")))?;
        Decoder::try_from(Cursor::new(bytes.clone())).map_err(|_| PackError::Decode(id.into()))?;
        cues.push(ManifestCue {
            id: id.into(),
            offset: data.len() as u64,
            length: bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(&bytes)),
        });
        data.extend(bytes);
    }
    let manifest =
        serde_json::to_vec(&Manifest { cues }).map_err(|error| PackError::Manifest(error.to_string()))?;
    let manifest_length = u32::try_from(manifest.len()).map_err(|_| PackError::InvalidRange)?;
    let mut plaintext = Vec::with_capacity(4 + manifest.len() + data.len());
    plaintext.extend(manifest_length.to_le_bytes());
    plaintext.extend(manifest);
    plaintext.extend(data);
    let nonce: [u8; 24] = rand::random();
    let mut header = Vec::from(*MAGIC);
    header.extend(PACK_VERSION.to_le_bytes());
    let cipher = XChaCha20Poly1305::new(Key::from_slice(&pack_key()));
    let ciphertext = cipher
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: &plaintext,
                aad: &header,
            },
        )
        .map_err(|_| PackError::Encryption)?;
    let mut encoded = header;
    encoded.extend(nonce);
    encoded.extend(ciphertext);
    fs::write(output, encoded)?;
    Ok(())
}

pub struct AudioEngine {
    pack: Option<SoundPack>,
    _device: Option<MixerDeviceSink>,
    navigation: Vec<Player>,
    notification: Option<Player>,
    warned_missing: HashSet<String>,
}

impl AudioEngine {
    pub fn load(pack_path: &Path) -> Self {
        let pack = match SoundPack::load(pack_path) {
            Ok(pack) => Some(pack),
            Err(error) => {
                log::warn!("sounds unavailable: {error}");
                None
            }
        };
        match DeviceSinkBuilder::open_default_sink() {
            Ok(device) => {
                let navigation = (0..2).map(|_| Player::connect_new(device.mixer())).collect();
                let notification = Player::connect_new(device.mixer());
                Self {
                    pack,
                    _device: Some(device),
                    navigation,
                    notification: Some(notification),
                    warned_missing: HashSet::new(),
                }
            }
            Err(error) => {
                log::warn!("audio output unavailable: {error}");
                Self {
                    pack,
                    _device: None,
                    navigation: Vec::new(),
                    notification: None,
                    warned_missing: HashSet::new(),
                }
            }
        }
    }

    fn play(&mut self, id: &str, navigation: bool) {
        let Some(bytes) = self.pack.as_ref().and_then(|pack| pack.cue(id)) else {
            if self.warned_missing.insert(id.into()) {
                log::warn!("sound cue unavailable: {id}");
            }
            return;
        };
        let Ok(source) = Decoder::try_from(Cursor::new(bytes.to_vec())) else {
            if self.warned_missing.insert(id.into()) {
                log::warn!("sound cue could not be decoded: {id}");
            }
            return;
        };
        let player = if navigation {
            self.navigation.first()
        } else {
            self.notification.as_ref()
        };
        if let Some(player) = player {
            player.stop();
            player.append(source);
        }
    }

    fn play_navigation(&mut self, cue_ids: &[&str]) {
        let mut sources = Vec::with_capacity(cue_ids.len().min(self.navigation.len()));
        for id in cue_ids.iter().take(self.navigation.len()) {
            let Some(bytes) = self.pack.as_ref().and_then(|pack| pack.cue(id)) else {
                if self.warned_missing.insert((*id).into()) {
                    log::warn!("sound cue unavailable: {id}");
                }
                sources.push(None);
                continue;
            };
            let Ok(source) = Decoder::try_from(Cursor::new(bytes.to_vec())) else {
                if self.warned_missing.insert((*id).into()) {
                    log::warn!("sound cue could not be decoded: {id}");
                }
                sources.push(None);
                continue;
            };
            sources.push(Some(source));
        }

        for player in &self.navigation {
            player.stop();
        }
        for (player, source) in self.navigation.iter().zip(sources) {
            if let Some(source) = source {
                player.append(source);
            }
        }
    }
}

impl SoundOutput for AudioEngine {
    fn navigation(&mut self, cue_ids: &[&str]) {
        self.play_navigation(cue_ids);
    }
    fn notification(&mut self, cue_id: &str) {
        self.play(cue_id, false);
    }
    fn is_complete(&self) -> bool {
        self.pack.as_ref().is_some_and(SoundPack::is_complete) && self._device.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode_plaintext(plaintext: &[u8], key: &[u8; 32]) -> Vec<u8> {
        let nonce = [7u8; 24];
        let mut header = Vec::from(*MAGIC);
        header.extend(PACK_VERSION.to_le_bytes());
        let ciphertext = XChaCha20Poly1305::new(Key::from_slice(key))
            .encrypt(
                XNonce::from_slice(&nonce),
                Payload {
                    msg: plaintext,
                    aad: &header,
                },
            )
            .unwrap();
        header.extend(nonce);
        header.extend(ciphertext);
        header
    }

    fn encode_manifest(manifest: &Manifest, data: &[u8]) -> Vec<u8> {
        let json = serde_json::to_vec(manifest).unwrap();
        let mut plaintext = Vec::new();
        plaintext.extend((json.len() as u32).to_le_bytes());
        plaintext.extend(json);
        plaintext.extend(data);
        encode_plaintext(&plaintext, &pack_key())
    }

    #[test]
    fn defines_exactly_thirty_unique_stable_cues() {
        let ids = required_cue_ids();
        assert_eq!(ids.len(), 30);
        assert_eq!(ids.iter().copied().collect::<HashSet<_>>().len(), 30);
    }

    #[test]
    fn rejects_bad_headers_versions_and_authentication() {
        assert!(matches!(SoundPack::from_bytes(b"short"), Err(PackError::Header)));
        let mut bytes = vec![0u8; HEADER_LENGTH + 16];
        bytes[..8].copy_from_slice(MAGIC);
        bytes[8..10].copy_from_slice(&2u16.to_le_bytes());
        assert!(matches!(
            SoundPack::from_bytes(&bytes),
            Err(PackError::Version(2))
        ));
        bytes[8..10].copy_from_slice(&PACK_VERSION.to_le_bytes());
        assert!(matches!(
            SoundPack::from_bytes(&bytes),
            Err(PackError::Authentication)
        ));
    }

    #[test]
    fn decrypts_valid_ciphertext_and_rejects_wrong_key_or_changes() {
        let plaintext = b"authenticated pack body";
        let encoded = encode_plaintext(plaintext, &pack_key());
        assert_eq!(decrypt(&encoded, &pack_key()).unwrap(), plaintext);
        assert!(matches!(
            decrypt(&encoded, &[0u8; 32]),
            Err(PackError::Authentication)
        ));
        let mut changed = encoded;
        *changed.last_mut().unwrap() ^= 1;
        assert!(matches!(
            decrypt(&changed, &pack_key()),
            Err(PackError::Authentication)
        ));
    }

    #[test]
    fn validates_required_ids_uniqueness_and_contiguous_ranges() {
        assert!(matches!(
            validate_manifest(&Manifest { cues: vec![] }, 0),
            Err(PackError::MissingCue(_))
        ));
        let unknown = Manifest {
            cues: vec![ManifestCue {
                id: "not_a_cue".into(),
                offset: 0,
                length: 1,
                sha256: "00".into(),
            }],
        };
        assert!(matches!(
            validate_manifest(&unknown, 1),
            Err(PackError::UnknownCue(_))
        ));
        let duplicate = Manifest {
            cues: vec![
                ManifestCue {
                    id: "ocean".into(),
                    offset: 0,
                    length: 1,
                    sha256: "00".into(),
                },
                ManifestCue {
                    id: "ocean".into(),
                    offset: 1,
                    length: 1,
                    sha256: "00".into(),
                },
            ],
        };
        assert!(matches!(
            validate_manifest(&duplicate, 2),
            Err(PackError::DuplicateCue(_))
        ));
        let bad_range = Manifest {
            cues: vec![ManifestCue {
                id: "ocean".into(),
                offset: 1,
                length: 1,
                sha256: "00".into(),
            }],
        };
        assert!(matches!(
            validate_manifest(&bad_range, 2),
            Err(PackError::InvalidRange)
        ));
    }

    #[test]
    fn rejects_bad_hashes_and_invalid_ogg_data() {
        let data = vec![0u8; required_cue_ids().len()];
        let cues = required_cue_ids()
            .into_iter()
            .enumerate()
            .map(|(offset, id)| ManifestCue {
                id: id.into(),
                offset: offset as u64,
                length: 1,
                sha256: "incorrect".into(),
            })
            .collect();
        let encoded = encode_manifest(&Manifest { cues }, &data);
        assert!(matches!(SoundPack::from_bytes(&encoded), Err(PackError::Hash(_))));

        let digest = hex::encode(Sha256::digest([0u8]));
        let cues = required_cue_ids()
            .into_iter()
            .enumerate()
            .map(|(offset, id)| ManifestCue {
                id: id.into(),
                offset: offset as u64,
                length: 1,
                sha256: digest.clone(),
            })
            .collect();
        let encoded = encode_manifest(&Manifest { cues }, &data);
        assert!(matches!(
            SoundPack::from_bytes(&encoded),
            Err(PackError::Decode(_))
        ));
    }
}
