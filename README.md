# Passport & ID Photo

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

## Getting started

**Prerequisites:** Flutter SDK (Dart `^3.12.2`), Xcode (iOS), Android SDK.

```bash
# from passport_app/
flutter pub get
flutter run
```

### Running tests

```bash
# engine tests (fast, no device needed)
cd packages/compliance_core && flutter test

# app tests
cd passport_app && flutter test
```

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

## Tech stack

Flutter · Dart · Google ML Kit (face detection + selfie segmentation) ·
`camera` · `image` · Firebase (Auth + Firestore) · `in_app_purchase` ·
`google_mobile_ads` · `pdf` / `printing` · `provider`

Built by eTechFlow.
