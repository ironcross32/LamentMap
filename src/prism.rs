use libloading::Library;
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::Path;
use thiserror::Error;

const SUPPORTS_SPEAK: u64 = 1 << 2;
const SUPPORTS_BRAILLE: u64 = 1 << 4;
const SUPPORTS_OUTPUT: u64 = 1 << 5;
const PRISM_OK: i32 = 0;

type Context = c_void;
type Backend = c_void;

#[repr(C)]
#[derive(Clone, Copy)]
struct PrismConfig {
    version: u8,
    registry: *mut c_void,
    availability_callback: Option<unsafe extern "C" fn(*mut c_void, u64, *const c_char, bool)>,
    availability_userdata: *mut c_void,
    availability_poll_interval_ms: u32,
    availability_debounce_samples: u32,
    availability_backoff_max_ms: u32,
    availability_auto_power_manage: bool,
}

struct Api {
    _library: Library,
    config_init: unsafe extern "C" fn() -> PrismConfig,
    init: unsafe extern "C" fn(*mut PrismConfig) -> *mut Context,
    shutdown: unsafe extern "C" fn(*mut Context),
    create_best: unsafe extern "C" fn(*mut Context) -> *mut Backend,
    backend_free: unsafe extern "C" fn(*mut Backend),
    backend_name: unsafe extern "C" fn(*mut Backend) -> *const c_char,
    features: unsafe extern "C" fn(*mut Backend) -> u64,
    speak: unsafe extern "C" fn(*mut Backend, *const c_char, bool) -> i32,
    braille: unsafe extern "C" fn(*mut Backend, *const c_char) -> i32,
    output: unsafe extern "C" fn(*mut Backend, *const c_char, bool) -> i32,
}

impl Api {
    unsafe fn load(path: &Path) -> Result<Self, PrismError> {
        let library = unsafe { Library::new(path) }.map_err(|error| PrismError::Load(error.to_string()))?;
        macro_rules! symbol {
            ($name:literal, $ty:ty) => {{
                *unsafe { library.get::<$ty>(concat!($name, "\0").as_bytes()) }
                    .map_err(|error| PrismError::Load(format!("{}: {error}", $name)))?
            }};
        }
        Ok(Self {
            config_init: symbol!("prism_config_init", unsafe extern "C" fn() -> PrismConfig),
            init: symbol!(
                "prism_init",
                unsafe extern "C" fn(*mut PrismConfig) -> *mut Context
            ),
            shutdown: symbol!("prism_shutdown", unsafe extern "C" fn(*mut Context)),
            create_best: symbol!(
                "prism_registry_create_best",
                unsafe extern "C" fn(*mut Context) -> *mut Backend
            ),
            backend_free: symbol!("prism_backend_free", unsafe extern "C" fn(*mut Backend)),
            backend_name: symbol!(
                "prism_backend_name",
                unsafe extern "C" fn(*mut Backend) -> *const c_char
            ),
            features: symbol!(
                "prism_backend_get_features",
                unsafe extern "C" fn(*mut Backend) -> u64
            ),
            speak: symbol!(
                "prism_backend_speak",
                unsafe extern "C" fn(*mut Backend, *const c_char, bool) -> i32
            ),
            braille: symbol!(
                "prism_backend_braille",
                unsafe extern "C" fn(*mut Backend, *const c_char) -> i32
            ),
            output: symbol!(
                "prism_backend_output",
                unsafe extern "C" fn(*mut Backend, *const c_char, bool) -> i32
            ),
            _library: library,
        })
    }
}

#[derive(Debug, Error)]
pub enum PrismError {
    #[error("could not load Prism: {0}")]
    Load(String),
    #[error("Prism initialization failed")]
    Initialize,
    #[error("no Prism backend is available")]
    NoBackend,
    #[error("text contains an embedded null byte")]
    InvalidText,
    #[error("Prism output failed with code {0}")]
    Output(i32),
}

pub struct Prism {
    api: Api,
    context: *mut Context,
    backend: *mut Backend,
}

impl Prism {
    pub fn load(path: &Path) -> Result<Self, PrismError> {
        let api = unsafe { Api::load(path)? };
        let mut config = unsafe { (api.config_init)() };
        let context = unsafe { (api.init)(&mut config) };
        if context.is_null() {
            return Err(PrismError::Initialize);
        }
        let backend = unsafe { (api.create_best)(context) };
        if backend.is_null() {
            unsafe { (api.shutdown)(context) };
            return Err(PrismError::NoBackend);
        }
        Ok(Self {
            api,
            context,
            backend,
        })
    }

    pub fn backend_name(&self) -> String {
        let name = unsafe { (self.api.backend_name)(self.backend) };
        if name.is_null() {
            "unknown".into()
        } else {
            unsafe { CStr::from_ptr(name) }.to_string_lossy().into_owned()
        }
    }

    pub fn send(&mut self, text: &str) -> Result<(), PrismError> {
        let text = CString::new(text).map_err(|_| PrismError::InvalidText)?;
        let first = self.send_once(&text);
        if first.is_ok() {
            return Ok(());
        }
        log::warn!(
            "Prism output failed; reacquiring backend once: {}",
            first.unwrap_err()
        );
        unsafe { (self.api.backend_free)(self.backend) };
        self.backend = unsafe { (self.api.create_best)(self.context) };
        if self.backend.is_null() {
            return Err(PrismError::NoBackend);
        }
        self.send_once(&text)
    }

    fn send_once(&self, text: &CStr) -> Result<(), PrismError> {
        let features = unsafe { (self.api.features)(self.backend) };
        if features & SUPPORTS_OUTPUT != 0 {
            check(unsafe { (self.api.output)(self.backend, text.as_ptr(), true) })
        } else {
            let mut attempted = false;
            if features & SUPPORTS_SPEAK != 0 {
                attempted = true;
                check(unsafe { (self.api.speak)(self.backend, text.as_ptr(), true) })?;
            }
            if features & SUPPORTS_BRAILLE != 0 {
                attempted = true;
                check(unsafe { (self.api.braille)(self.backend, text.as_ptr()) })?;
            }
            if attempted {
                Ok(())
            } else {
                Err(PrismError::NoBackend)
            }
        }
    }
}

fn check(code: i32) -> Result<(), PrismError> {
    if code == PRISM_OK {
        Ok(())
    } else {
        Err(PrismError::Output(code))
    }
}

impl Drop for Prism {
    fn drop(&mut self) {
        if !self.backend.is_null() {
            unsafe { (self.api.backend_free)(self.backend) };
        }
        if !self.context.is_null() {
            unsafe { (self.api.shutdown)(self.context) };
        }
    }
}
