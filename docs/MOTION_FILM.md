# Freki Hub motion film

**A day, in rhythm.** A 48-second editorial product film, designed for a portfolio or project presentation. The master is 1920 × 1080, 30 fps, H.264 MP4 with a stereo AAC soundtrack. It is a motion graphics reconstruction of the product, not an Android screen recording or a device verification result.

## Creative direction

Bundled Geist / Geist Mono typography, charcoal and ivory canvases, sage accents and the app's muted finance palette connect the film to the existing design system. Large masked headlines, spring entrances, layered phone compositions, graphic shutters, expanding traces and close-up feature cuts supply the motion. An original, deterministic 120 BPM electronic score accompanies the sequence, with transition swells and percussion.

| Time | Sequence |
| --- | --- |
| 00–04 | Orbital identity and kinetic opening: “A day, in rhythm.” |
| 04–10 | Today, analog clock, session controls and split-flap timer close-up |
| 10–16 | Sessions and Calendar, followed by a moving strip of saved days |
| 16–22 | Finance, animated totals, safe-to-spend and savings goal |
| 22–28 | Map, category colors and abstract chronological sample traces |
| 28–34 | Valid scheduled-reminder syntax and a local reminder reveal |
| 34–40 | Settings, opt-in defaults, JSON backup and local record ownership |
| 40–48 | Five-phone fan, Freki Hub lock-up and musical resolution |

## Product accuracy

Read the [app documentation](APP_DOCUMENTATION.md), [data reference](DATA_REFERENCE.md), [Android runtime](ANDROID_RUNTIME.md), [current audit](APPLICATION_AUDIT.md), [rule syntax](../RULE_SYNTAX.md), [development guide](DEVELOPMENT.md), root README and historical references when planning the film. Current documentation takes precedence over historical page names or older claims.

All displayed records, values and map samples are fictional production data. The phones are simplified editorial mockups with four bottom tabs and fixed Calendar/Settings shortcuts. They use the app's fonts and documented feature hierarchy; they do not establish pixel fidelity to a real phone. The Map is a schematic of discrete recorded samples, without invented GPS coordinates, geographical tiles or road routes. Settings shows location collection and activity logs off. The film makes no purchase-import, server-sync, bank-integration or uninterrupted background-delivery claim.

The Finance example uses PHP only: income 24,000 minus expenses 6,550 minus savings 3,000 yields net 14,450. Remaining planned commitments of 2,000 produce safe-to-spend of 12,450. The 60% savings example is 3,000 against a fictional goal of 5,000. Reminder syntax is copied in structure from the supported `notifications` schedule grammar. Reminder delivery still depends on Android permissions and system scheduling, as documented in the runtime reference.

## Reproduce and edit

The self-contained source is [tools/motion/freki_showreel.py](../tools/motion/freki_showreel.py). It requires Python 3, Pillow, NumPy and `ffmpeg` on PATH. It does not add dependencies to Flutter or modify app behavior.

```powershell
python tools/motion/freki_showreel.py --output 'C:\path\outside\repository\freki-hub-film'
```

Use `--preview` to render the eight-scene contact sheet and poster without audio/video encoding. `frame(seconds)` exposes a deterministic frame for individual inspection. The font assets resolve relative to the repository; run from any working directory. Output includes the MP4, original stereo WAV, poster and chapter thumbnails. Keep renders outside the repository: exported media are delivery artifacts, not app source or checked-in build outputs.

The score is synthesized specifically for this film. Geist fonts retain their bundled [OFL license](../assets/fonts/OFL.txt). No third-party music, stock footage, personal records or private attachments are incorporated.

## Verification

Production verification covers contact sheets for all eight chapters and six macro shots, sampled encoded video frames, FFmpeg decoding, stream dimensions/frame rate/duration and audio levels. This does not replace Android device testing. App source and runtime behavior are unchanged, so Flutter tests and APK builds are outside this media-only task.

The 2026-10-02 export passed a complete FFmpeg decode with no reported errors. FFprobe confirmed 1920 × 1080 H.264 at 30 fps, exactly 48.000 seconds, and 48 kHz stereo AAC of the same duration. The MP4 is 5,696,601 bytes. The original PCM score measured −17.6 dB mean and −3.0 dB peak using `volumedetect`. Generated chapter/macro contact sheets and eight sampled encoded frames were visually reviewed. Python syntax parsing, local links in this document and the documentation index, and `git diff --check` passed.
