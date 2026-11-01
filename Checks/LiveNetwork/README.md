# Live network privacy check (macOS)

Run `bash Checks/LiveNetwork/run.sh` when you intend to contact ChatGPT and YouTube. This is a manual network audit. It compiles a separate process with the app’s production ChatGPT session and artwork loader. WebKit receives an empty nonpersistent store. The artwork request uses a fixed public video ID.

The output reports the document hostname, navigation state, HTTP status when available, hostnames from the main document’s HTTPS Resource Timing entries, and the byte count of an accepted image. For artwork, a positive byte count means the production loader accepted a successful HTTP response and the image passed its format and size checks. A zero count can reflect a network failure or a rejected response. The script can finish even if the service is unavailable. Check the observations in the output.

Resource Timing covers entries visible to the main document during the sample. Subframes, redirects, service workers, background processes and traffic after sign-in may have other destinations. For comparison across runs, record the date, HTTP status and measurement method along with the host list.

## Installed debug build

Launching the installed debug executable with `--audit-chatgpt-hosts` opens the ChatGPT window using the app’s usual website store. Quit the running app first. Eight seconds after the first completed main document on chatgpt.com, the app prints one line starting with `NOTCH_HOST_AUDIT` to standard output. The isolated JavaScript context reads HTTPS resource hostnames from the main document’s Performance timeline. The result contains the number of entries and the sorted distinct hosts. A subsequent ordinary launch resumes normal operation. Confirm sign-in visually when documenting a signed-in run.
