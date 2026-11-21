//! Scheduling for the headless downloader. Kept independent of the desktop UI
//! so the same service loop can later be hosted by Auralis.
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Receiver;
use std::time::Duration;

const MIN_DELAY: Duration = Duration::from_millis(100);
const MAX_DELAY: Duration = Duration::from_secs(1);

/// Run one service tick at a time until the host or the service requests exit.
/// A command wake interrupts the timeout; a full wake channel is harmless.
pub fn run(mut tick: impl FnMut() -> (Duration, bool), stop: &AtomicBool, wakes: &Receiver<()>) {
    loop {
        let (delay, exit) = tick();
        if stop.load(Ordering::SeqCst) || exit {
            break;
        }
        let _ = wakes.recv_timeout(delay.clamp(MIN_DELAY, MAX_DELAY));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[test]
    fn tick_can_request_shutdown() {
        let stop = AtomicBool::new(false);
        let (_tx, rx) = mpsc::channel();
        let mut calls = 0;
        run(
            || {
                calls += 1;
                (Duration::ZERO, true)
            },
            &stop,
            &rx,
        );
        assert_eq!(calls, 1);
    }

    #[test]
    fn command_wake_runs_another_tick_and_host_can_stop() {
        let stop = AtomicBool::new(false);
        let (tx, rx) = mpsc::sync_channel(1);
        tx.send(()).unwrap();
        let mut calls = 0;
        run(
            || {
                calls += 1;
                if calls == 2 {
                    stop.store(true, Ordering::SeqCst);
                }
                (Duration::from_secs(30), false)
            },
            &stop,
            &rx,
        );
        assert_eq!(calls, 2);
    }
}
