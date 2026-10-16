# Thông Dịch — live English/Spanish → Vietnamese interpreter for iPhone

Optimized for **iPhone 15 Pro Max** and **iPhone Air**. 100% offline, listen-only (never plays sound).

| | |
|---|---|
| Speech recognition | NVIDIA Parakeet Ultra (English + Spanish, detected automatically) on the Neural Engine · optional Apple Live engine |
| Translation | Gemma 4 E2B (default on 15 Pro Max) · Gemma 4 E4B (default on iPhone Air) · TranslateGemma 4B — all on the iPhone **GPU** with Apple MLX |
| Modes | Everyday · Work (business, medical, legal, tech, school, customer service) · Catholic Mass |
| Sound sources | 1-on-1 conversation · Loudspeaker (Mass, events) · pre-recorded audio/video files |
| Extras | History grouped by place and date · offline GPS place names · Big-text display · Dark & Light mode · Vietnamese/English interface · your own glossary |

---

## What you need

- A **Windows PC** (yours works) and an **iPhone 15 Pro Max or iPhone Air on iOS 26**.
- A free **Apple ID** and a free **GitHub** account.
- About **6.5 GB** free on the iPhone (12 GB if you add the iPhone Air model) and twice that on the PC.

There are four one-time steps: **A** build the app, **B** install it, **C** download the models on the PC, **D** copy the models to the iPhone.

---

## A. Build the app file (.ipa) — free, on GitHub's Mac computers

iPhone apps can only be compiled on a Mac, so this project includes an automatic build that runs on GitHub's free Macs.

**Easiest:** create an empty **public** GitHub repository (for example `thong-dich`), then tell Claude its name. Claude can upload the project, start the build, and fix anything the build reports.

**Or do it yourself:**

1. Sign in at github.com, then select **+ › New repository**. Name it `thong-dich`, choose **Public** (builds are free for public repos), and select **Create repository**.
2. On the new repository page, select **uploading an existing file**. Open the unzipped `ThongDich` folder and drag everything inside it, including the `.github` folder, onto the page. Then select **Commit changes**.
3. Open the **Actions** tab. If asked, select **I understand my workflows, go ahead and enable them**. Then open **Build iPhone app** and select **Run workflow**.
4. Wait about 20–40 minutes for a green check mark. Open the finished run and download **ThongDich-iPhone-app** from the bottom of the page. Unzip it to get:
   - `ThongDich.ipa` — use this one.
   - `ThongDich-compat.ipa` — use only if step B refuses the first one.

## B. Install on the iPhone with Sideloadly (Windows)

1. Install **iTunes** and **iCloud** from apple.com. Use the web-download versions, not the Microsoft Store versions; Sideloadly needs their drivers. Then install **Sideloadly** from sideloadly.io.
2. Connect the iPhone with a cable, unlock it, and tap **Trust**.
3. In Sideloadly:
   - Drag in `ThongDich.ipa`.
   - Enter your Apple ID and select **Start**.
   - Type your password and the 2-factor code when asked.
4. On the iPhone, go to **Settings › Privacy & Security › Developer Mode**, turn it **On**, and let the iPhone restart. If the option isn't there, run step 3 once first.
5. On the iPhone, go to **Settings › General › VPN & Device Management**, tap your Apple ID, and tap **Trust**.

**Every 7 days** a free Apple ID requires re-signing. Open Sideloadly and select **Start** again with the same `.ipa`. Your models, history, and settings are kept. Sideloadly can also refresh automatically when the PC and iPhone are on the same Wi-Fi.

## C. Download the AI models on your PC (one time)

1. Open the `PC-Model-Downloader` folder and double-click **Get-Models.bat**.
2. Answer the two questions:
   - **TranslateGemma**: Yes is recommended.
   - **Gemma 4 E4B**: say Yes only if you will use the iPhone Air.
3. Wait for the downloads to finish. They resume automatically if interrupted; just run the file again.

When it finishes, a folder called **ThongDich-Transfer** opens with a few `.tdpack` files.

## D. Copy the models to the iPhone (no internet needed on the phone)

