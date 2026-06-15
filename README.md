# Claude (OAuth Pro/Max) — TypeWhisper Plugin

Use your **Anthropic Claude Pro/Max subscription** as an LLM provider in
[TypeWhisper](https://typewhisper.com) for text post-processing of dictated text —
**no API key, no per-token billing.**

> This is a fork of [TypeWhisper/typewhisper-plugins](https://github.com/TypeWhisper/typewhisper-plugins)
> that adds the `claude-oauth` plugin. It is **not** part of the official TypeWhisper catalog
> (see the disclaimer below for why).

## ⚠️ Disclaimer — independent, unofficial, experimental

This is an **independent, unofficial** project — **not affiliated with, authorized by, or
endorsed by Anthropic or TypeWhisper.** The `claude-oauth` plugin works by presenting
Anthropic's Claude Code OAuth client identity to use a Claude Pro/Max subscription from a
third-party app. That is **not a supported use of the subscription and may breach
[Anthropic's Terms of Service](https://www.anthropic.com/legal/consumer-terms).** It can stop
working at any time and could put your Anthropic account standing at risk. Published as an
**educational proof-of-concept — use entirely at your own risk.**

> "Claude" and "Anthropic" are trademarks of Anthropic, PBC; "TypeWhisper" of its respective
> owner. This project is not endorsed by either.

## Install

### Option A — Download the prebuilt bundle (no Xcode needed)

1. Download `ClaudeOAuthPlugin-*-macos-universal.bundle.zip` from the
   **[latest release](../../releases/latest)**.
2. Unzip it (double-click) → you get `ClaudeOAuthPlugin.bundle`.
3. Clear the download-quarantine flag and move it into TypeWhisper's plugin folder:
   ```bash
   xattr -dr com.apple.quarantine ~/Downloads/ClaudeOAuthPlugin.bundle
   mv ~/Downloads/ClaudeOAuthPlugin.bundle \
      ~/Library/Application\ Support/TypeWhisper/Plugins/
   ```
4. Quit and restart TypeWhisper.

### Option B — Build from source (needs Xcode command line tools)

```bash
git clone https://github.com/mguttmann/typewhisper-plugins.git
cd typewhisper-plugins/plugins/claude-oauth
./install.sh
```

Then quit and restart TypeWhisper.

After restarting, activate the plugin under
*Settings → Plugins → Claude (OAuth Pro/Max)*.

**Full usage, setup steps, model list, and refresh details:**
see [`plugins/claude-oauth/README.md`](plugins/claude-oauth/README.md).

## Requirements

- macOS 14.0+ (Apple Silicon or Intel — the prebuilt bundle is universal)
- TypeWhisper 1.4.0+
- An active Claude Pro or Claude Max subscription
- For Option B only: Xcode command line tools (`xcode-select --install`)

**macOS only.** TypeWhisper for Windows uses a completely separate C#/.NET plugin system,
so this Swift plugin cannot run there — not even by rebuilding. A Windows version would be
a full rewrite in C#. (Windows already has an official API-key-based `Claude` plugin; a
Pro/Max-OAuth equivalent would have to be written from scratch.) See the
[plugin README](plugins/claude-oauth/README.md#platform-support) for details.

## Heads-up

This plugin uses the same OAuth client identifier that Claude Code uses internally and
identifies API requests as Claude Code so that Pro/Max subscriptions accept them. That is
an **unofficial use of the subscription** under Anthropic's Terms of Service, which is why
it is not in the official TypeWhisper catalog. It may stop working if Anthropic changes
their OAuth client policy. Tokens are stored only in the macOS Keychain; no telemetry is
sent anywhere except `api.anthropic.com` and `platform.claude.com`. Use at your own risk.
