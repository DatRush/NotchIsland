# NotchIsland Privacy Policy

Updated: 2 November 2026.
[Русский](PRIVACY.md)

## Author and contact

NotchIsland is maintained by Tair. Privacy questions and data requests:
[tair@kuanyshbayev.com](mailto:tair@kuanyshbayev.com).
The app is free and MIT-licensed; Boosty support is voluntary.
Kuanyshbayev Tair is the data controller for personal data in messages sent to this address. The sections below describe data on your Mac and what happens when you use an external service.

## Overview

NotchIsland primarily runs on your Mac. The current code has no author-operated backend,
advertising SDK, usage analytics or automatic crash reporting to the author. Clipboard
content, files, screenshots and reminders are not sent to an author's app server.
Integrations may transmit data to third-party services, whose websites and system
services follow their own policies.

## Data used

| Feature | Data, purpose and retention |
| --- | --- |
| Clipboard | Text, links, images and file references are read for history and preview. History stays in process memory: up to 50 entries, up to 12 hours from copying, with additional size limits. It is lost on quit and is not written to a separate on-disk database by the app. |
| Shelf | Added files/folders are copied into `~/Library/Application Support/NotchIsland/PrototypeShelf/`, with their name, identifier and time added. Retention is 6, 12 or 24 hours. Cleanup runs while the app operates or restores its data; immediate expiry deletion while the app is closed is not provided. Damaged or unrecognised records may remain to avoid data loss. Originals are not deleted. |
| Screenshots | The selected area is saved as PNG in your chosen folder (default `~/Pictures/NotchIsland`) and copied to the system clipboard. Saved PNGs have no automatic expiry. Temporary capture and error files are removed on normal completion; a crash or deletion failure may leave files behind. |
| Reminders | With macOS permission, EventKit reads available lists and works with entries in the selected list: text, notes, dates, identifiers and completion status. Creating, editing or deleting affects Apple Reminders and may sync through the chosen account. Completed entries are hidden in the island after six hours, not deleted from Apple. The selected list identifier is stored locally. Legacy migration reads reminders across all accessible lists to locate migration markers and avoid duplicates. |
| Legacy reminders | Older installations may retain `reminders.json`, `reminders-before-apple.json` and `apple-reminders-imported.json` under `~/Library/Application Support/NotchIsland/`. The first two may contain text and dates; the ledger contains migration identifiers. These files have no automatic expiry. |
| Music | Player, title, artist, playback and artwork information is read for display and control. The last source, title and artist are saved in preferences. Some players use Accessibility and capture of the artwork region. |
| Preferences and timer | Language, tab order/selection, screenshot folder, shelf retention, excluded apps, recent durations and other preferences are stored locally. The active application's identifier is used for exclusions and music integrations. The current timer session stays in memory. |

Pausing clipboard history stops new history entries; it is not a global ban on app access
to the system clipboard. Clearing history does not clear the system clipboard. Known
private markers and app exclusions are supported, but not every password or secret can
be identified reliably.

## ChatGPT and external connections

Main-page and new-window navigation is limited to chatgpt.com, auth.openai.com and auth0.openai.com. Other HTTPS websites require confirmation displaying the hostname; permission applies only to that host until the app restarts or ChatGPT data is cleared. A normal GET link can also be opened in the default browser. This rule does not restrict HTTPS frames or network resources within pages; it is not a filter for all website traffic.

ChatGPT opens `chatgpt.com` in embedded WebKit. The app interacts with page content to
adapt the interface, attach screenshots and copy answers. WebKit persists cookies,
website data and login sessions across launches. Credentials are not sent to an author
through a NotchIsland server.

On 1 November 2026, the embedded ChatGPT page using the app’s regular profile reported HTTPS resources on `chatgpt.com`, `ab.chatgpt.com`, `cdn.platform.openai.com` and `cdn.auth0.com`. The set of resources can vary by page and session.

