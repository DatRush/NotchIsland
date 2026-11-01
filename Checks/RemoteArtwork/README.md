# Remote artwork checks

Run `bash Checks/RemoteArtwork/run.sh` on macOS.

Uses a synthetic URLProtocol transport through the production URLSession delegates.
No real player, network request, account or shared cookie/cache modification is used.
Covers the fixed HTTPS host/path allowlist; URL credentials, ports, queries and path
encoding; no cookies/cache/credential storage; HTTP status and MIME; declared and
streamed byte caps; supported image formats and pixel dimensions; cancellation and
exactly-once completion. Redirect delegate decisions are invoked directly for same-
and different-host targets: no redirect is followed.

The fixture does not prove live CDN behaviour, TLS connectivity or detection of a
real YouTube player. Those remain separate integration checks.
