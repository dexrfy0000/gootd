# Gootd

Turn off your Mac's screen and keyboard backlight with one hotkey.
Everything keeps running: downloads finish, builds keep building,
agents keep working. Press it again and everything is back where
you left it.

## Install

```bash
brew install --cask dexrfy0000/gootd/gootd && xattr -cr /Applications/Gootd.app
```

(The `xattr` half clears the quarantine flag on the ad hoc signed build.
A Developer ID signed and notarised build needs no such step.)

Requires Apple silicon, macOS 13+.

## Build from source

Needs Command Line Tools only:

```bash
cd app
./build.sh        # -> build/Gootd.app
./makedmg.sh      # -> build/Gootd.dmg
./release.sh      # signed + notarised image (needs a Developer ID certificate)
```

## Layout

- `app/` — the SwiftPM app (`Sources/Gootd`), build scripts, icon/backdrop tools
- `landing/` — this site ([gootd.vercel.app](https://gootd.vercel.app))

## License

MIT. See [LICENSE](LICENSE).