OpenAI receives data under its own policy, including submitted content and connection
information. Attaching a screenshot passes its content and filename to the webpage,
which may begin uploading **before you press Send**. The ChatGPT screenshot workflow
automatically attaches the image to the draft; the app does not automatically send the
message. Before first use, the app explains the transfer and offers Continue or Cancel;
your choice to continue is saved in preferences. Do not use this workflow for information you do not want to share with OpenAI.
Conversation retention, training use and deletion depend on the service and account
settings. See [OpenAI's policy](https://openai.com/policies/privacy-policy/), including
its regional version for the EEA.

To recognize music, NotchIsland matches the title to browser tabs using macOS Automation and requests the public video page from YouTube. YouTube receives the IP address and video ID. The request uses no browser cookies. The category result is cached temporarily in memory. The YouTube category check runs automatically even when external artwork downloads are disabled.

The packaged app reads the active macOS media session locally through a bundled adapter. The last title, artist and player identifier are saved on the Mac. System artwork is processed in memory.

The music integration automatically polls supported running players, including while
the Music tab is closed, when system permissions are available. YouTube artwork
requests to `i.ytimg.com` are off by default. You can enable them using “Download
YouTube artwork from the internet” in Settings. The recipient then receives your
IP address and technical request data; the path contains the video identifier.
Turning this off cancels the current download and removes the remote artwork from
app memory; it does not recall a request already received by Google.
Artwork uses a separate ephemeral session without cookies, stored credentials or
disk caching. Only the fixed HTTPS YouTube artwork endpoint is allowed; redirects
are refused, and response bytes and image dimensions are bounded.
The Yandex artwork capture toggle controls a separate local feature.
See [Google's policy](https://policies.google.com/privacy).
Apple/iCloud processing depends on account settings and
[Apple's policy](https://www.apple.com/legal/privacy/).

The support button opens the author’s page in your browser. Boosty handles voluntary payments. NotchIsland does not receive card details or payment confirmations. As of 1 November 2026, the author has received no donations and does not share donor information with anyone. If the author starts receiving and using donors’ personal data, this section will be updated to describe the data, purpose and retention period. The platform’s notice is available under “Privacy policy” on the [Boosty website](https://boosty.to/).

Downloads and correspondence through GitHub are subject to
[GitHub's policy](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
Services may process data outside your country; their providers describe applicable
international transfer arrangements in their own policies.

## Permissions, logs and security

macOS controls Screen Recording (screenshots/artwork), Accessibility (music app controls),
Music automation and Reminders access. Permissions can be revoked in System Settings;
the related feature may stop working. System permission does not send all data to the author.

The app writes limited music integration diagnostics to the system log. Debug builds
can manually save ChatGPT page structure and dimensions to
`/private/tmp/notch-chatgpt-layout.json`. Its generator excludes message text, HTML,
cookies and URL values. That file is not automatically transmitted or deleted by the app.
macOS and third-party services may maintain their own logs.

New screenshots are created with POSIX mode 0600; the shelf root and new temporary capture directories use 0700. ACLs and other macOS mechanisms may affect effective access. A crash may leave temporary screenshots behind: on a subsequent launch, recognized remnants older than one day with a marker and no active lock are removed. Unmarked folders from older versions, symbolic links and unknown contents are not automatically removed.

The app does not implement its own encryption for shelf files or screenshots. Protection
depends on your macOS account and system safeguards. Backups and synced folders may retain
additional copies. File deletion is not guaranteed secure erasure of the storage medium.

## App updates

“Check for Updates…” requests the project’s release feed on GitHub. Background checks are off by default. Use “Automatically Check for Updates” in the NotchIsland menu to enable or disable them. When you choose to install an update, Sparkle downloads it from GitHub Releases and verifies its signature. GitHub and its delivery network receive your IP address and ordinary request metadata, including the User-Agent header. Sparkle system profiling is disabled. The update preference is stored locally.

## Controls and deletion

- Pause history, configure exclusions or clear history in the app.
- Remove shelf copies in the app; delete saved screenshots separately in Finder.
- Manage tasks in Apple Reminders. Deletions may sync across devices; hiding a completed
  task in the island does not delete it.
- Use ChatGPT sign-out and its data controls. Sign-out does not mean deletion of account
  conversations or all local WebKit data. In NotchIsland Settings, choose “Clear local
  ChatGPT data…” and confirm: ChatGPT windows close and cookies, cache and data for all
  embedded-browser websites, including sign-in sites, are removed. Local drafts are lost.
  The site does not reopen automatically; choose “Open ChatGPT” to continue. Safari/Chrome
  data, saved screenshots and OpenAI account conversations are not deleted. Clearing does
  not recall uploaded files. If the app reports remaining data, repeat the clear action.
- Deleting the `.app` does not automatically remove screenshots, preferences, shelf copies,
  web data or legacy reminder files. Do not delete migration files without considering
  repeat-import consequences.

### How to remove NotchIsland from this Mac

To remove just the app, choose Quit from its menu and move `NotchIsland.app` from its installation folder to the Trash. To also remove local data for the current macOS user:

1. **Before quitting**, note the screenshot folder in Settings (default: `~/Pictures/NotchIsland`) and save any screenshots and shelf copies you want to keep. Clear local ChatGPT data as described above, wait for the result, then quit. If the app is already gone, proceed to checking the folders.
2. In Finder, press **⇧⌘G** and open `~/Library/Application Support/NotchIsland`. This contains `PrototypeShelf` and, on older installations, reminder files and their migration ledger. For complete removal, move this folder to the Trash as a unit; do not restore legacy reminders without their ledger when reinstalling. Apple Reminders tasks and the originals of shelf files remain in place.
3. After quitting, run `defaults delete local.notchisland.prototype` in Terminal to remove this build’s preferences. This targets only the app’s preferences domain. If the domain does not exist, there are no preferences to remove.
4. Use ⇧⌘G to inspect `~/Library/WebKit`, `~/Library/Caches` and `~/Library/HTTPStorages`. In each, remove **only** the item named exactly `local.notchisland.prototype`, if present. HTTPStorages may also contain `local.notchisland.prototype.binarycookies` and temporary files named `local.notchisland.prototype.binarycookies_tmp_<number>.dat`. Keep the parent folders and all data belonging to Safari and other apps.
5. If no longer needed, remove individual PNGs from the screenshot folder you noted; a shared destination may contain unrelated files. Optionally remove the app’s backup ZIPs from `~/Library/Application Support/NotchIsland Backups`. If you manually created a debug report, check `/private/tmp/notch-chatgpt-layout.json`.
6. After a crash, capture remnants may exist in the current user’s temporary directory (find its path with `getconf DARWIN_USER_TEMP_DIR`). With the app quit, inspect only folders named `NotchIsland-Capture-<UUID>`; do not clear the whole temporary directory. Leave files of uncertain origin alone. Review the Trash before emptying it.

Clearing history does not replace the system clipboard: copy another piece of text to replace its last item. Revoke system permissions separately in macOS privacy settings. These steps do not erase cloud conversations, email, synced reminders or existing Mac backups. Paths were checked against this build; end-to-end removal in a separate account has not yet been tested.

## Correspondence and your rights

If you contact the author, they receive your sender address and message, including
attachments you provide. Do not send passwords, tokens, private conversations or unredacted
screenshots containing other people's data. Public GitHub issues are visible to others.

The mailbox `tair@kuanyshbayev.com` is hosted by iCloud Mail (Apple). The author uses
your address, message and attachments to respond and resolve your enquiry; the mail
provider processes them for delivery and storage under [Apple's policy](https://www.apple.com/legal/privacy/).
Support correspondence is deleted from the author's mailbox no later than 12 months
after the enquiry is closed, unless longer retention is required by law. This rule
does not delete the sender's copies or set retention periods for provider backups
or operational copies. It does not automatically apply to public GitHub issues
or supporter details.

For ordinary support, the author relies on the legitimate interest in answering users’ questions and resolving reported problems (GDPR Article 6(1)(f)). Providing an address and a description of the issue is voluntary. Without a return address, the author cannot reply by email. You may object to this processing on grounds relating to your particular situation. When the GDPR requires the author to handle a data rights request, the basis for that processing is compliance with a legal obligation (Article 6(1)(c)). [GDPR text](https://eur-lex.europa.eu/eli/reg/2016/679/oj).

Where GDPR applies to
processing by the author, contact the email above about access, correction, deletion,
restriction, objection, portability or withdrawal of consent, as applicable. You may
complain to a supervisory authority, including the
[Italian Garante](https://www.garanteprivacy.it/).
The author cannot remotely delete data from your Mac or third-party accounts.

## Changes

This document will be dated and updated when processing changes. New backend features
or analytics require a separate assessment and an updated description.
