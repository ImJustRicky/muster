# Changelog

All notable changes to muster are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.5.51] - 2026-03-04

### Fixed
- Installer now says "Downloading" instead of "Cloning" for fresh installs
- Minor bug fixes

## [0.5.50] - 2026-03-04

### Added
- App file integrity system — SHA256 manifest of all source files, verified on every launch
- `muster verify` command — full file-by-file integrity check (`--quick` for signature only, `--json` for machine output)
- `--no-verify` flag to bypass startup integrity check
- Inline bootstrap trust chain — verifies integrity libs themselves before sourcing (zero-dependency openssl + shasum)
- Tamper detection with interactive repair — shows which files changed, offers `git checkout` + manifest regeneration
- Doctor integration — `muster doctor` now checks app file integrity
- Post-install manifest generation — fresh installs get integrity tracking automatically
- Post-update manifest regeneration — updater regenerates manifest after pulling trusted code
- Makefile targets: `make manifest`, `make manifest-sign`, `make manifest-verify`
- Installer now shows version number during clone/update

## [0.5.47] - 2026-03-04

- Updated updater and minor bug fixes
- Installer now installs from official releases (not source)
- Downgrade protection when switching from source to release channel
- Source mode warnings for non-production use
- Updates panel in settings with changelog viewer
- Fleet Sync (beta)

## [0.5.45] - 2026-03-04

First official release on the Releases channel.

Please report bugs and issues at https://github.com/Muster-dev/muster/issues
