# GlideCursor

A macOS utility that adds inertia-based cursor movement.

---

## What GlideCursor Does

GlideCursor adds inertia to your cursor movement on macOS.

Flick your mouse or trackpad, and the cursor keeps gliding — then stops the moment you touch the input device again.

It works with both mouse and trackpad input.

---

## Mouse Behavior

Nothing happens while the mouse remains on the desk.

When you move the mouse and **lift it**, the cursor continues moving with inertia.

When the mouse touches the desk again, the cursor **stops immediately**.

---

## Trackpad Behavior

Flick the trackpad to start inertia movement.

To stop the cursor, simply place your finger on the trackpad and move it **even slightly**.

---

## Installation

Download the `.pkg` installer from the **Releases** page and run it.

When launching GlideCursor for the first time:

1. A welcome window will appear.
2. Click **Open System Settings**.
3. Enable **Accessibility** permission for GlideCursor.
4. Return to the app and click **Get Started**.
5. Turn GlideCursor **ON** from the menu bar.

---

## Settings

Open the GlideCursor menu from the menu bar icon to adjust:

- **Flick Sensitivity** — how easy it is to trigger inertia
- **Speed** — multiplier applied to the initial velocity
- **Friction** — how quickly the cursor decelerates
- **Max Velocity** — caps the maximum speed
- **Global Shortcut** — toggle GlideCursor on/off with a key combination (customizable)
- Settings can be **reset to defaults** at any time

---

## Privacy & Security

GlideCursor **does not collect or transmit any data**.

All processing happens entirely on your Mac.

Accessibility permission is required solely to monitor and control cursor movement.

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
# User settings (speed, friction, shortcut, etc.)
rm -f ~/Library/Preferences/jp.yaoyorozu.glidecursor.plist

# Saved window state (auto-created by macOS)
rm -rf ~/Library/Saved\ Application\ State/jp.yaoyorozu.glidecursor.savedState
```

### 4. Revoke Accessibility permission

Open **System Settings → Privacy & Security → Accessibility** and remove GlideCursor from the list.

> If you manually added GlideCursor to Login Items, also remove it from
> **System Settings → General → Login Items & Extensions**.

That's all — GlideCursor leaves no other files on your system.
