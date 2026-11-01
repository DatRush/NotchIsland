# Compact ChatGPT regression checks

Run `bash Checks/ChatGPTCompact/run.sh` on macOS with Swift command-line tools.
The runner compiles the production `ChatGPTCompact.script` with an isolated WKWebView harness. A temporary test window is shown so animation frames and resize observations run normally; it closes when the tests finish. Build output is temporary and removed by the runner.

The fixtures use local HTML with a chatgpt.com base URL and a nonpersistent WebKit store. They do not connect to an account, upload a file, or send a message.

Checks cover:
- attachment card, working removal button and upload-error visibility;
- English, Russian, arbitrary labels with semantic identity, and an unknown control that must remain visible;
- separate composer rows, actual height reserved below the conversation, error hide/reveal and growing input;
- ordered, unordered and nested lists, and preservation of message-content containers;
- ordinary site layout at 900 px.

Unknown composer branches are intentionally preserved rather than hidden. Large attachment areas scroll within a composer capped at half the viewport. Live-site login, actual upload/retry/removal, generation cancellation, and changing between island and expanded window still need manual acceptance. Fixtures test our DOM adaptation, not every present or future version of ChatGPT.

Also covers an empty home page with no transcript or send button, first conversation insertion, and an authentication route that must stay unmodified. These are structural fixtures, not a captured DOM from a signed-in account.

The layout diagnostic is also checked for valid geometry output without fixture message text, arbitrary attribute values, or a full URL. The DEBUG bug button writes only a local structural report to `/private/tmp/notch-chatgpt-layout.json`.

The account-report regression covers a visible form editor with no legacy ID, a hidden textarea that must not introduce ambiguity, and a Conversation region without legacy message/turn markers.

The dynamic nested-composer case moves the form into Conversation and adds an unrelated submit button. Assertions wait for a fresh adaptation before checking the transcript, attachments, and composer.

The nested layout now requires a separate transcript branch and checks `elementFromPoint` at the editor center, so a layout rectangle alone cannot count as a visible, usable input.

Stop-generation regressions cover a hidden submit before visible stop, hit-testing/click delivery to the existing handler, attribute-only visibility transitions, and a disabled submit coexisting with stop. These fixtures do not test server-side cancellation.
