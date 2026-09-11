# Performance audit — 2026-09-10

The changed paths had three directly observable costs:

- `BiliImage` loaded original `UIImage(data:)` objects for every visible size and retained up to 300 images regardless of decoded byte size. The renderer could trigger deferred full-image decoding. Images now use ImageIO to downsample and eagerly decode on a detached task at the actual view's physical pixel size. A 64 MB decoded bitmap budget and LRU eviction bound the cache. Concurrent URL/size consumers share their decode; different sizes share an in-flight HTTP transfer. Original resolution remains available with a nil pixel size; QuickLook's separate raw-file image viewer path is unchanged.
- `PlaybackProgressStore` encoded its whole dictionary synchronously for every five-second checkpoint and repeated pause/exit callbacks. At its limit this means encoding 2,000 entries for one position change. Version 2 writes only that video's record, changing the membership index only when entries are added/removed. An identical position/duration skips persistence. Version 1 records migrate before committing the new index. Local checkpoints remain synchronous and continue working across relaunch and per cid.
- `VideoPreparationCache` kept cancelled queued cards until an occupied slot finished, and a card cancelled during its detail request still fetched the play URL afterward. Cancellation now removes/resumes the queued waiter and is checked again before the second request. Shared detail work is retained for later foreground consumers.

## Reproduce without Simulator

Run `./offline-harness/performance.sh` on the Mac. It compiles the actual ImageIO helper, progress store, and prefetch actor with Swift 6 `-O`; only the prefetch test's API payload/network boundaries are stubs. Every suite runs without a device or UI. Existing `./offline-harness/run.sh` covers resume semantics, storage bounds, player aspect and collapse logic.

The recorded output is in `host-results.txt`. The image fixture is a generated 4,000 × 3,000 JPEG decoded either at original size or for a 160 × 90 point card at 3×. Each decode timing is the median of nine iterations. Decoded allocation is computed from the actual CGImage `bytesPerRow × height`. The persistence test preloads 2,000 legacy records, verifies migration/reopening, then counts the real UserDefaults data submitted by 12 checkpoints and 6 duplicate saves. The legacy byte comparison uses the encoded legacy dictionary for those same 12 updates; it does not measure physical filesystem bytes written by CFPreferences.

| Measured work | Before | After |
| --- | ---: | ---: |
| Decoded fixture bitmap | 48,000,000 bytes | 786,432 bytes |
| Records encoded per checkpoint at 2,000 saved videos | 2,000 | 1 |
| Extra writes for 6 identical pause/exit saves | 6 | 0 |
| Play URL requests after cancelling one of two held details | 2 | 1 |

`PerformanceRegressionTests` additionally covers downsampling crop resolution, cache byte budget, recency eviction, same-key replacement, oversized-image retention policy, shared image tasks, queued cancellation and reuse of completed shared detail on a real iPhone test run.

The combined iPhone 17 validation passed 87 tests with zero failures, including the five performance cases. See [device-validation.md](device-validation.md) for the tested scope and local result bundle.

The later mini-player/settings/loading refinement passed 110 real-device tests, including actual UIKit drag interruption and renderer ownership checks. See [refinement-validation.md](refinement-validation.md).

These numbers demonstrate the changed work, not an app-wide speedup, launch-time result, or iPhone frame-rate measurement. No claim about dropped frames, thermal behavior, or whole-app memory is made from the host benchmark. The bitmap limit applies to cached images; visible view images and in-flight buffers also consume memory. First migration touches all legacy entries once; future playback checkpoints touch one entry.
