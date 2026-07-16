/// The six MVP document spec configs, transcribed verbatim from Part A of the
/// spec-and-compliance data pack. DO NOT retype these values from memory.
///
/// The three India specs are deliberately distinct — mixing them is the top
/// India rejection cause:
///   * India passport = 35x45, WHITE background.
///   * India OCI      = 51x51, LIGHT (explicitly NOT white).
///   * India e-Visa   = 51x51, WHITE  (second-wave, not in this MVP set).
///
/// Values below their confidence being HIGH carry a note describing the single
/// verification still owed (a portal file-size ceiling or one test upload).
library;

import '../models/document_config.dart';
import '../models/geometry.dart';

/// US Passport (print and online renewal). Confidence: HIGH.
const usPassport = DocumentConfig(
  id: 'us_passport',
  country: 'US',
  documentType: 'passport',
  displayName: 'US Passport',
  outputSizeMm: SizeMm(51, 51), // 2 x 2 inches, exact
  minResolutionPx: SizePx(600, 600),
  maxResolutionPx: SizePx(1200, 1200),
  dpiMin: 300,
  headHeightMinPct: 50, // 25-35 mm chin-to-crown within the 51 mm frame
  headHeightMaxPct: 69,
  eyeLineMinPctFromBottom: 56,
  eyeLineMaxPctFromBottom: 69,
  backgroundRule: BackgroundRule.whiteRequired,
  backgroundTarget: Rgb(250, 250, 248),
  backgroundAcceptMin: Rgb(235, 235, 235), // accept 235-255, near-neutral
  backgroundAcceptMax: Rgb(255, 255, 255),
  glassesRule: GlassesRule.banned, // banned since 2016; medical exception only
  expressionRule: ExpressionRule.neutralClosedMouthOk,
  maxFileSizeKb: 10240, // 10 MB
  minFileSizeKb: 54,
  recencyDays: 180,
  alterationAllowed: false, // 2026 rule: no AI, filters, retouching
  printLayout: '4x6 sheet, multiple 2x2 with cut guides',
  confidence: Confidence.high,
  sourceUrl:
      'https://travel.state.gov/content/travel/en/passports/how-apply/photos.html',
  lastVerifiedDate: '2026-07-08',
);

/// US Visa (DS-160 digital). Confidence: HIGH.
const usVisaDs160 = DocumentConfig(
  id: 'us_visa_ds160',
  country: 'US',
  documentType: 'visa_ds160',
  displayName: 'US Visa (DS-160)',
  outputSizeMm: SizeMm(51, 51),
  minResolutionPx: SizePx(600, 600),
  maxResolutionPx: SizePx(1200, 1200),
  dpiMin: 300,
  headHeightMinPct: 50,
  headHeightMaxPct: 69,
  eyeLineMinPctFromBottom: 56,
  eyeLineMaxPctFromBottom: 69,
  backgroundRule: BackgroundRule.whiteRequired,
  backgroundTarget: Rgb(250, 250, 248),
  backgroundAcceptMin: Rgb(235, 235, 235),
  backgroundAcceptMax: Rgb(255, 255, 255),
  glassesRule: GlassesRule.banned,
  expressionRule: ExpressionRule.neutralClosedMouthOk,
  recencyDays: 180,
  alterationAllowed: false,
  confidence: Confidence.high,
  sourceUrl:
      'https://travel.state.gov/content/travel/en/us-visas/visa-information-resources/photos.html',
  lastVerifiedDate: '2026-07-08',
  notes:
      'JPEG only. The CEAC/DS-160 upload enforces its own file-size ceiling on '
      'the portal; validate the current portal limit at export time.',
);

/// UK Passport (print and online). Confidence: HIGH.
const ukPassport = DocumentConfig(
  id: 'uk_passport',
  country: 'UK',
  documentType: 'passport',
  displayName: 'UK Passport',
  outputSizeMm: SizeMm(35, 45),
  minResolutionPx: SizePx(600, 750),
  maxResolutionPx: SizePx(1200, 1500),
  dpiMin: 300,
  headHeightMinPct: 64, // 29-34 mm chin-to-crown within the 45 mm height
  headHeightMaxPct: 76,
  // No separate eye band: rely on head-height + vertical centring.
  backgroundRule: BackgroundRule.lightNotWhite,
  backgroundTarget: Rgb(215, 215, 210), // grey/cream
  backgroundAcceptMin: Rgb(190, 190, 185), // reject dark
  backgroundAcceptMax: Rgb(232, 232, 230), // reject pure white
  glassesRule: GlassesRule.banned, // banned since 2018; medical exception only
  expressionRule: ExpressionRule.neutralStrict, // no smile, no tilt
  maxFileSizeKb: 10240, // some portal paths cap at 4 MB; validate at export
  minFileSizeKb: 50,
  recencyDays: 30, // stricter than US: within one month
  alterationAllowed: false,
  confidence: Confidence.high,
  sourceUrl: 'https://www.gov.uk/photos-for-passports',
  lastVerifiedDate: '2026-07-08',
  notes:
      'Photo must NOT be a cropped section of a larger wide shot; downscaling '
      'reads as pixelation to the biometric checker. Capture at correct framing.',
);

