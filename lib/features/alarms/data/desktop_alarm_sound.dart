import 'dart:io';
import 'dart:async';

class DesktopAlarmSound {
  Process? _activeSoundProcess;

  void play(String soundPath, bool loop, void Function() onComplete) async {
    _activeSoundProcess?.kill();
    _activeSoundProcess = null;

    Future<void> runPlay() async {
      try {
        _activeSoundProcess = await Process.start('paplay', [soundPath]);
        if (loop) {
          unawaited(_activeSoundProcess?.exitCode.then((code) {
            if (_activeSoundProcess != null) {
              unawaited(runPlay());
            }
          }));
        } else {
          unawaited(_activeSoundProcess?.exitCode.then((_) {
            onComplete();
          }));
        }
      } catch (_) {
        try {
          _activeSoundProcess = await Process.start('pw-play', [soundPath]);
          if (loop) {
            unawaited(_activeSoundProcess?.exitCode.then((code) {
              if (_activeSoundProcess != null) {
                unawaited(runPlay());
              }
            }));
          } else {
            unawaited(_activeSoundProcess?.exitCode.then((_) {
              onComplete();
            }));
          }
        } catch (_) {
          try {
            _activeSoundProcess = await Process.start('aplay', ['/usr/share/sounds/alsa/Front_Center.wav']);
            if (!loop) {
              unawaited(_activeSoundProcess?.exitCode.then((_) {
                onComplete();
              }));
            }
          } catch (_) {
            if (!loop) onComplete();
          }
        }
      }
    }

    unawaited(runPlay());
  }

  void stop() {
    _activeSoundProcess?.kill();
    _activeSoundProcess = null;
  }
}
