use crate::config::FeedbackMode;
use crate::model::CellKind;
use crate::navigation::MoveResult;

pub trait SpeechOutput {
    fn output(&mut self, phrase: &str) -> Result<(), String>;
}

pub trait SoundOutput {
    fn navigation(&mut self, cue_ids: &[&str]);
    fn notification(&mut self, cue_id: &str);
    fn is_complete(&self) -> bool;
}

pub struct Feedback<S, A> {
    pub mode: FeedbackMode,
    pub speech: S,
    pub audio: A,
}

impl<S: SpeechOutput, A: SoundOutput> Feedback<S, A> {
    pub fn explicit(&mut self, phrase: &str) {
        if let Err(error) = self.speech.output(phrase) {
            log::warn!("Prism explicit output failed: {error}");
        }
    }

    pub fn navigation(&mut self, result: MoveResult, kind: CellKind, phrase: &str) {
        if self.mode.uses_speech()
            && let Err(error) = self.speech.output(phrase)
        {
            log::warn!("Prism navigation output failed: {error}");
        }
        if self.mode.uses_sounds() {
            if result == MoveResult::Boundary {
                self.audio.navigation(&["boundary"]);
            } else if let CellKind::Player(Some(terrain)) = kind {
                self.audio.navigation(&[terrain.cue_id(), "player"]);
            } else {
                self.audio.navigation(&[kind.cue_id()]);
            }
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
        fn navigation(&mut self, cue_ids: &[&str]) {
            self.0
                .borrow_mut()
                .extend(cue_ids.iter().map(|cue| (*cue).into()));
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

    #[test]
    fn layers_inferred_terrain_and_player_cues() {
        let played = Rc::new(RefCell::new(vec![]));
        let mut feedback = Feedback {
            mode: FeedbackMode::Sounds,
            speech: FakeSpeech::default(),
            audio: FakeAudio(played.clone()),
        };

        feedback.navigation(
            MoveResult::Centered,
            CellKind::Player(Some(crate::model::Terrain::DenseForests)),
            "Dense forest (player's position).",
        );

        assert_eq!(&*played.borrow(), &["dense_forests", "player"]);
    }

    #[test]
    fn crossroads_phrase_preserves_underlying_cell_cues() {
        for (kind, expected) in [
            (CellKind::Terrain(crate::model::Terrain::Road), "road"),
            (CellKind::Player(None), "player"),
            (CellKind::Landmark, "landmark"),
        ] {
            let played = Rc::new(RefCell::new(vec![]));
            let mut feedback = Feedback {
                mode: FeedbackMode::Sounds,
                speech: FakeSpeech::default(),
                audio: FakeAudio(played.clone()),
            };

            feedback.navigation(MoveResult::Moved, kind, "Crossroads, east, south, west.");

            assert_eq!(&*played.borrow(), &[expected]);
        }
    }

    #[test]
    fn explicit_speech_bypasses_mode_and_never_plays_audio() {
        for mode in [
            FeedbackMode::Speech,
            FeedbackMode::SpeechAndSounds,
            FeedbackMode::Sounds,
        ] {
            let spoken = Rc::new(RefCell::new(vec![]));
            let played = Rc::new(RefCell::new(vec![]));
            let mut feedback = Feedback {
                mode,
                speech: FakeSpeech(spoken.clone()),
                audio: FakeAudio(played.clone()),
            };

            feedback.explicit("Crossroads, east, south, west.");

            assert_eq!(&*spoken.borrow(), &["Crossroads, east, south, west."]);
            assert!(played.borrow().is_empty());
        }
    }
}
