use crate::config::FeedbackMode;
use crate::model::CellKind;
use crate::navigation::MoveResult;

pub trait SpeechOutput {
    fn output(&mut self, phrase: &str) -> Result<(), String>;
}

pub trait SoundOutput {
    fn navigation(&mut self, cue_id: &str);
    fn notification(&mut self, cue_id: &str);
    fn is_complete(&self) -> bool;
}

pub struct Feedback<S, A> {
    pub mode: FeedbackMode,
    pub speech: S,
    pub audio: A,
}

impl<S: SpeechOutput, A: SoundOutput> Feedback<S, A> {
    pub fn navigation(&mut self, result: MoveResult, kind: CellKind, phrase: &str) {
        if self.mode.uses_speech()
            && let Err(error) = self.speech.output(phrase)
        {
            log::warn!("Prism navigation output failed: {error}");
        }
        if self.mode.uses_sounds() {
            let cue = if result == MoveResult::Boundary {
                "boundary"
            } else {
                kind.cue_id()
            };
            self.audio.navigation(cue);
        }
    }

    pub fn focus(&mut self, phrase: &str) {
        if self.mode.uses_speech()
            && let Err(error) = self.speech.output(phrase)
        {
            log::warn!("Prism focus output failed: {error}");
        }
    }

    pub fn new_map(&mut self, enabled: bool) {
        if enabled && self.mode.uses_sounds() {
            self.audio.notification("new_map");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::rc::Rc;

    #[derive(Default)]
    struct FakeSpeech(Rc<RefCell<Vec<String>>>);
    impl SpeechOutput for FakeSpeech {
        fn output(&mut self, phrase: &str) -> Result<(), String> {
            self.0.borrow_mut().push(phrase.into());
            Ok(())
        }
    }
    #[derive(Default)]
    struct FakeAudio(Rc<RefCell<Vec<String>>>);
    impl SoundOutput for FakeAudio {
        fn navigation(&mut self, cue_id: &str) {
            self.0.borrow_mut().push(cue_id.into());
        }
        fn notification(&mut self, cue_id: &str) {
            self.0.borrow_mut().push(cue_id.into());
        }
        fn is_complete(&self) -> bool {
            true
        }
    }

    #[test]
    fn honors_all_modes_and_boundary_cue() {
        for (mode, speech_count, audio_count) in [
            (FeedbackMode::Speech, 1, 0),
            (FeedbackMode::SpeechAndSounds, 1, 1),
            (FeedbackMode::Sounds, 0, 1),
        ] {
            let spoken = Rc::new(RefCell::new(vec![]));
            let played = Rc::new(RefCell::new(vec![]));
            let mut feedback = Feedback {
                mode,
                speech: FakeSpeech(spoken.clone()),
                audio: FakeAudio(played.clone()),
            };
            feedback.navigation(MoveResult::Boundary, CellKind::Unseen, "Map boundary.");
            feedback.focus("Player position, center.");
            assert_eq!(spoken.borrow().len(), speech_count * 2);
            assert_eq!(played.borrow().len(), audio_count);
            if audio_count > 0 {
                assert_eq!(played.borrow()[0], "boundary");
            }
        }
    }
}