/// Schengen Visa (harmonised, ICAO 9303). Confidence: MEDIUM-HIGH.
const schengenVisa = DocumentConfig(
  id: 'schengen_visa',
  country: 'Schengen',
  documentType: 'visa',
  displayName: 'Schengen Visa',
  outputSizeMm: SizeMm(35, 45),
  minResolutionPx: SizePx(700, 900), // VFS digital; verify per consulate
  maxResolutionPx: SizePx(1000, 1200),
  dpiMin: 300,
  headHeightMinPct: 71, // 32-36 mm chin-to-crown; head fills ~70-80% of frame
  headHeightMaxPct: 80,
  backgroundRule: BackgroundRule.lightNotWhite,
  backgroundTarget: Rgb(210, 210, 210),
  backgroundAcceptMin: Rgb(188, 188, 188),
  backgroundAcceptMax: Rgb(228, 228, 228),
  glassesRule: GlassesRule.discouraged,
  expressionRule: ExpressionRule.neutralStrict,
  maxFileSizeKb: 2048, // VFS commonly under 2 MB; verify per consulate
  recencyDays: 180,
  alterationAllowed: false,
  confidence: Confidence.mediumHigh,
  sourceUrl:
      'https://www.icao.int/publications/pages/publication.aspx?docnum=9303',
  lastVerifiedDate: '2026-07-08',
  notes:
      'Digital pixel and file-size specs vary by member state and by VFS Global '
      'vs consulate portal. Treat px/file-size as MEDIUM; verify against the '
      'specific consulate at export.',
);

/// India Passport (Passport Seva). Confidence: MEDIUM-HIGH.
const indiaPassport = DocumentConfig(
  id: 'india_passport',
  country: 'India',
  documentType: 'passport',
  displayName: 'India Passport',
  outputSizeMm: SizeMm(35, 45),
  minResolutionPx: SizePx(630, 810), // Passport Seva upload, 7:9 aspect
  maxResolutionPx: SizePx(630, 810),
  dpiMin: 300,
  headHeightMinPct: 80, // raised to 80-85% under ICAO enforcement (Sept 2025)
  headHeightMaxPct: 85,
  backgroundRule: BackgroundRule.whiteRequired, // WHITE (opposite of OCI)
  backgroundTarget: Rgb(250, 250, 250),
  backgroundAcceptMin: Rgb(240, 240, 240), // accept 240-255
  backgroundAcceptMax: Rgb(255, 255, 255),
  glassesRule: GlassesRule.banned, // effectively banned since 2025-09-01
  expressionRule: ExpressionRule.neutralClosedMouthOk,
  maxFileSizeKb: 250, // JPEG under ~250 KB (secondary 2026 sources)
  recencyDays: 180,
  alterationAllowed: false, // Passport Seva 2.0 checks for altered photos
  confidence: Confidence.mediumHigh,
  sourceUrl: 'https://www.passportindia.gov.in/',
  lastVerifiedDate: '2026-07-08',
  notes:
      '35x45 / 630x810 / white spec corroborated across 2026 sources but not '
      'from an official passportindia.gov.in sheet. Do one test upload through '
      'the Passport Seva photo step to finalise pixel and file-size, then HIGH.',
);

/// India OCI (Overseas Citizenship of India). Confidence: HIGH (official PDF).
const indiaOci = DocumentConfig(
  id: 'oci',
  country: 'India',
  documentType: 'oci',
  displayName: 'India OCI',
  outputSizeMm: SizeMm(51, 51), // 2 x 2 inches, official
  minResolutionPx: SizePx(200, 200), // portal range 200-900 px, square
  maxResolutionPx: SizePx(900, 900),
  dpiMin: 300,
  headHeightMinPct: 49, // head 25-35 mm chin-to-crown within 51 mm (like US)
  headHeightMaxPct: 69,
  eyeLineMinPctFromBottom: 55, // ~1-1/8 to 1-3/8 inch from bottom
  eyeLineMaxPctFromBottom: 69,
  backgroundRule: BackgroundRule.lightNotWhite, // light-coloured, NOT white
  backgroundTarget: Rgb(225, 225, 222),
  backgroundAcceptMin: Rgb(205, 205, 200), // reject dark/coloured
  backgroundAcceptMax: Rgb(238, 238, 235), // reject pure white
  glassesRule: GlassesRule.allowedNoGlare, // OK if no tint/glare, eyes visible
  expressionRule: ExpressionRule.neutralClosedMouthOk,
  maxFileSizeKb: 200, // 2026 sources; older say up to 500 KB / 1 MB
  recencyDays: 180,
  alterationAllowed: false, // official: do not retouch/enhance/soften
  confidence: Confidence.high,
  sourceUrl: 'https://ociservices.gov.in/Photo-Spec-FINAL.pdf',
  lastVerifiedDate: '2026-07-08',
  notes:
      'Photo spec HIGH (official gov PDF). Only open value is the portal '
      'file-size ceiling (target <=200 KB); confirm with one test upload. OCI '
      'also requires a separate signature image (JPEG, 1:3 h:w).',
);

/// All six MVP documents, in picker order.
const List<DocumentConfig> mvpDocuments = [
  usPassport,
  usVisaDs160,
  ukPassport,
  schengenVisa,
  indiaPassport,
  indiaOci,
];

/// Look up a document config by id (as used in the harness manifest).
DocumentConfig? documentById(String id) {
  for (final d in mvpDocuments) {
    if (d.id == id) return d;
  }
  return null;
}
