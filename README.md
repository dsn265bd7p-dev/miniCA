# miniCA

A small native macOS app for running your own private Certificate Authority — create Root and Intermediate CAs, issue TLS server and client certificates, and deploy them to Linux servers over SSH.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple) ![License: MIT](https://img.shields.io/badge/License-MIT-green)

Built with SwiftUI, SwiftData, [swift-certificates](https://github.com/apple/swift-certificates) and [swift-crypto](https://github.com/apple/swift-crypto). Private keys never touch disk — they live in the macOS Keychain. On macOS 26 Tahoe the UI picks up Liquid Glass styling; on macOS 15 Sequoia it falls back to standard materials.

## Features

### 🏛 Certificate Authorities
- **Root CAs** — self-signed, with configurable Common Name, Organization, Country, and validity (1–30 years)
- **Intermediate CAs** — signed by any existing CA, with path-length constraint 0
- **Algorithms**: ECDSA P-256, ECDSA P-384, Ed25519, RSA 2048, RSA 4096
- Proper X.509v3 extensions: `BasicConstraints` (critical), `KeyUsage keyCertSign+cRLSign` (critical), Subject/Authority Key Identifiers
- Per-CA serial counter for issued certificates
- Detail view with SHA-256 fingerprint, PEM display, copy & save, and private-key export
- Export the Root CA certificate for import on other devices (macOS, Linux, iOS)

### 📜 Certificate Issuance
- **Server certificates** (EKU `serverAuth`) and **client certificates** (EKU `clientAuth`)
- **Subject Alternative Names**: any number of DNS names and IPv4/IPv6 addresses; server certs default to the CN if no SAN is given
- Configurable validity in days (default 397, the public-TLS maximum)
- Any supported algorithm per certificate, independent of the CA's algorithm
- Detail view with fingerprint, PEM display, and one-click export of:
  - certificate (`.crt`)
  - **full chain** (leaf + intermediates + root, nginx/HAProxy-ready)
  - private key (`.key`, PKCS#8 PEM)

### 🖥 Server Management (Linux)
- Register any number of Linux servers (host, port, user, notes)
- **Authentication**: SSH key (with key file path) or password (stored in the macOS Keychain, passed to `ssh` via an `SSH_ASKPASS` helper — never on the command line)
- **Test Connection** button with live output
- Per-server certificate directory (default `/etc/ssl/minica`) and reload command (e.g. `systemctl reload nginx`)

### 🚀 Deployment over SSH
- Pick certificate + target server, adjust remote paths, deploy with one click
- Steps, each with live progress: upload via `scp` → `sudo mkdir/mv/chmod` (key gets `0600`) → optional trust-store install → optional service reload
- **Root CA trust-store installation** on the server:
  - Debian/Ubuntu: `/usr/local/share/ca-certificates` + `update-ca-certificates`
  - RHEL/Fedora: `/etc/pki/ca-trust/source/anchors` + `update-ca-trust extract`
- Every deployment is recorded (what, where, when)

### 🔍 Expiry Monitoring
- **Dashboard** with counts, an "expiring soon" list (CAs and certificates), and recent deployments
- Configurable warning threshold (7–180 days before expiry)
- **Remote scan**: reads the actual certificates on each server via `openssl x509 -enddate` and compares expiry dates against your deployments

### ⚙️ Settings
- Default key algorithm for new CAs and certificates
- Default CA validity (years) and certificate validity (days)
- Expiry warning threshold

## Requirements

- macOS 15 Sequoia or later (Apple Silicon or Intel)
- For building: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

```bash
xcodegen generate
xcodebuild build -project miniCA.xcodeproj -scheme miniCA -destination 'platform=macOS'
```

## Installing a release build

Release binaries are ad-hoc signed (no Apple Developer ID). After downloading, clear the quarantine flag once:

```bash
xattr -d com.apple.quarantine ./miniCA.app
```

or right-click → Open the first time.

## Trusting your Root CA on other devices

Export the Root CA certificate from the CA detail view, then:

- **macOS:** double-click the `.crt` and mark it trusted in Keychain Access
- **Linux:** `sudo cp your-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates`
- **iOS:** AirDrop the `.crt`, install the profile, then enable full trust under Settings → General → About → Certificate Trust Settings

## Data & security notes

- Metadata (CAs, certificates, servers, deployments) is stored in SwiftData at `~/Library/Application Support/default.store`
- Private keys and SSH passwords are generic Keychain items under the service `com.local.miniCA`
- The app is **not sandboxed** — it needs to launch `/usr/bin/ssh`/`scp` and read `~/.ssh`
- SSH host-key checking is disabled for deployments (`StrictHostKeyChecking=no`); use on trusted networks
- Deployment assumes the SSH user may run `sudo` without a password prompt (or is root)
- A headless self-test of the whole CA pipeline is built in: `miniCA.app/Contents/MacOS/miniCA --selftest /tmp/out` writes a root, intermediate, and leaf certs for several algorithms, verifiable with `openssl verify`

## License

MIT
