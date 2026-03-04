# Changelog

All notable changes to muster are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- GitHub Releases update channel (default) — checks API for new releases, shows changelog before updating
- Source update channel (opt-in) — tracks HEAD of main, labeled as risky
- `update_mode` global setting (`release` | `source`)
- Deploy password setting — require a password before deploying
- Hook security system — integrity manifest, dangerous command scanner, permission lockdown
- `CHANGELOG.md` and GitHub Actions release workflow

### Changed
- `muster update` now shows release notes and prompts for confirmation before applying
- Dashboard update banner shows version number when available
