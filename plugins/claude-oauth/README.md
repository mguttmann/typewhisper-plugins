# Claude (OAuth Pro/Max)

Use your Anthropic Claude Pro/Max subscription as an LLM provider in TypeWhisper for text
post-processing of dictated text — no API key, no per-token billing.

## ⚠️ Disclaimer — independent, unofficial, experimental

This is an **independent, unofficial** project — **not affiliated with, authorized by, or
endorsed by Anthropic or TypeWhisper.** It works by presenting Anthropic's Claude Code OAuth
client identity so that a Claude Pro/Max subscription accepts requests from a third-party app.
That is **not a supported use of the subscription and may breach
[Anthropic's Terms of Service](https://www.anthropic.com/legal/consumer-terms).** It can stop
working at any time and could put your Anthropic account standing at risk. Published as an
**educational proof-of-concept — use entirely at your own risk.** "Claude" and "Anthropic" are
trademarks of Anthropic, PBC.

## What it does

When TypeWhisper finishes transcribing a voice recording, it can route the text through
an LLM for post-processing (rewriting, summarising, cleaning up, etc.). This plugin makes
that LLM be Claude, authenticated via the OAuth flow Anthropic provides for Claude Code.

## Installation

This plugin is not in the official TypeWhisper catalog. Two ways to install it — pick one.

### Option A — Download the prebuilt bundle (no Xcode needed)

Easiest if you just want to use it. Grab the universal (Apple Silicon + Intel) bundle from
the latest release:

→ **[Releases](https://github.com/mguttmann/typewhisper-plugins/releases/latest)**

```bash
# After downloading & unzipping ClaudeOAuthPlugin.bundle (e.g. in ~/Downloads):
xattr -dr com.apple.quarantine ~/Downloads/ClaudeOAuthPlugin.bundle
mv ~/Downloads/ClaudeOAuthPlugin.bundle \
   ~/Library/Application\ Support/TypeWhisper/Plugins/
```

The `xattr` line clears the download-quarantine flag so macOS will load the ad-hoc-signed
bundle. Then quit and restart TypeWhisper.

### Option B — Build from source (needs Xcode command line tools)

```bash
# 1. Clone the repo (or pull if you already have it)
git clone https://github.com/mguttmann/typewhisper-plugins.git
cd typewhisper-plugins/plugins/claude-oauth

# 2. Build + install in one step
./install.sh
```

`install.sh` compiles the plugin, wraps it into a `.bundle`, patches it so it finds
TypeWhisper's bundled SDK at runtime, ad-hoc code-signs it, and copies it into
`~/Library/Application Support/TypeWhisper/Plugins/`.

To update later: `git pull`, then run `./install.sh` again.

> **First build is slow:** Swift Package Manager downloads the TypeWhisper SDK on the
> first `./install.sh` run (~30–60 s). Subsequent builds are fast.

---

Either way: **quit and restart TypeWhisper** afterwards. The plugin then appears under
*Settings → Plugins → Claude (OAuth Pro/Max)* — activate it and follow the Setup steps below.

## Setup

1. Open TypeWhisper → *Settings → Plugins → Claude (OAuth Pro/Max)* and activate the plugin.
2. Click **Connect to Claude** (German UI: *"Mit Claude verbinden"*). Your default browser
   opens at `claude.ai/oauth/authorize`.
3. Log in with your Claude Pro/Max account and confirm the permission grant.
4. Anthropic shows an authorization code of the form `<code>#<state>`. Copy the whole thing.
5. Paste it back into the plugin's code field and click **Confirm** (German UI:
   *"Bestätigen"*).
6. The plugin exchanges the code for access + refresh tokens and stores them in the macOS
   Keychain.

After connecting, choose a model:

| Model | Best for |
|---|---|
| Haiku 4.5 (default) | Fast post-processing of short voice snippets |
| Sonnet 4.6 | More careful rewriting / structured output |
| Opus 4.7 | Complex transformations (slower) |

## Refresh strategy

Refresh tokens are single-use: every refresh returns a new access *and* refresh token, and
the previous refresh token dies immediately. The plugin handles this transparently:

- A 60-second background timer refreshes whenever less than 15 minutes of token validity
  remain.
- An on-demand refresh runs on plugin activation and before each LLM call if less than
  5 minutes remain.
- New tokens are persisted atomically to the keychain before the refresh function returns.

As long as TypeWhisper opens at least every few days, the refresh chain stays warm and
re-authentication is rare.

## Heads-up

This plugin uses the same OAuth client identifier that Claude Code uses internally and
identifies API requests as Claude Code calls so that Pro/Max subscriptions accept them.
That is an unofficial use of the subscription. If Anthropic changes their OAuth client
policy or tightens enforcement, the plugin may stop working without warning. Tokens are
stored only in the macOS Keychain; no telemetry is sent anywhere except `api.anthropic.com`
and `platform.claude.com`.

## Requirements

- macOS 14.0+
- TypeWhisper 1.4.0+ (verified on 1.5.0 build 826)
- An active Claude Pro or Claude Max subscription
- Xcode command line tools (for building: `xcode-select --install`)

## Troubleshooting

**"Missing SDK compatibility metadata for this TypeWhisper runtime"**

TypeWhisper 1.5.0 started requiring every plugin bundle to declare
`sdkCompatibilityVersion` in its runtime manifest. Plugin builds before v0.1.1
shipped a manifest without that field and fail to load on 1.5.0 with this error.

Fix: install **v0.1.1 or newer** — download the latest release bundle, or
`git pull` and re-run `./install.sh`. Then quit and restart TypeWhisper.

## Platform support

**macOS only.** Verified against TypeWhisper 1.5.0 (build 826).

This plugin will **not** run on TypeWhisper for Windows, and it cannot simply be "built on
Windows" either. The two platforms have entirely separate plugin systems:

| | macOS (this plugin) | Windows |
|---|---|---|
| Language | Swift | C# / .NET |
| UI | SwiftUI | WPF / XAML |
| Build artifact | `.bundle` (Mach-O dylib) | `.dll` (.NET assembly) |
| Manifest key | `principalClass` | `assemblyName` + `pluginClass` |

On top of that, this plugin depends on Apple-only frameworks: SwiftUI, AppKit
(`NSWorkspace`), CryptoKit, Security (`SecRandomCopyBytes`), `os.log`, and the macOS
Keychain. None of these exist on Windows.

A Windows version would be a **full rewrite in C#** (a `ClaudePlugin.cs`, a XAML settings
view, and the PKCE/OAuth/refresh logic re-implemented against the Windows plugin SDK), not
a recompile of this code.

Note: TypeWhisper for Windows already ships an official **Claude** plugin
(`com.typewhisper.claude`) for API-key-based access. If you want Claude on Windows today,
use that. A Pro/Max-OAuth equivalent for Windows does not exist yet and would have to be
written from scratch. Contributions welcome.
