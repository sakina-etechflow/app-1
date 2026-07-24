# Passport & ID Photo

> On-device passport and ID photo validation app built with Flutter and Google ML Kit.

A Flutter app for iOS and Android that turns a selfie into a compliant passport
or ID photo. You capture (or import) a photo, the app checks it against the
official government rules for the document you're applying for, tells you in
plain language exactly what to fix, and exports a correctly-sized image or a
print-ready sheet.

All image analysis runs **on-device**. The photos themselves are never uploaded.

---

## How it works

```
Pick document ──▶ Capture (live coaching) ──▶ Process on-device ──▶ Results
                                                                      │
                          Export (save / share / print)  ◀── Preview ─┘
```

1. **Pick a document** — choose the country/document you're applying for.
2. **Capture** — a live camera preview with a face oval overlay and real-time
   coaching ("move closer", "look straight ahead") guides you to a good frame.
   You can also import an existing photo.
3. **Process** — the photo is normalised to an upright JPEG, ML Kit extracts
   face landmarks and a person mask, and the rule engine evaluates every check.
4. **Results** — each rule shows as pass / warning / fail with a specific fix.
5. **Export** — save the compliant image, share it, or print a cut-guide sheet.

---

## Architecture

This is a monorepo with a deliberate split between the **rule engine** and the
**app**, so the compliance logic can be tested without a device, camera, or ML.

```
mob-app-passport-and-id-photo/
├── packages/
│   └── compliance_core/     # Pure-Dart rule engine — no Flutter, no ML
│       └── lib/src/
│           ├── engine.dart          # evaluate(signals, image, config) → report
│           ├── config/              # 6 document specs + thresholds
│           ├── checks/              # C1–C15 check implementations
│           ├── pipeline/            # alteration_policy — the no-AI-edit gate
│           └── models/              # ImageData, FaceSignals, PersonMask, …
│
└── passport_app/            # The Flutter app
    └── lib/
        ├── main.dart                # Firebase bootstrap + routes
        ├── screens/                 # splash, home, capture, processing,
        │                            #   results, preview, paywall, export, settings
        ├── services/                # ML bridge, pipeline, billing, ads, auth, sync
        ├── state/app_state.dart     # single source of truth for the flow
        └── widgets/                 # oval overlay, check tile
```

The app never talks to ML Kit or pixels directly inside the rules. Services
translate camera/ML output into `compliance_core`'s `FaceSignals`, and the pure
engine does the deciding. This keeps the rule logic identical between the app
and its test suite.

