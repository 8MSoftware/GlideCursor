# GlideCursor

A macOS utility that adds inertia-based cursor movement.

---

## What GlideCursor Does

GlideCursor gives your cursor trackball-like inertia on macOS.

Flick the trackpad and lift your finger — the cursor keeps gliding and slows down on its own.
Touch the trackpad again and it **stops instantly**, just like scrolling on an iPhone.

If you stop your finger before lifting it, the cursor stays put.

---

## Devices

GlideCursor tells your devices apart and lets you turn gliding on or off for each one.

- **Trackpads** (built-in and Magic Trackpad) — on by default
- **Magic Mouse** — off by default
- Mice without a touch surface are not supported, because GlideCursor can't tell when your finger leaves them.

Touching any trackpad or Magic Mouse stops a glide. So does moving another device, clicking, or scrolling.

If you use tap to click, the tap you use to stop a glide is not turned into a click (this can be turned off).

---

## Precision Mode

Slow the cursor down for fine positioning (×0.1–×0.9, default ×0.3), for example in a drawing app. No glide while it is on.
Precision mode is off by default. Turn it on in the **Precision mode** tab, then choose one or more ways to start it:

- **Keyboard shortcut** — press once to start, again to leave (default ⌃⌥G)
- **Hold a modifier key** — slow only while you hold fn, ⌃, ⌥, ⇧ or ⌘ (default fn)
- **Double-tap and hold** — double-tap, keep your finger down, and it starts; lift to leave. Clashes with double-tap dragging.

A ring around the cursor shows when precision mode starts and ends.

---

## Installation

Download the `.pkg` installer from the **Releases** page and run it.

When launching GlideCursor for the first time:

1. A welcome window will appear.
2. Click **Open System Settings**.
3. Enable **Accessibility** permission for GlideCursor.
4. Return to the app and click **Get Started**.
5. GlideCursor is on from the first launch. You can turn it off from the menu bar.

Requires macOS 14 Sonoma or later.

---

## Settings

Click the GlideCursor icon in the menu bar. The settings have two tabs.

**Glide**
- **Glide on these devices** — turn gliding on or off per device
- **Glide length**, **Speed**, **Flick threshold**, **Max speed**
- **Ignore the tap that stops a glide**
- **On/off shortcut** — toggle GlideCursor with a key combination (default ⌃G)

**Precision mode** — see above.

The gear menu has **Language**, **Open at Login**, **Donate…**, the website, and **Quit**.

GlideCursor is free. From the second launch it shows a short note asking for a donation; tick "Don't show this again" to stop it.

---

## Privacy & Security

GlideCursor **does not collect or transmit any data**.

All processing happens entirely on your Mac.

Accessibility permission is required solely to monitor and control cursor movement.
GlideCursor reads when a finger touches or leaves the trackpad (not what you type or where you click) to start and stop gliding.

---

## Disclaimer

This software is provided **as is**, without warranty of any kind.

The author is not responsible for any damages resulting from the use of this software.

Compatibility with all mice and trackpads is **not guaranteed**.

Use at your own risk.

GlideCursor is open source. You are free to fork and modify it.

---

## Uninstall

GlideCursor can be completely removed in four steps.

### 1. Quit the app

Click the GlideCursor icon in the menu bar and choose **Quit**.

### 2. Move the app to Trash

Drag **GlideCursor.app** from `/Applications` to the Trash, or run:

```bash
sudo rm -rf /Applications/GlideCursor.app
```

### 3. Remove preferences and saved state

```bash
# User settings (speed, glide length, devices, shortcut, etc.)
rm -f ~/Library/Preferences/jp.yaoyorozu.glidecursor.plist

# Saved window state (auto-created by macOS)
rm -rf ~/Library/Saved\ Application\ State/jp.yaoyorozu.glidecursor.savedState
```

### 4. Revoke Accessibility permission

Open **System Settings → Privacy & Security → Accessibility** and remove GlideCursor from the list.

> If you turned on **Open at Login** (or added GlideCursor to Login Items manually), also remove it from
> **System Settings → General → Login Items & Extensions**.

That's all — GlideCursor leaves no other files on your system.
