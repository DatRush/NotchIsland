# ChatGPT session checks

Run `bash Checks/ChatGPTSession/run.sh` on macOS. Exercises the production navigation-delegate callbacks with injected NSError values: offline/lost network, timeout, DNS/connectivity, TLS, cancellation, popup errors, recovery, process termination and pending operation cleanup. Verifies the main view uses a persistent store and retains its identity. No page is loaded, no credentials or storage contents are read, and no system clipboard is changed.

This does not prove login persistence, real connectivity recovery or authentication providers. Service errors within an already loaded ChatGPT page remain the website's responsibility; no private requests or retries are added. The application never automatically resends a question.

Also verifies that an unavailable chat retains the selected screenshot URL and manual retry prompt, remains retryable, and clears the prompt on dismissal. The fixture path is never read because the chat is unavailable.


## Local website-data reset

The suite additionally injects two nonpersistent WebKit stores and synthetic cookies,
loads local HTML with localStorage, and clears only the injected session store. It
checks cookie/localStorage deletion, preservation of the other store, invalidated
pending content, replacement of the page, no automatic restart and repeated reset.
It does not clear the default store, log into a real account or upload a file.
Production clears all website data types from its own persistent WebKit store after
confirmation. Live signed-in reset and reauthentication remain separate checks.

Document-navigation policy checks cover exact host approval, lookalike/subdomain rejection, unsafe schemes, credentials and ports, blank popup bootstrap and HTTPS frames. These are pure policy tests; real authentication, redirect flows and browser launch still require live acceptance.
