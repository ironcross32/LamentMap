use crate::protocol::MAX_INPUT_LINE_BYTES;
use crossbeam_channel::{Receiver, Sender, TryRecvError, TrySendError, bounded};
use serde::Serialize;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::thread::{self, JoinHandle};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportEvent {
    Line(Vec<u8>),
    Error(String),
    Eof,
}

pub struct InputTransport {
    receiver: Receiver<TransportEvent>,
    _thread: JoinHandle<()>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "type")]
pub enum OutboundMessage {
    #[serde(rename = "move")]
    Move {
        protocol_version: u32,
        directions: Vec<String>,
    },
    #[serde(rename = "cancel_move")]
    CancelMove { protocol_version: u32 },
}

impl OutboundMessage {
    pub fn movement(directions: Vec<String>) -> Self {
        Self::Move {
            protocol_version: crate::protocol::PROTOCOL_VERSION,
            directions,
        }
    }

    pub const fn cancellation() -> Self {
        Self::CancelMove {
            protocol_version: crate::protocol::PROTOCOL_VERSION,
        }
    }
}

pub struct OutputTransport<W> {
    writer: W,
}

impl<W: Write> OutputTransport<W> {
    pub const fn new(writer: W) -> Self {
        Self { writer }
    }

    pub fn send(&mut self, message: &OutboundMessage) -> io::Result<()> {
        let encoded = serde_json::to_vec(message).map_err(io::Error::other)?;
        if encoded.len() > MAX_INPUT_LINE_BYTES {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "output line exceeds 1 MiB",
            ));
        }
        self.writer.write_all(&encoded)?;
        self.writer.write_all(b"\n")?;
        self.writer.flush()
    }

    #[cfg(test)]
    fn into_inner(self) -> W {
        self.writer
    }
}

impl InputTransport {
    pub fn spawn<R: Read + Send + 'static>(reader: R, capacity: usize) -> Self {
        assert!(capacity > 0);
        let (sender, receiver) = bounded(capacity);
        let replacement_receiver = receiver.clone();
        let thread = thread::Builder::new()
            .name("lament-mapper-stdin".into())
            .spawn(move || read_stream(reader, &sender, &replacement_receiver))
            .expect("failed to start stdin reader");
        Self {
            receiver,
            _thread: thread,
        }
    }

    pub fn try_recv(&self) -> Result<TransportEvent, TryRecvError> {
        self.receiver.try_recv()
    }
}

fn send_latest(sender: &Sender<TransportEvent>, receiver: &Receiver<TransportEvent>, event: TransportEvent) {
    match sender.try_send(event) {
        Ok(()) | Err(TrySendError::Disconnected(_)) => {}
        Err(TrySendError::Full(event)) => {
            let _ = receiver.try_recv();
            let _ = sender.try_send(event);
        }
    }
}

fn read_stream<R: Read>(reader: R, sender: &Sender<TransportEvent>, receiver: &Receiver<TransportEvent>) {
    let mut reader = BufReader::new(reader);
    let mut line = Vec::new();
    let mut oversized = false;
    loop {
        let available = match reader.fill_buf() {
            Ok(available) => available,
            Err(error) => {
                send_latest(sender, receiver, TransportEvent::Error(error.to_string()));
                let _ = sender.send(TransportEvent::Eof);
                return;
            }
        };
        if available.is_empty() {
            if !line.is_empty() && !oversized {
                finish_line(sender, receiver, &mut line);
            }
            let _ = sender.send(TransportEvent::Eof);
            return;
        }

        let newline = available.iter().position(|byte| *byte == b'\n');
        let consumed = newline.map_or(available.len(), |position| position + 1);
        let content_length = newline.unwrap_or(available.len());
        if !oversized {
            if line.len() + content_length > MAX_INPUT_LINE_BYTES {
                oversized = true;
                line.clear();
                send_latest(
                    sender,
                    receiver,
                    TransportEvent::Error("input line exceeds 1 MiB".into()),
                );
            } else {
                line.extend_from_slice(&available[..content_length]);
            }
        }
        reader.consume(consumed);
        if newline.is_some() {
            if !oversized {
                finish_line(sender, receiver, &mut line);
            }
            line.clear();
            oversized = false;
        }
    }
}