> **Why the split matters for setup:** `passport_app` depends on
> `compliance_core` through a **local path dependency**
> (`compliance_core: { path: ../packages/compliance_core }` in
> `passport_app/pubspec.yaml`). You do **not** clone or publish the package
> separately — running `flutter pub get` inside `passport_app/` resolves it
> automatically from the sibling folder. See [Getting started](#getting-started).

### The rule engine

`evaluate(FaceSignals signals, ImageData? image, DocumentConfig config)` returns
a `ComplianceReport`. Passing `image = null` runs only the signal-based checks
(C1–C9, C15) for fast live coaching; passing decoded pixels plus a person mask
adds the pixel checks (C10–C14).

**The 15 checks:**

| ID  | Check | Basis |
|-----|-------|-------|
| C1  | Exactly one face present | landmarks |
| C2  | Head orientation — no tilt/turn (yaw, pitch, roll) | landmarks |
| C3  | Head height (chin-to-crown) within spec % | landmarks + mask |
| C4  | Eye-line position (where required) | landmarks |
| C5  | Horizontal centering | landmarks |
| C6  | Both eyes open | landmarks |
| C7  | Expression / mouth (neutral, strict for UK & Schengen) | landmarks |
| C8  | Glasses (user-confirmed; ML Kit can't classify reliably) | confirm step |
| C9  | Head covering (warning only — religious/medical exceptions) | — |
| C10 | Background uniformity | pixels + mask |
| C11 | Background colour within document target | pixels + mask |
| C12 | Shadows (background gradient + face shadowing) | pixels + mask |
| C13 | Exposure (face luminance, clipped highlights) | pixels |
| C14 | Sharpness & resolution (Laplacian variance) | pixels |
| C15 | No AI / retouch / alteration (enforced for US & UK) | pipeline record |

### Supported documents

Six MVP specs, each transcribed from its official source with a source URL and a
verification date, and tagged with a confidence level:

- **US Passport**
- **US Visa (DS-160)**
- **UK Passport**
- **Schengen Visa**
- **India Passport**
- **India OCI**

> The three India-family specs are kept deliberately distinct (35×45 white vs.
> 51×51 light-not-white), because mixing them is a top rejection cause.

Adding a document = adding one `DocumentConfig` in
`packages/compliance_core/lib/src/config/documents.dart`. No engine changes.

---

## Getting started

### 1. Set up your environment

| Tool | Version used | Notes |
|------|--------------|-------|
| **Flutter SDK** | 3.44.x (stable) | Dart `^3.12.2` — pinned in `pubspec.yaml`. |
| **JDK** | 17 or newer | Needed by the Android Gradle Plugin. The JDK bundled with a recent Android Studio works. |
| **Android SDK** | API 36 (build-tools 36.x) | Install via Android Studio → SDK Manager. |
| **Xcode + CocoaPods** | latest (macOS only) | iOS builds only. |
| **Firebase** | project + config file | Optional to run; see step 4. |

After installing, confirm the toolchain is healthy:

```bash
flutter doctor
```

Every line that matters for building should show `[✓]`
(**Flutter**, **Android toolchain**, and — on macOS — **Xcode**).

> **💡 IDE tip (avoids indexing/analysis confusion).**
> Because the Flutter project is **nested** inside `passport_app/`, open that
> folder **directly** in VS Code or Android Studio — *not* the repo root. If you
> prefer to open the root (e.g. to edit both the app and the engine), add
> **both** `passport_app/` and `packages/compliance_core/` as workspace folders
> so the analyzer resolves the path dependency correctly.

### 2. Clone the repository

```bash
git clone https://github.com/etechflow/mob-app-passport-and-id-photo.git
cd mob-app-passport-and-id-photo
```

### 3. Install dependencies

```bash
cd passport_app
flutter pub get
```

This single command also resolves the local `compliance_core` package via its
path dependency — **no separate install is required**. You only need to run
`flutter pub get` inside `packages/compliance_core/` if you are editing the
engine in isolation and want to run *its* tests directly (see
[Running tests](#running-tests)).

### 4. Configure Firebase (optional for a first run)

The repo ships a **placeholder** `lib/firebase_options.dart`, so the app builds
and the core photo flow runs without any Firebase setup. Cloud sync and auth
simply degrade to safe no-ops until you provide real config:

```bash
# once, if you don't have it
dart pub global activate flutterfire_cli
# from passport_app/, with your own Firebase project selected
flutterfire configure
```

### 5. Run it

```bash
# from passport_app/
flutter run                 # on a connected device or emulator
```

---

## Building an installable APK (for team testing)

To hand a testable build to teammates without the App Store / Play Store:

```bash
# from passport_app/
flutter build apk --release
# ➜ build/app/outputs/flutter-apk/app-release.apk  (universal, ~113 MB)
```

The size is dominated by the bundled ML Kit models. For a smaller download, build
per-CPU-architecture APKs (each tester installs only the one for their device):

```bash
flutter build apk --release --split-per-abi
# ➜ app-arm64-v8a-release.apk (~40 MB), app-armeabi-v7a-release.apk, app-x86_64-release.apk
```

**Installing on a phone:** copy the `.apk` to an Android device, tap it in a file
manager, and allow *"Install from unknown sources"* when prompted.

> An `.apk` is a compiled Android package — it only installs on **Android**. It
> cannot be opened on Windows/macOS or inspected as source in an editor.

---

## Feature build log — A1-01 → A1-11

The app was built in sprint tickets `A1-01`…`A1-11`. Each entry below lists **what
it delivers** and the **process / how to verify** it, so a new contributor can
trace any feature to its screen, service, or config.

### A1-01 · Scaffold + rule engine
- **Delivers:** the monorepo skeleton — the Flutter app plus the pure-Dart
  `compliance_core` engine with document specs and the C1–C15 check framework.
- **Process:** `packages/compliance_core` is a standalone Dart package; the app
  depends on it by path. Start here to understand data flow: `engine.dart` →
  `checks/` → `models/`.

### A1-02 · Home screen (S2)
- **Delivers:** country/document search, document-type list, a per-document spec
  preview, and a **Start** action.
- **Process:** `lib/screens/home_screen.dart`. Documents come from
  `compliance_core`'s `config/documents.dart` — adding one there makes it appear
  here automatically.

### A1-03 · Camera capture (S3)
- **Delivers:** live camera with an alignment overlay, front/back flip,
  low-light warning, and system photo-picker import.
- **Process:** `lib/screens/capture_screen.dart` + the oval overlay widget.
  Camera permission is requested **at point of use**, with a purpose string in
  the platform manifests.

### A1-04 · On-device processing (S4)
- **Delivers:** face detection, crop, resize and background handling **entirely
  on-device** — no upload anywhere. Progress, cancel, and a "no face detected"
  failure state.
- **Process:** `services/processing_service.dart`, `photo_normalizer.dart`,
  `signal_extractor.dart`. ML Kit output is converted into `FaceSignals` here
  before the engine sees it.

### A1-05 · Results data model
- **Delivers:** the compliance checks wired to a results model producing
  **pass / warning / fail per check** with a status summary.
- **Process:** the engine's `ComplianceReport` drives
  `lib/screens/results_screen.dart`.

### A1-06 · Results screen + no-alteration gate 🔒
- **Delivers:** the results UI (retake / adjust per check) **and** enforcement of
  the **US no-AI-alteration** rule in code, by document type.
- **Process:** the gate lives in
  `packages/compliance_core/lib/src/pipeline/alteration_policy.dart` and is
  covered by `alteration_policy_test.dart`. This is a **blocker-level compliance
  requirement** — do not bypass it for US/UK documents.

### A1-07 · Preview + watermark
- **Delivers:** a formatted-photo preview that shows a **watermark in the free
  (unpaid) state**.
- **Process:** `lib/screens/preview_screen.dart`. The watermark is removed only
  after a successful unlock (A1-08 / A1-09).

### A1-08 · Paywall + In-App Purchase
- **Delivers:** a one-time **unlock SKU** wired via StoreKit (iOS) and Play
  Billing (Android), **Restore Purchases**, and full price shown before purchase.
- **Process:** `lib/screens/paywall_screen.dart` + `services/billing_service.dart`.
  **The SKU must be created in App Store Connect and Play Console first** — until
  it exists, the app falls back to the rewarded-video unlock. See
  [Before shipping](#before-shipping-to-production).

### A1-09 · Ads + export unlock
- **Delivers:** AdMob rewarded video, interstitial, and banner; an **ATT prompt**
  matching the privacy label; and the export / save / print sheet that unlocks
  after a purchase **or** a rewarded view.
- **Process:** `services/ads_service.dart` + `lib/screens/export_screen.dart`.
  Ships with Google **test** ad unit IDs — swap for real ones before release.

### A1-10 · Settings / About + end-to-end
- **Delivers:** Settings/About with a **privacy-policy link**, **Restore
  Purchases**, and app version; plus a full end-to-end flow test.
- **Process:** `lib/screens/settings_screen.dart`; version via `package_info_plus`;
  E2E coverage in `test/end_to_end_test.dart`.

### A1-11 · Privacy manifests & store declarations
- **Delivers:** iOS `PrivacyInfo.xcprivacy` for the app and every plugin, App
  Privacy nutrition labels, the Play Data Safety form, and matching AdMob
  ad-identifier declarations.
- **Process:** `ios/Runner/PrivacyInfo.xcprivacy` + the Android manifest;
  verified by `test/privacy_manifest_test.dart`.

---

## Running tests

```bash
# engine tests — fast, no device needed
cd packages/compliance_core && flutter test

# app tests (widget + end-to-end)
cd passport_app && flutter test
```

---

## Monetization

- **One-time unlock** via In-App Purchase (StoreKit / Play Billing only) removes
  the watermark, with a required **Restore Purchases** path.
- **Rewarded-video fallback** (AdMob) unlocks a single export when the IAP SKU
  isn't available.

The free tier produces a watermarked preview; unlocking (paid or rewarded)
exports the clean, spec-sized file.

## Privacy

- Passport/ID **photos never leave the device**.
- Cloud sync (Firestore) is limited to **non-image data**: preferences and a
  small history log (document type, country, pass/fail, timestamp).
- Firebase auth uses an anonymous account by default (no sign-in friction);
  users can optionally upgrade to email.
- iOS privacy manifest and ad-identifier declarations are included.

Every cloud/ads/auth call is guarded: if Firebase is unconfigured or offline,
those features degrade to safe no-ops and the core photo flow is unaffected.

---

## Before shipping to production

The app runs end-to-end today using test/placeholder credentials. Swap these for
real ones before release:

- [ ] **AdMob** — replace Google's test ad unit IDs (and the manifest app ID)
      with real ones.
- [ ] **In-App Purchase** — create the non-consumable unlock SKU in App Store
      Connect and Google Play Console. Until it exists, the app falls back to the
      rewarded-video unlock.
- [ ] **Firebase** — replace the placeholder `firebase_options.dart` with a real
      configuration to enable cloud sync.
- [ ] **Portal file-size limits** — verify current upload ceilings at export
      time for US Visa (CEAC) and UK passport paths (noted in the specs).

---

## Contributing

- Branch off `main`, keep the sprint-ticket prefix in commit subjects
  (e.g. `A1-12: …`) to stay consistent with the build log above.
- This project uses AI-assisted commits. When adding a `Co-Authored-By:` trailer,
  use an email tied to a real GitHub account so the co-author is recognised in
  the contributors list; otherwise the trailer is cosmetic only.
- Run both test suites (`flutter test` in each package) before opening a PR.

---

## Tech stack

Flutter · Dart · Google ML Kit (face detection + selfie segmentation) ·
`camera` · `image` · Firebase (Auth + Firestore) · `in_app_purchase` ·
`google_mobile_ads` · `pdf` / `printing` · `provider`

Built by eTechFlow.