1. Connect the iPhone and open the **Apple Devices** app (or iTunes).
2. Select your iPhone, then **Files › Thông Dịch**.
3. Drag **all the `.tdpack` files** from ThongDich-Transfer onto Thông Dịch and wait for the copy to finish.
4. Open **Thông Dịch** on the iPhone. It installs the packs by itself (a few minutes, with a progress bar) and deletes them afterward to free space.

**Alternative:** copy the `.tdpack` files to a USB-C flash drive formatted **exFAT**, plug it into the iPhone, and in the app tap **⋯ › Settings › AI models & setup › Import from Files**.

The first launch after installing takes up to about a minute while the speech model prepares. Later launches are fast.

---

## Using the app

- Choose a mode at the top: **Everyday**, **Work**, or **Mass**. Then tap the big microphone button.
- **Mass and events (loudspeaker):** hold the phone with its **back toward the altar or loudspeaker**. The app uses the back microphone and boosts quiet, echoey sound. It waits for whole sentences before translating, so the homily isn't translated in fragments.
  - Standard responses appear instantly in the official Vietnamese wording, marked *Lời chuẩn phụng vụ*.
  - Prayers the congregation says together show as a prayer card, for example *Kinh Lạy Cha*.
- **1-on-1:** put the phone between you. English and Spanish are recognized automatically, even when people switch languages.
- **Big text:** the **Chữ lớn / Big text** button shows only the Vietnamese in large letters, for reading at a distance or for elders.
- **Recordings:** the **Bản ghi / Recording** button lets you pick a voice memo, audio file, or video.
  - You can also share a recording from Voice Memos or Files to **Thông Dịch**.
  - Turn on **Recorded through a loudspeaker** for recordings made in a church or hall.
- **History** (clock button): every session is saved automatically with date, time, and place. Group by **Place** or **Date**, swipe to delete, or use **⋯** to delete a place, a day, or everything. **Share** exports the bilingual text.
- **Places:** the first time you're somewhere new, tap the pink **Name this place** chip, for example *Nhà thờ Thánh Giuse*. After that, sessions there are labeled automatically using GPS. GPS works in Airplane Mode and your location never leaves the phone. You can turn this off in **Settings › Update location when I use the app**.
- **Settings** (⋯):
  - **Translation:** how people are addressed (tôi–bạn, tôi–anh, con–bác…), Southern or Northern vocabulary, work field, and your glossary.
  - **Listening:** speech engine and microphone.
  - **Display:** text size, Dark/Light mode, and app language.

## Privacy & offline

- The app contains **no internet features**, and it also blocks any web request at startup. It works in **Airplane Mode**.
- Speech, translation, history, and places stay on the iPhone. Models and history are excluded from iCloud backup.
- The app never plays sound. Its audio session is record-only.

## Troubleshooting

| Problem | Fix |
|---|---|
| Sideloadly: an error mentioning "entitlement" or "memory limit" | Use `ThongDich-compat.ipa`. |
| "Not enough free memory for this model" | Close other apps, or pick **Gemma 4 E2B** in Settings › Translator. |
| The app stopped opening after a week | Re-sign with Sideloadly (step B). |
| Models not found | Settings › AI models & setup › **Check again**. Make sure the `.tdpack` copy finished. |
| Translation pauses when you leave the app | This is normal: iOS doesn't let apps use the GPU in the background. Listening continues, and translation catches up as soon as you return. |
| Apple Live engine not available | It needs Apple's speech pack already on the iPhone. The app never downloads one; use **Auto**. |

## For developers

- `ThongDichKit/` is a Swift package containing all the code: audio capture, speech engines, the translation pipeline, and SwiftUI screens.
- `project.yml` is the XcodeGen spec. `.github/workflows/build-iphone-app.yml` is the cloud build.
- Dependencies are pinned: mlx-swift-lm 3.32.3, mlx-swift 0.32.x, swift-transformers 1.3.5, FluidAudio 0.17.7.

Model licenses: Gemma 4 / TranslateGemma (Google, Gemma terms), Parakeet (NVIDIA, CC-BY-4.0), Silero VAD (MIT).
