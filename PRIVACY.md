# Privacy

moi runs on your Mac. There's no account, no analytics and no server of ours.

## What stays on your Mac

- Your plan, settings and clean-up history: JSON files in `~/Library/Application Support/Moi/`.
- What Vision saw in your photos (labels only, never the photos): `photo-labels.json` in the same folder.
- When you last used each app (so moi can tell which ones you're not using): in moi's preferences.
- Brain usage (requests today, quota reported by the provider): in moi's preferences.
- API keys: in your macOS Keychain.

## What can leave your Mac, and only when you choose it

| What | Sent to | When |
|---|---|---|
| What you type or say to moi, plus the recent chat | The cloud brain you set up (Gemini, Groq, OpenRouter, NVIDIA, Mistral, OpenAI, Anthropic…) | After a one-time OK per provider. Backups only get messages if you already added and approved them. Never in offline mode. |
| Your plan's item names and times | Your cloud brain | Only if you turn on "Let … see my plan". Local brains always see it. |
| A place name you search for ("Italy"), and rough locations of photos near it | Apple's map service | When you search photos by place, or name trips. |
| Your chosen city's rough coordinates | [Open-Meteo](https://open-meteo.com) (free, no account) | Only with the notch's UV & weather part on, at most every 30 minutes, never in offline mode. |
| Album artwork lookups | Your music app | When "Show artwork" is on. |

Speech is recognised on your Mac; audio is never recorded or uploaded.

## What moi does with your files and photos

- Photos: reads your library only when you search, and can make albums. It never edits or deletes a photo.
- Files: moves them only after you confirm, and keeps a record so "Put back" restores them. It moves files to the Trash only when you pick them, and never empties the Trash.
- Apps: asks them to quit the normal way, so anything unsaved prompts you. It never force-quits.

## Permissions

Each is optional and asked for when you use the feature, or all at once in the introduction: Notifications, Microphone and Speech Recognition, Photos, Desktop and Downloads folders, Calendar (for the notch's Calendar part), controlling your music app, and Accessibility (only to open private Safari windows).
