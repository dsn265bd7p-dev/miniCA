# miniCA

A small native macOS app that runs your own private Certificate Authority —
create Root and Intermediate CAs, issue TLS server and client certificates,
and deploy them to Linux servers over SSH.

Built with SwiftUI, SwiftData and Apple's
[swift-certificates](https://github.com/apple/swift-certificates) /
[swift-crypto](https://github.com/apple/swift-crypto). Private keys never
touch disk — they live in the macOS Keychain. Runs on macOS 15 Sequoia or
later; Liquid Glass UI on macOS 26 Tahoe.

## Features

- **Root CAs** — self-signed, with configurable Common Name, Organization,
  Country and validity (1–30 years)
- **Intermediate CAs** — signed by any existing CA, path length constraint 0
- **Key algorithms** — ECDSA P-256, ECDSA P-384, Ed25519, RSA 2048, RSA 4096,
  independently selectable per CA and per certificate
- **Server and client certificates** — EKU `serverAuth` / `clientAuth`, any
  number of DNS and IPv4/IPv6 Subject Alternative Names, validity in days
  (default 397); server certs default to the CN if no SAN is given
- **Proper X.509v3 extensions** — BasicConstraints and KeyUsage (critical),
  Subject/Authority Key Identifiers, per-CA serial counters
- **Export** — certificate, full chain (leaf + intermediates + root,
  nginx/HAProxy-ready) and PKCS#8 private key as PEM; copy to clipboard or
  save to file; SHA-256 fingerprint in every detail view
- **Linux servers** — any number of servers with host, port, user and notes;
  SSH key or password authentication (passwords stored in the Keychain,
  passed to `ssh` via an `SSH_ASKPASS` helper, never on the command line);
  one-click connection test
- **Deployment over SSH** — upload via `scp`, install with
  `sudo mkdir/mv/chmod` (key gets mode 600), optional service reload command
  (e.g. `systemctl reload nginx`), each step with live progress
- **Root CA trust-store install on the server** — Debian/Ubuntu
  (`/usr/local/share/ca-certificates` + `update-ca-certificates`) and
  RHEL/Fedora (`/etc/pki/ca-trust/source/anchors` + `update-ca-trust extract`)
- **Expiry monitoring** — dashboard with an "expiring soon" list and recent
  deployments; remote scan reads the certificates actually installed on each
  server via `openssl x509 -enddate`; configurable warning threshold
- **Settings** — default algorithm, default CA/certificate validity, warning
  threshold

## Download & install (no building needed)

1. Download the `miniCA-….zip` from the
   [latest release](https://github.com/dsn265bd7p-dev/miniCA/releases/latest)
   and unzip it.
2. Drag `miniCA.app` into your **Applications** folder.
3. Open it. macOS will refuse the first launch because the app isn't from the
   App Store — that's expected and only happens once: close the dialog, open
   **System Settings → Privacy & Security**, scroll down and click
   **Open Anyway** next to miniCA, then confirm.

(Terminal alternative for step 3:
`xattr -d com.apple.quarantine /Applications/miniCA.app`)

## Build from source

Requires macOS 15+, Xcode 16+ and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild build -project miniCA.xcodeproj -scheme miniCA \
  -destination 'platform=macOS'
```

A locally built app is signed on your own machine, so Gatekeeper doesn't get
in the way at all.

## Trusting your Root CA on other devices

Export the Root CA certificate from the CA detail view, then:

- **macOS:** double-click the `.crt` and mark it trusted in Keychain Access
- **Linux:** `sudo cp your-ca.crt /usr/local/share/ca-certificates/ &&
  sudo update-ca-certificates`
- **iOS:** AirDrop the `.crt`, install the profile, then enable full trust
  under Settings → General → About → Certificate Trust Settings

## Data & security notes

- Metadata (CAs, certificates, servers, deployments) is stored in SwiftData
  at `~/Library/Application Support/default.store`
- Private keys and SSH passwords are generic Keychain items under the
  service `com.local.miniCA`
- The app is not sandboxed — it needs to launch `/usr/bin/ssh`/`scp` and
  read `~/.ssh`
- SSH host-key checking is disabled for deployments
  (`StrictHostKeyChecking=no`); use on trusted networks
- Deployment assumes the SSH user may run `sudo` without a password prompt
  (or is root)
- A headless self-test of the whole CA pipeline is built in:
  `miniCA.app/Contents/MacOS/miniCA --selftest /tmp/out` writes a root, an
  intermediate and leaf certificates for several algorithms, verifiable with
  `openssl verify`

## Authorship

This app was written by [Claude](https://claude.com/claude-code) (Anthropic's
Claude Fable 5 model, via Claude Code), supervised and tested by a human.

## License

Public domain ([The Unlicense](LICENSE)) — free to use, copy, modify, and
distribute for any purpose, no conditions.