fn finish_line(sender: &Sender<TransportEvent>, receiver: &Receiver<TransportEvent>, line: &mut Vec<u8>) {
    if line.last() == Some(&b'\r') {
        line.pop();
    }
    if line.len() > MAX_INPUT_LINE_BYTES {
        send_latest(
            sender,
            receiver,
            TransportEvent::Error("input line exceeds 1 MiB".into()),
        );
    } else {
        send_latest(sender, receiver, TransportEvent::Line(std::mem::take(line)));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io;
    use std::io::Cursor;
    use std::time::Duration;

    #[derive(Default)]
    struct RecordingWriter {
        bytes: Vec<u8>,
        flushes: usize,
        fail_writes: bool,
    }

    impl Write for RecordingWriter {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            if self.fail_writes {
                return Err(io::Error::new(io::ErrorKind::BrokenPipe, "closed pipe"));
            }
            self.bytes.extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            self.flushes += 1;
            Ok(())
        }
    }

    #[test]
    fn frames_and_flushes_movement_and_cancellation_messages() {
        let mut transport = OutputTransport::new(RecordingWriter::default());
        transport
            .send(&OutboundMessage::movement(vec![
                "northeast".into(),
                "east".into(),
            ]))
            .unwrap();
        transport.send(&OutboundMessage::cancellation()).unwrap();
        let writer = transport.into_inner();
        let lines = String::from_utf8(writer.bytes).unwrap();
        assert_eq!(
            lines,
            "{\"type\":\"move\",\"protocol_version\":1,\"directions\":[\"northeast\",\"east\"]}\n\
             {\"type\":\"cancel_move\",\"protocol_version\":1}\n"
        );
        assert_eq!(writer.flushes, 2);
    }

    #[test]
    fn rejects_oversized_output_and_surfaces_write_failures() {
        let oversized = OutboundMessage::movement(vec!["x".repeat(MAX_INPUT_LINE_BYTES)]);
        let mut transport = OutputTransport::new(RecordingWriter::default());
        let error = transport.send(&oversized).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::InvalidData);
        assert!(transport.into_inner().bytes.is_empty());

        let mut transport = OutputTransport::new(RecordingWriter {
            fail_writes: true,
            ..RecordingWriter::default()
        });
        let error = transport.send(&OutboundMessage::cancellation()).unwrap_err();
        assert_eq!(error.kind(), io::ErrorKind::BrokenPipe);
    }

    #[test]
    fn reads_partial_and_multiple_lines_then_eof() {
        struct Chunks {
            bytes: Cursor<Vec<u8>>,
        }
        impl Read for Chunks {
            fn read(&mut self, output: &mut [u8]) -> io::Result<usize> {
                let mut tiny = [0u8; 2];
                let count = self.bytes.read(&mut tiny)?;
                output[..count].copy_from_slice(&tiny[..count]);
                Ok(count)
            }
        }
        let transport = InputTransport::spawn(
            Chunks {
                bytes: Cursor::new(b"one\ntwo\n".to_vec()),
            },
            8,
        );
        assert_eq!(
            transport.receiver.recv_timeout(Duration::from_secs(1)).unwrap(),
            TransportEvent::Line(b"one".to_vec())
        );
        assert_eq!(
            transport.receiver.recv_timeout(Duration::from_secs(1)).unwrap(),
            TransportEvent::Line(b"two".to_vec())
        );
        assert_eq!(
            transport.receiver.recv_timeout(Duration::from_secs(1)).unwrap(),
            TransportEvent::Eof
        );
    }

    #[test]
    fn full_channel_keeps_latest_event() {
        let transport = InputTransport::spawn(Cursor::new(b"one\ntwo\nthree\n".to_vec()), 1);
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(
            transport.receiver.recv().unwrap(),
            TransportEvent::Line(b"three".to_vec())
        );
        assert_eq!(transport.receiver.recv().unwrap(), TransportEvent::Eof);
    }

    #[test]
    fn rejects_oversized_line_without_allocating_unboundedly_and_recovers() {
        let mut input = vec![b'x'; MAX_INPUT_LINE_BYTES + 2];
        input.extend_from_slice(b"\nok\r\n");
        let transport = InputTransport::spawn(Cursor::new(input), 8);
        assert_eq!(
            transport.receiver.recv_timeout(Duration::from_secs(1)).unwrap(),
            TransportEvent::Error("input line exceeds 1 MiB".into())
        );
        assert_eq!(
            transport.receiver.recv_timeout(Duration::from_secs(1)).unwrap(),
            TransportEvent::Line(b"ok".to_vec())
        );
        assert_eq!(
            transport.receiver.recv_timeout(Duration::from_secs(1)).unwrap(),
            TransportEvent::Eof
        );
    }
}
