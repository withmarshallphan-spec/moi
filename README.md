# moi

A small helper that lives in your Mac's notch. Tell it what you need, by typing or talking, and it does it, on your Mac, with native macOS features (no screen-clicking robots).

- **Clean up your desktop.** "clean up my desktop" sorts every loose file into folders by kind and quits the apps you haven't touched in a while. One button puts it all back.
- **Sort your photos.** "sort my flower photos and my trips" finds flowers with on-device Vision and works out every trip from where and when photos were taken ("Italy · Mar 2025"), then makes Photos albums. Your photos are never changed.
- **Pick a wallpaper.** "change my wallpaper to my best photo" ranks your photos with Apple's on-device photo-quality scoring and puts the best one up. Say "undo" to go back.
- **Run your day.** "gym tomorrow 16:30", "move it to 5pm", "the essay is done", "what's tomorrow?".
- **Tame your Mac.** "quit everything except Safari", "remove Discord from my Dock", "open YouTube in a private window", "clean up my downloads".
- **Focus.** "focus on the essay for 50 minutes". Open a distracting app and moi asks if you want to get back to it.
- **The notch, your way.** Rest your pointer on it for music, click it for your day. Edit it like a Lock Screen: music, now & next, Calendar, UV & weather, recent files. While music plays it shows the album cover, like an iPhone.

Everything shows you what will change first. moi never deletes files, never empties the Trash, never force-quits an app, and every change can be undone.

## Get it

moi is built from source for now (a signed download is coming):

```sh
git clone https://github.com/withmarshallphan-spec/moi.git
cd moi
MOI_FLAVOR=release MOI_BUILD_CONFIGURATION=release ./Scripts/build-app.sh
open Build/Moi.app
```

You need macOS 14 or later and Xcode or the Command Line Tools (`xcode-select --install`). There are no package dependencies.

## A brain, for free

moi understands common requests on its own, with no AI and no account. For everything else it uses a brain:

- **Apple Intelligence** on macOS 26: on your Mac, free, no setup.
- **Free cloud keys** from Google Gemini, Groq, OpenRouter, NVIDIA or Mistral. Paste any key into moi and it works out whose it is. Add two or three: when one runs out of free quota, the next takes over in the same chat.
- **Ollama or LM Studio** running on your Mac.

Keys stay in your Keychain. Paid providers are never used unless you choose them. The rules live in `Sources/MoiApp/Services/BrainChain.swift`.

## Privacy

Your plan, files and photos stay on your Mac. A cloud brain only receives what you type to moi, after you've said OK. Offline mode blocks every cloud request. Each macOS permission is asked for when you first use the feature that needs it, or all at once in the introduction. Details: [PRIVACY.md](PRIVACY.md).

## Develop

```sh
./Scripts/build-app.sh                 # Build/Moi Development.app, with its own separate data
./Scripts/test-core.sh                 # parser, plan, brain chain, photos, clean-up logic
./Scripts/test-workspace.sh            # persistence, focus, music, trust boundaries
./Scripts/test-refinement.sh           # wallpaper ranking, guides, desktop clean-up
MOI_FLAVOR=firstrun ./Scripts/build-app.sh   # Build/Moi First Run.app: a clean first launch
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## Made by

**[Marshall Phan](https://marshallphan.com).** See what else he's making at **[marshallphan.com](https://marshallphan.com)**.

If moi makes your Mac a little calmer, a star helps.

## License

[MIT](LICENSE). moi's character, logo, icon and sounds were made for this project and are covered by the same license.
