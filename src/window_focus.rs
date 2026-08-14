use std::mem::size_of;
use windows_sys::Win32::Foundation::{CloseHandle, HWND, INVALID_HANDLE_VALUE, LPARAM};
use windows_sys::Win32::Storage::FileSystem::WriteFile;
use windows_sys::Win32::System::Console::{GetStdHandle, STD_OUTPUT_HANDLE};
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible, SW_RESTORE,
    SetForegroundWindow, ShowWindow,
};

const MAPPER_WINDOW_TITLE: &str = "LamentMapper";

#[derive(Debug, PartialEq, Eq)]
struct WindowCandidate {
    process_id: u32,
    title: String,
    visible: bool,
}

struct NativeWindow {
    handle: HWND,
    candidate: WindowCandidate,
}

pub fn write_helper_output(message: &str) {
    let handle = unsafe { GetStdHandle(STD_OUTPUT_HANDLE) };
    let Ok(length) = u32::try_from(message.len()) else {
        return;
    };
    if handle.is_null() || handle == INVALID_HANDLE_VALUE {
        return;
    }
    let mut written = 0;
    unsafe {
        WriteFile(
            handle,
            message.as_ptr().cast(),
            length,
            &raw mut written,
            std::ptr::null_mut(),
        );
    }
}

pub fn parent_process_id() -> Option<u32> {
    let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if snapshot == INVALID_HANDLE_VALUE {
        return None;
    }
    let current_process_id = std::process::id();
    let mut entry = PROCESSENTRY32W {
        dwSize: size_of::<PROCESSENTRY32W>() as u32,
        ..PROCESSENTRY32W::default()
    };
    let mut parent = None;
    if unsafe { Process32FirstW(snapshot, &raw mut entry) } != 0 {
        loop {
            if entry.th32ProcessID == current_process_id {
                parent = Some(entry.th32ParentProcessID);
                break;
            }
            if unsafe { Process32NextW(snapshot, &raw mut entry) } == 0 {
                break;
            }
        }
    }
    unsafe { CloseHandle(snapshot) };
    parent.filter(|process_id| *process_id != 0)
}

pub fn focus_existing_mapper() -> bool {
    let windows = enumerate_windows();
    select_mapper_window(&windows, MAPPER_WINDOW_TITLE)
        .is_some_and(|index| activate_window(windows[index].handle))
}

pub fn focus_parent_window(parent_process_id: u32) -> bool {
    let windows = enumerate_windows();
    select_parent_window(&windows, parent_process_id)
        .is_some_and(|index| activate_window(windows[index].handle))
}

fn select_mapper_window(windows: &[NativeWindow], expected_title: &str) -> Option<usize> {
    select_candidate(windows.iter().map(|window| &window.candidate), |candidate| {
        candidate.visible && candidate.title == expected_title
    })
}

fn select_parent_window(windows: &[NativeWindow], parent_process_id: u32) -> Option<usize> {
    select_candidate(windows.iter().map(|window| &window.candidate), |candidate| {
        candidate.visible && candidate.process_id == parent_process_id
    })
}

fn select_candidate<'a>(
    candidates: impl Iterator<Item = &'a WindowCandidate>,
    predicate: impl Fn(&WindowCandidate) -> bool,
) -> Option<usize> {
    candidates
        .enumerate()
        .find_map(|(index, candidate)| predicate(candidate).then_some(index))
}

fn enumerate_windows() -> Vec<NativeWindow> {
    let mut windows = Vec::new();
    unsafe {
        EnumWindows(
            Some(collect_window),
            (&raw mut windows).cast::<core::ffi::c_void>() as LPARAM,
        );
    }
    windows
}

unsafe extern "system" fn collect_window(handle: HWND, data: LPARAM) -> i32 {
    let visible = unsafe { IsWindowVisible(handle) } != 0;
    let length = unsafe { GetWindowTextLengthW(handle) };
    let mut buffer = vec![0u16; usize::try_from(length).unwrap_or(0) + 1];
    let copied = unsafe { GetWindowTextW(handle, buffer.as_mut_ptr(), buffer.len() as i32) };
    let title = String::from_utf16_lossy(&buffer[..usize::try_from(copied).unwrap_or(0)]);
    let mut process_id = 0;
    unsafe { GetWindowThreadProcessId(handle, &raw mut process_id) };
    let windows = unsafe { &mut *(data as *mut Vec<NativeWindow>) };
    windows.push(NativeWindow {
        handle,
        candidate: WindowCandidate {
            process_id,
            title,
            visible,
        },
    });
    1
}

fn activate_window(handle: HWND) -> bool {
    unsafe {
        ShowWindow(handle, SW_RESTORE);
        SetForegroundWindow(handle) != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn native(process_id: u32, title: &str, visible: bool) -> NativeWindow {
        NativeWindow {
            handle: std::ptr::null_mut(),
            candidate: WindowCandidate {
                process_id,
                title: title.into(),
                visible,
            },
        }
    }

    #[test]
    fn mapper_selection_requires_an_exact_visible_title() {
        let windows = vec![
            native(10, "LamentMapper - other", true),
            native(11, "LamentMapper", false),
            native(12, "LamentMapper", true),
        ];
        assert_eq!(select_mapper_window(&windows, MAPPER_WINDOW_TITLE), Some(2));
        assert_eq!(select_mapper_window(&windows, "lamentmapper"), None);
    }

    #[test]
    fn parent_selection_requires_the_exact_pid_and_visibility() {
        let windows = vec![
            native(40, "Mudlet", false),
            native(41, "Mudlet", true),
            native(40, "Active profile - Mudlet", true),
        ];
        assert_eq!(select_parent_window(&windows, 40), Some(2));
        assert_eq!(select_parent_window(&windows, 42), None);
    }
}
