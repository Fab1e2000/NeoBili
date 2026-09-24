# PiliPlus source reference

NeoBili's PiliPlus research is pinned to one upstream commit. The source itself
is not kept in this repository; browse it upstream, or check it out locally into
the git-ignored `references/PiliPlus/`:

```bash
git clone https://github.com/bggRGjQaUbCoE/PiliPlus references/PiliPlus && git -C references/PiliPlus checkout 32538c4d705c9f5c74747cd00bacdd061d4aed99
```

- Upstream: <https://github.com/bggRGjQaUbCoE/PiliPlus>
- Commit: [`32538c4d705c9f5c74747cd00bacdd061d4aed99`](https://github.com/bggRGjQaUbCoE/PiliPlus/tree/32538c4d705c9f5c74747cd00bacdd061d4aed99)
- Commit date: 2026-09-09 18:05:37 +08:00
- License: GNU GPL version 3 ([LICENSE](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/32538c4d705c9f5c74747cd00bacdd061d4aed99/LICENSE)).

File paths below are relative to the upstream repository root.

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
