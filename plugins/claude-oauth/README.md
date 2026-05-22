# Claude (OAuth Pro/Max)

Use your Anthropic Claude Pro/Max subscription as an LLM provider in TypeWhisper for text
post-processing of dictated text — no API key, no per-token billing.

## What it does

When TypeWhisper finishes transcribing a voice recording, it can route the text through
an LLM for post-processing (rewriting, summarising, cleaning up, etc.). This plugin makes
that LLM be Claude, authenticated via the OAuth flow Anthropic provides for Claude Code.

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
- TypeWhisper 1.4.0+
- An active Claude Pro or Claude Max subscription
