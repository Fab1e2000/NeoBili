# PiliPlus source reference

`PiliPlus/` contains a permanent, unmodified source snapshot for researching
PiliPlus behavior while developing NeoBili. It is not included in the NeoBili
application target.

- Upstream: <https://github.com/bggRGjQaUbCoE/PiliPlus>
- Commit: `32538c4d705c9f5c74747cd00bacdd061d4aed99`
- Commit date: 2026-09-09 18:05:37 +08:00
- Retrieved: 2026-09-10
- License: GNU GPL version 3; see the unchanged [LICENSE](PiliPlus/LICENSE).
- Upstream README and all other source notices remain in the snapshot.
- Git history and the nested `.git` directory are intentionally omitted.

## Playback behavior references

- `lib/pages/video/controller.dart`, `_setVideoHeight`: takes dimensions from
  the selected video stream, falling back to the current part's dimensions.
  Portrait and landscape video use different inline player heights.
- `lib/pages/video/view.dart`, `didChangeDependencies`: uses a 16:9 minimum
  height and a portrait maximum of the larger of 65% of the screen's long edge
  or its short edge, preserving space for page content.
- `lib/pages/video/controller.dart`, `_queryVideoUrl` and `playerInit`: takes an
  explicit progress argument or the server's last playback time and passes it
  to the player as the initial seek position.
- `lib/models/video/play/url.dart`, `lastPlayTime`: treats nonpositive saved
  positions as zero.
- `lib/plugin/pl_player/controller.dart`, `makeHeartBeat`: reports progress
  while playing and on status changes; finished playback uses progress `-1`.

This snapshot is reference material. NeoBili's native Swift implementation is
maintained in `NeoBili/`; upstream Flutter source is retained here for inspection.
