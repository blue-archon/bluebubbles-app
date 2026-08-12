# BlueBubbles Community Fork

> **Unofficial community fork** of [BlueBubblesApp/bluebubbles-app](https://github.com/BlueBubblesApp/bluebubbles-app).
> It stays current with the latest upstream and adds the features and fixes below. Not affiliated with or
> endorsed by the BlueBubbles project.
>
> **Prebuilt binaries** (Android APK, Linux desktop package) are on the
> [Releases page](https://github.com/blue-archon/bluebubbles-app/releases).

## What this fork is

A BlueBubbles client that carries a handful of improvements the official app doesn't have yet, rebased on the
latest upstream release (currently 2.1.1), so you also get BlueBubbles' newest work before it reaches the Play
Store, Microsoft Store, or Flathub. Everything here that isn't fork-specific is offered upstream as a pull
request, so the fork shrinks as those land. The FCM on/off toggle and the "Clear Configurations" fix this fork
shipped last release have since merged into upstream
([#3163](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3163),
[#3164](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3164)), so they are now part of the base for
everyone and no longer carried here.

## Features

### 1. Per-contact Do Not Disturb bypass  *(flagship)*
The stock app puts the entire notification channel on the DND override list, so *every* message bypasses
Do Not Disturb. This fork uses Android's native "starred contacts can interrupt" rule instead: only
contacts you've **Favorited** in your Android contacts app ring through DND, and everyone else respects it.
Opt-in, off by default, under Settings → Notification Settings → **Override DND for Favorites**.
See [setup](#do-not-disturb-bypass-setup) below. Offered upstream as
[#3064](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3064).

### 2. Reliability fixes ahead of the next official release
Fixes that aren't in a shipped upstream build yet. The theme is "messages are less likely to silently
vanish." All are offered upstream as PRs, so this list shrinks as they merge:

| What you get | Upstream PR |
|---|---|
| Incoming messages don't silently go missing (a null field in a message could drop it on arrival) | [#3131](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3131) |
| Reliable push via UnifiedPush / ntfy, attachments included (large pushes could fail to arrive) | [#3132](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3132) |
| Group chats stop losing messages or hanging on a loading spinner (stale participant list) | [#3062](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3062) |
| Desktop notifications show in the narrow single-pane window (otherwise you'd get none there) | [#3071](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3071) |
| No crash when a message arrives before the conversation view finishes loading | [#3161](https://github.com/BlueBubblesApp/bluebubbles-app/pull/3161) |

### 3. Larger Android heap
`android:largeHeap="true"` for extra memory headroom on message-heavy devices.

## Installing

- **Android (APK):** signed with this fork's own key, so it **cannot install over the official app** —
  uninstall the official app first (messages live on the server and re-sync). Use the `prod`-flavor APK;
  it uses the same package id (`com.bluebubbles.messaging`).
- **Linux desktop:** an Arch/pacman package (`.pkg.tar.zst`) is attached to releases (installs to
  `/opt/bluebubbles`; per-user data stays in `~/.local/share/app.bluebubbles.BlueBubbles/`). Other
  distros: build from source.
- **Windows / macOS:** no prebuilt binaries — build from source (standard Flutter build).

## Do Not Disturb bypass setup

1. In the app: Settings → Application Settings → Notification Settings → enable **Override DND for Favorites**.
2. Android: Settings → Notifications → Do Not Disturb → Allowed during DND → enable **Starred contacts**
   (label varies by Android version / manufacturer).
3. Star/favorite the contacts you want to reach you during DND in your contacts app.
4. Do **not** add BlueBubbles to the DND "Apps" override list — that bypasses DND for everything again.

**How it works:** the global `com.bluebubbles.new_messages` channel no longer calls `setBypassDnd(true)`.
On each incoming message, if the sender is a starred contact, the notification `Person` is built with
`setUri(lookupUri)` + `setImportant(true)` so Android's DND system grants the per-contact exception;
non-starred senders get neither and respect DND normally. In group chats the bypass keys off the
*sender's* starred status, not the group.

---

# BlueBubbles

BlueBubbles is an open-source, cross-platform ecosystem of apps that brings iMessage to Android, Windows, Linux, and the web. Send messages, media, reactions, and more — all from your non-Apple devices.

> **Note:** BlueBubbles requires a Mac running the BlueBubbles Server and an active Apple ID. A macOS virtual machine on Windows or Linux works as well.

---

## Features

### Core Messaging

- Send and receive iMessages, SMS, and MMS
- View and send tapbacks, stickers, and emoji reactions
- Full support for read receipts and delivered timestamps
- Threaded replies (requires macOS 11+)
- Create new chats and group conversations
- Mute or archive conversations
- Share your location

### Customization

- Robust theming engine with light and dark mode support
- Choose between iOS, Material, or Samsung-style UI skins
- Extensive settings to personalize your experience
- Full cross-platform support — message from Android, Linux, Windows, and macOS

### Private API Features

With optional Private API setup, you can unlock deeper iMessage integration:

- Send and receive typing indicators in real time
- Send tapbacks, subject lines, message effects, and replies
- Automatically mark chats as read on your Mac
- Rename group chats and manage participants

> Private API features require additional configuration. See the [Private API setup guide](https://docs.bluebubbles.app/helper-bundle/installation) for instructions.

---

## Screenshots

<table>
  <tr>
    <td align="center">Chat List</td>
    <td align="center">Message View</td>
    <td align="center">Private API Features</td>
  </tr>
  <tr>
    <td><img src="https://raw.githubusercontent.com/BlueBubblesApp/bluebubbles-app/master/screenshots/Samsung%20Galaxy%20S10%2B%20Prism%20Black%20-%20imessage_framed.png" width=270></td>
    <td><img src="https://raw.githubusercontent.com/BlueBubblesApp/bluebubbles-app/master/screenshots/Samsung%20Galaxy%20S10+%20Prism%20Black%20-%20messaging_framed.png" width=270></td>
    <td><img src="https://raw.githubusercontent.com/BlueBubblesApp/bluebubbles-app/master/screenshots/Samsung%20Galaxy%20S10+%20Prism%20Black%20-%20privateAPI_framed.png" width=270></td>
  </tr>
</table>

---

## Getting Started

1. Download and install the **BlueBubbles Server** on your Mac: [Server releases](https://github.com/BlueBubblesApp/BlueBubbles-Server/releases)
2. Download the **BlueBubbles client app** for your platform: [Client releases](https://github.com/BlueBubblesApp/blueBubbles-app/releases)
3. Follow the [installation guide](https://bluebubbles.app/install/) to connect everything together

The client is also available on:

- [Google Play](https://play.google.com/store/apps/details?id=com.bluebubbles.messaging)
- [Snap Store](https://snapcraft.io/bluebubbles)
- [Flathub](https://flathub.org/apps/app.bluebubbles.BlueBubbles)
- [Microsoft Store](https://www.microsoft.com/store/productId/9P3XF8KJ0LSM)

---

## Community

We have an active and welcoming community. Come say hello, get help, or follow along with development:

- **Discord:** [discord.gg/6nrGRHT](https://discord.gg/6nrGRHT) — the best place for support, feedback, and general chat
- **Reddit:** [r/BlueBubbles](https://www.reddit.com/r/BlueBubbles/)
- **Website:** [bluebubbles.app](https://bluebubbles.app)
- **Documentation:** [docs.bluebubbles.app](https://docs.bluebubbles.app)
- **FAQ:** [bluebubbles.app/faq](https://bluebubbles.app/faq)

---

## Contributing

Contributions are always welcome. Whether it's fixing a bug, improving performance, or adding a new feature — we appreciate the help.

Before getting started, please read [CONTRIBUTING.md](CONTRIBUTING.md) for setup instructions and code conventions.

To report a bug or request a feature, [open an issue on GitHub](https://github.com/BlueBubblesApp/bluebubbles-app/issues). Please search before opening a new ticket.

---

## Donating

BlueBubbles is free and open-source, maintained entirely by volunteers. If you find the project valuable, consider supporting its development:

[bluebubbles.app/donate](https://bluebubbles.app/donate)

---

## Sponsors

| ![signpath](https://signpath.org/assets/favicon-50x50.png) | Free code signing on Windows provided by [SignPath.io](https://about.signpath.io/), certficate by [SignPath Foundation](https://signpath.org/) |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|

---

## License

BlueBubbles is released under the terms of the [LICENSE](LICENSE) file in this repository.
