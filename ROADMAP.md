# Orca Mini roadmap

Orca Mini aims to be a fast personal browser for Apple silicon Macs. The roadmap favors page compatibility, predictable resource use, and a small native interface over feature count.

## Available now

- Native WebKit browsing with the system user agent
- One persistent profile with shared cookies and history
- Isolated private windows
- Vertical tabs, pinned tabs, session restore, and inactive-tab suspension
- Split-view browsing
- Downloads, history, import, find in page, and configurable search
- Content blocking, tracker protection, cookie controls, and custom filter lists
- Customizable keyboard shortcuts and Safari Web Inspector access

## Current priorities

- Website compatibility and navigation correctness
- Startup, tab-switching, page-load, CPU, and memory profiling
- Clear site-permission controls
- Download reliability and recovery
- Accessibility and keyboard-navigation polish
- Reproducible, signed, and notarized Apple-silicon releases

## Non-goals

- Shipping a separate rendering engine instead of macOS WebKit
- Multiple profile or space-management interfaces
- A second favorites model alongside pinned tabs
- A built-in password vault
- Global media widgets or automatic picture-in-picture
- Fingerprint or user-agent spoofing
- Matching the feature surface of Chrome or Safari

Ideas that add continuous observers, timers, injected page scripts, background network requests, or large dependencies should include a measured benefit and resource-cost analysis.

_Last updated: August 2026_
