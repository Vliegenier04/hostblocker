# macOS Hostname / Domain Blocker
# HostBlocker

An interactive script that blocks hostnames on macOS by writing a managed
section into the system `hosts` file. Works from a running macOS session **and**
from the macOS Recovery Terminal, so you can pre-block domains on a disk that
hasn't been booted yet (e.g. during a fresh setup, before MDM enrollment
domains are ever contacted).

---

## ✨ Features

- **📂 Automatic Target Detection** - Finds every candidate `hosts` file under
  `/Volumes/*` (Recovery) and the running system's Data volume
- **🧠 Smart Input Normalisation** - Paste URLs, `0.0.0.0 host` lines, or bare
  hostnames — everything is reduced to a valid hostname
- **🛡️ Non-destructive Edits** - All entries live inside a marked block, so
  existing `hosts` content is preserved
- **💾 Timestamped Backups** - Every apply/remove/restore takes a fresh backup
  next to the target file
- **↩️ One-Click Restore** - Roll back to any previous backup from the menu
- **🌐 IPv4 + IPv6 Coverage** - Writes both `0.0.0.0` and `::1` entries (IPv6
  toggleable)
- **🍎 Apple MDM Preset** - One-shot option to load Apple's DEP / MDM enrollment
  hostnames into the blocklist
- **🎨 Color-coded Output** - Clear `[ok]` / `[warn]` / `[error]` status
  messages

---

## ⚠️ Prerequisites

- **Must be run as root** — `sudo ./block-v1.sh` on normal macOS; Recovery
  Terminal is already root
- **macOS** with `bash` (ships by default; the script is bash 3.2 compatible)
- For Recovery use: unlock/mount the target disk in **Disk Utility** first
  (FileVault volumes must be unlocked)

---

## 📋 Installation & Usage

### Quick Start

Copy and paste this command into Terminal:

```bash
curl -L https://raw.githubusercontent.com/vliegenier04/hostblocker/main/block-v1.sh -o block-v1.sh && chmod +x ./block-v1.sh && sudo ./block-v1.sh
```

> 💡 **Tip:** In macOS Recovery Terminal, drop the `sudo` — you're already
> root.

### Step-by-Step (Running macOS)

**1.** **Download the script** using the command above

**2.** **Choose target** - Select option `1` in the main menu. On a running
system you'll usually pick the entry that ends in
`/private/etc/hosts` or `/System/Volumes/Data/private/etc/hosts` (they resolve
to the same file)

**3.** **Edit the blocklist** - Select option `2`:

- `1` — Add a single hostname or URL
- `2` — Paste multiple entries, finish with a single `.` on its own line
- `4` — Load defaults compiled into the script
- `7` — Preload Apple MDM / DEP hostnames

**4.** **Apply** - Select option `3` from the main menu. The script writes a
managed block like:

```text
# >>> RECOVERY_DOMAIN_BLOCKER BEGIN
0.0.0.0	test.example.com
::1		test.example.com
# <<< RECOVERY_DOMAIN_BLOCKER END
```

**5.** **Flush DNS** - The script will remind you, but for reference:

```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

**6.** 🎉 **Done!** New connections resolve blocked hostnames to `0.0.0.0` and
fail immediately.

### Step-by-Step (macOS Recovery)

> **Starting Point:** You've booted into Recovery (⌘R on Intel, hold Power on
> Apple Silicon) and opened Terminal from the **Utilities** menu.

**1.** **Unlock the target disk** in Disk Utility if FileVault is enabled

**2.** **Connect to Wi-Fi** so `curl` works

**3.** **Run the download command** (without `sudo` — Recovery is already root):

```bash
curl -L https://raw.githubusercontent.com/myscript/block-v1.sh -o block-v1.sh && chmod +x ./block-v1.sh && ./block-v1.sh
```

**4.** **Select target** - Option `1` will list all mounted volumes. Pick the
`hosts` file on the **Data volume** of the disk you're preparing (usually
`/Volumes/Macintosh HD - Data/private/etc/hosts`)

**5.** **Edit the blocklist and apply** - Options `2` then `3`, same as above

**6.** **Reboot into macOS** - The script prints a reboot reminder when the
target lives under `/Volumes/*`

---

## 🔧 Troubleshooting

### No Target Found

**Problem:** "No candidate hosts file locations found"

**Solutions:**

- Unlock the FileVault volume in Disk Utility, then re-run
- Use option `c` to enter a custom mounted path such as
  `/Volumes/Macintosh HD - Data`

### Hosts File Not Writable

**Problem:** `Hosts file is not writable`

**Solutions:**

- Confirm you're running as root (`sudo` on normal macOS)
- In Recovery, verify the disk is fully mounted and unlocked (not just
  visible)

### Blocks Don't Take Effect

**Problem:** A blocked hostname still resolves in the browser

**Solutions:**

- Flush the DNS cache:
  ```bash
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder
  ```
- **Disable Secure DNS (DoH/DoT)** in your browser — Chrome, Firefox and
  Safari can resolve names over HTTPS, bypassing `/etc/hosts` entirely
- Restart long-lived apps that cached the old resolution
- If the Mac is MDM-managed, a configuration profile may reinstall an
  overriding `hosts` payload or content filter — check
  `profiles list`

### Wildcards Don't Work

**Problem:** `*.example.com` was rejected

**Explanation:** The `hosts` file has no wildcard support. The script strips
the wildcard and adds only the apex domain (`example.com`). Add each
subdomain you need explicitly.

### Restore From Backup

Every apply/remove takes a `*.recovery-blocker-backup.YYYYMMDD-HHMMSS` file
next to the target `hosts` file. Use main menu option `6` to pick one and
roll back.

---

## 📦 What Gets Written

| Section              | Behaviour                                                     |
| -------------------- | ------------------------------------------------------------- |
| Existing `hosts`     | Preserved verbatim                                            |
| Managed block        | Delimited by `# >>> RECOVERY_DOMAIN_BLOCKER BEGIN` / `END`    |
| IPv4 line            | `0.0.0.0\t<hostname>` for every entry                         |
| IPv6 line (optional) | `::1\t\t<hostname>` when IPv6 is enabled (default: on)        |
| Permissions          | Reset to `0644` root:wheel after every write                  |

Re-running the script updates the managed block in place — existing entries
outside the markers are never touched.

---

## ⚖️ Legal Disclaimer

> **Important:** This script edits your own machine's local `hosts` file. It
> does not tamper with any remote system. Blocking hostnames is a standard
> and supported use of `/etc/hosts`.
>
> **Use responsibly and at your own risk.** This tool is intended for
> personal devices and lawful use cases (development, testing, ad/tracker
> blocking, pre-provisioning).
---

## 📄 License

This project is provided as-is for educational purposes. Use at your own
discretion.

---

## 🙏 Credits

<3 from Vliegenier04 and a little bit from Claude Opus 4.7 for ReadMe.md generation. 

Interactive-script pattern inspired by
[`assafdori/bypass-mdm`](https://github.com/assafdori/bypass-mdm) — a great
reference for Recovery-Terminal scripting on macOS. Go star their repo.
