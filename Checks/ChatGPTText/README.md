# Response copying checks

Run `bash Checks/ChatGPTText/run.sh` on macOS. Local WebKit fixtures with a nonpersistent store verify the last assistant answer, selected fragments, code/list text, exclusion of toolbar/user text, busy generation, unknown structure, auth/foreign/insecure pages, and preservation of draft/attachment without submission. An isolated named clipboard checks text storage without modifying the system clipboard. No account or real messages are used.

Text transformation actions and prompt insertion were removed at the user's request on 22 October 2026. Only response copying remains. Live website markup may differ; manual Command-C remains available.

Signed-in layout fixtures also cover an accessibility-only speaker heading and a single content branch, rejection of visible quoted headings and embedded controls, and refusal to fall back to an older answer when the newest recognized container is ambiguous. On 23 October 2026, copying a plain answer from the installed app into TextEdit via Command-V was verified on the live account; selection and complex live answers remain separate checks.

Review regressions (25 October): selected Edit code content and mixed prose/code ranges; draft, unknown editor and user-message rejection; ordered start, reversed/value numbering and nested mixed lists with exact Markdown output.
