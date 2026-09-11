# Third-party notices

## PiliPlus reference source

The complete upstream source snapshot is retained in `references/PiliPlus` for
implementation reference. It is not compiled into or bundled with the iOS app.

- Project: https://github.com/bggRGjQaUbCoE/PiliPlus
- Commit: `32538c4d705c9f5c74747cd00bacdd061d4aed99`
- License: GPL-3.0; the original license is retained in `references/PiliPlus/LICENSE`.
- Provenance and reference entry points: `references/README.md`.

## MPVKit / libmpv

NeoBili links the `MPVKit` Swift Package product at version `1.0.0`.
The application uses the LGPL build and does not link `MPVKit-GPL`.

- Project: https://github.com/mpvkit/MPVKit
- License: LGPL-3.0
- Package manifest: https://github.com/mpvkit/MPVKit/blob/1.0.0/Package.swift

MPVKit bundles libmpv and FFmpeg-related libraries. Their respective license
and attribution files are retained in the upstream package and must remain
available with any redistributed application build.
