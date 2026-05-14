#!/usr/bin/env node
"use strict";

const pptxgen = require("pptxgenjs");
const fs = require("fs");
const path = require("path");

const DOCS = "/Users/david/Work/Zelis/.claude/worktrees/feature-engagement-attribution/docs";
const WIREFRAMES = path.join(DOCS, "wireframes");
const OUT = path.join(DOCS, "Engagement-Attribution-Demo.pptx");

// ── Palette ────────────────────────────────────────────────────────────────
// Zelis-inspired: dark navy dominant, Salesforce blue accent, light content slides
const C = {
  navy:      "0D1B2A",   // dominant dark
  blue:      "0070D2",   // Salesforce blue accent
  lightBlue: "EBF4FF",   // very light blue for content bg
  white:     "FFFFFF",
  offWhite:  "F4F6F9",
  slate:     "36454F",
  midGray:   "64748B",
  lightGray: "E2E8F0",
  teal:      "028090",
  textDark:  "1A2332",
  textMid:   "4A5568",
};

// ── Helpers ────────────────────────────────────────────────────────────────
function readImg(filename) {
  const p = path.join(WIREFRAMES, filename);
  const data = fs.readFileSync(p);
  return "image/png;base64," + data.toString("base64");
}

function makeShadow() {
  return { type: "outer", color: "000000", blur: 8, offset: 3, angle: 135, opacity: 0.12 };
}

// Slide footer helper
function addFooter(slide, slideNum, total) {
  // Footer bar
  slide.addShape("rect", {
    x: 0, y: 5.375, w: 10, h: 0.25,
    fill: { color: C.navy },
    line: { color: C.navy }
  });
  // Date left
  slide.addText("May 2026", {
    x: 0.3, y: 5.375, w: 2, h: 0.25,
    fontSize: 9, color: C.white, valign: "middle", margin: 0
  });
  // Title center
  slide.addText("Engagement Attribution — Zelis", {
    x: 2.5, y: 5.375, w: 5, h: 0.25,
    fontSize: 9, color: C.white, align: "center", valign: "middle", margin: 0
  });
  // Slide number right
  slide.addText(`${slideNum} / ${total}`, {
    x: 7.7, y: 5.375, w: 2, h: 0.25,
    fontSize: 9, color: C.white, align: "right", valign: "middle", margin: 0
  });
}

// Slide title helper (content slides — light bg)
function addSlideTitle(slide, title) {
  slide.addText(title, {
    x: 0.5, y: 0.22, w: 9, h: 0.65,
    fontSize: 26, fontFace: "Trebuchet MS", bold: true,
    color: C.navy, valign: "middle", margin: 0
  });
  // thin teal rule under title
  slide.addShape("rect", {
    x: 0.5, y: 0.90, w: 9, h: 0.04,
    fill: { color: C.teal }, line: { color: C.teal }
  });
}

// ── Build ──────────────────────────────────────────────────────────────────
const pres = new pptxgen();
pres.layout = "LAYOUT_16x9"; // 10" × 5.625"
pres.author  = "David Wood";
pres.title   = "Engagement Attribution — Pattern Overview";
pres.subject = "Zelis — HubSpot→Salesforce Attribution";

const TOTAL = 6; // 5 content + 1 appendix

// ══════════════════════════════════════════════════════════════════════════
// SLIDE 1 — Title / Overview  (dark background)
// ══════════════════════════════════════════════════════════════════════════
const s1 = pres.addSlide();
s1.background = { color: C.navy };

// Large accent bar on left
s1.addShape("rect", {
  x: 0, y: 0, w: 0.12, h: 5.625,
  fill: { color: C.teal }, line: { color: C.teal }
});

// Title
s1.addText("Engagement Attribution", {
  x: 0.4, y: 0.5, w: 9.2, h: 0.9,
  fontSize: 38, fontFace: "Trebuchet MS", bold: true,
  color: C.white, valign: "middle", margin: 0
});

// Subtitle
s1.addText("A pattern I've implemented before — sharing for team evaluation", {
  x: 0.4, y: 1.35, w: 9.2, h: 0.5,
  fontSize: 16, fontFace: "Calibri", italic: true,
  color: "A0B8D0", valign: "middle", margin: 0
});

// Divider
s1.addShape("rect", {
  x: 0.4, y: 1.88, w: 9.2, h: 0.03,
  fill: { color: C.teal }, line: { color: C.teal }
});

// Bullets
const s1bullets = [
  "Captures every marketing engagement as an event-level record in Salesforce.",
  "Attributes engagement to Accounts and Opportunities through topic + account match — OCR membership not required.",
  "Surfaces engagement intelligence on Account and Opportunity pages for sales.",
  "Preserves raw event data for later attribution and AI work.",
  "Sharing the design with the team; will validate fit against our actual situation once discovery is done."
];

s1.addText(
  s1bullets.map((t, i) => [
    { text: t, options: { bullet: true, color: C.white, fontSize: 15, fontFace: "Calibri", breakLine: i < s1bullets.length - 1 } }
  ]).flat(),
  { x: 0.4, y: 2.0, w: 9.2, h: 2.8, valign: "top", margin: [0, 0, 0, 10], paraSpaceAfter: 6 }
);

// Footer
s1.addShape("rect", {
  x: 0, y: 5.375, w: 10, h: 0.25,
  fill: { color: "071322" }, line: { color: "071322" }
});
s1.addText("May 2026", { x: 0.3, y: 5.375, w: 2, h: 0.25, fontSize: 9, color: "607080", valign: "middle", margin: 0 });
s1.addText("Engagement Attribution — Zelis", { x: 2.5, y: 5.375, w: 5, h: 0.25, fontSize: 9, color: "607080", align: "center", valign: "middle", margin: 0 });
s1.addText("1 / 6", { x: 7.7, y: 5.375, w: 2, h: 0.25, fontSize: 9, color: "607080", align: "right", valign: "middle", margin: 0 });

// ══════════════════════════════════════════════════════════════════════════
// SLIDE 2 — Two views from one data set
// ══════════════════════════════════════════════════════════════════════════
const s2 = pres.addSlide();
s2.background = { color: C.offWhite };

addSlideTitle(s2, "OCR ≠ Buying Committee");
addFooter(s2, 2, TOTAL);

// Column headers
const colW = 4.2;
const colGap = 0.2;
const colStart = 0.7;

// Left header card
s2.addShape("rect", {
  x: colStart, y: 1.1, w: colW, h: 0.5,
  fill: { color: C.slate }, line: { color: C.slate },
  shadow: makeShadow()
});
s2.addText("Opportunity Contact Role", {
  x: colStart, y: 1.1, w: colW, h: 0.5,
  fontSize: 13, fontFace: "Trebuchet MS", bold: true,
  color: C.white, align: "center", valign: "middle", margin: 0
});

// Right header card
s2.addShape("rect", {
  x: colStart + colW + colGap, y: 1.1, w: colW, h: 0.5,
  fill: { color: C.teal }, line: { color: C.teal },
  shadow: makeShadow()
});
s2.addText("People Actually Engaging", {
  x: colStart + colW + colGap, y: 1.1, w: colW, h: 0.5,
  fontSize: 13, fontFace: "Trebuchet MS", bold: true,
  color: C.white, align: "center", valign: "middle", margin: 0
});

// Row data
const rows = [
  ["Sales-entered",                   "Observed via HubSpot"],
  ["Reflects the deal team",          "Reflects everyone interested"],
  ["Updated when reps remember",      "Recorded automatically"],
  ["Used by Campaign Influence",      "Not used by anything currently"],
];

rows.forEach((row, i) => {
  const y = 1.72 + i * 0.56;
  const bg = i % 2 === 0 ? C.white : C.lightGray;

  // Left cell
  s2.addShape("rect", { x: colStart, y, w: colW, h: 0.5, fill: { color: bg }, line: { color: C.lightGray } });
  s2.addText(row[0], {
    x: colStart + 0.1, y, w: colW - 0.2, h: 0.5,
    fontSize: 13, fontFace: "Calibri", color: C.textDark, valign: "middle", margin: 0
  });

  // Right cell
  s2.addShape("rect", { x: colStart + colW + colGap, y, w: colW, h: 0.5, fill: { color: bg }, line: { color: C.lightGray } });
  s2.addText(row[1], {
    x: colStart + colW + colGap + 0.1, y, w: colW - 0.2, h: 0.5,
    fontSize: 13, fontFace: "Calibri", color: C.textDark, valign: "middle", margin: 0
  });
});

// Sub-note
s2.addText(
  "Overlap exists but they aren't the same set. The gap includes the buying committee and ecosystem influencers (consultants, partners via AccountContactRelation).",
  {
    x: colStart, y: 4.98, w: colW * 2 + colGap, h: 0.35,
    fontSize: 10, fontFace: "Calibri", color: C.midGray, italic: true, margin: 0
  }
);

// ══════════════════════════════════════════════════════════════════════════
// SLIDE 3 — Architecture (simple flow)
// ══════════════════════════════════════════════════════════════════════════
const s3 = pres.addSlide();
s3.background = { color: C.offWhite };

addSlideTitle(s3, "Per-Touch Records, Per-Opportunity Signals");
addFooter(s3, 3, TOTAL);

// Mermaid diagram
const archSimpleData = readImg("arch-simple.png");
// 1112 x 316 → fit into ~8.5" wide, max 2.1" tall
const archSimpleW = 8.5;
const archSimpleH = archSimpleW * (316 / 1112);
const archSimpleX = (10 - archSimpleW) / 2;
s3.addImage({
  data: archSimpleData,
  x: archSimpleX, y: 1.05, w: archSimpleW, h: archSimpleH,
  altText: "Architecture flow diagram"
});

// Bullets below diagram
const s3bullets = [
  ["One Engagement Touch record per HubSpot event", " (downloads, form fills, webinars, etc.)."],
  ["Admin-managed routing rules", " classify each touch by topic and intent."],
  ["Opportunity matching uses topic + account + time window. ", "OCR membership not required."],
  ["Campaign Influence keeps running unchanged; ", "this augments it."]
];

const bulletY = 1.05 + archSimpleH + 0.25;
s3.addText(
  s3bullets.flatMap(([main, detail], i) => {
    const isLast = i === s3bullets.length - 1;
    return [
      { text: main, options: { bold: true, color: C.textDark, fontSize: 13, fontFace: "Calibri", bullet: true } },
      { text: detail + (isLast ? "" : ""), options: { bold: false, color: C.textDark, fontSize: 13, fontFace: "Calibri", breakLine: !isLast } }
    ];
  }),
  { x: 0.6, y: bulletY, w: 8.8, h: 5.375 - bulletY - 0.35, valign: "top", margin: [0, 0, 0, 10], paraSpaceAfter: 5 }
);

// ══════════════════════════════════════════════════════════════════════════
// SLIDE 4 — What sales sees (wireframe screenshots)
// ══════════════════════════════════════════════════════════════════════════
const s4 = pres.addSlide();
s4.background = { color: C.offWhite };

addSlideTitle(s4, "What Sales Sees — Compact Panel + Drill-Down");
addFooter(s4, 4, TOTAL);

const oppData  = readImg("screenshot-opportunity.png");
const acctData = readImg("screenshot-account.png");

// Two screenshots side by side
// Each screenshot is 1200 × 1227 — display at ~3.5" wide each
const imgH = 2.65;
const imgW = imgH * (1200 / 1227);
const imgY = 1.05;
const gap  = 0.3;
const totalW = imgW * 2 + gap;
const startX = (10 - totalW) / 2;

// Shadow rects behind screenshots
s4.addShape("rect", {
  x: startX - 0.05, y: imgY - 0.05, w: imgW + 0.1, h: imgH + 0.1,
  fill: { color: "D0D8E4" }, line: { color: "D0D8E4" }
});
s4.addShape("rect", {
  x: startX + imgW + gap - 0.05, y: imgY - 0.05, w: imgW + 0.1, h: imgH + 0.1,
  fill: { color: "D0D8E4" }, line: { color: "D0D8E4" }
});

s4.addImage({ data: oppData,  x: startX,                y: imgY, w: imgW, h: imgH, altText: "Opportunity engagement panel" });
s4.addImage({ data: acctData, x: startX + imgW + gap,   y: imgY, w: imgW, h: imgH, altText: "Account engagement panel" });

// Captions
s4.addText("Opportunity view", {
  x: startX, y: imgY + imgH + 0.05, w: imgW, h: 0.25,
  fontSize: 10, fontFace: "Calibri", color: C.midGray, align: "center", italic: true, margin: 0
});
s4.addText("Account view", {
  x: startX + imgW + gap, y: imgY + imgH + 0.05, w: imgW, h: 0.25,
  fontSize: 10, fontFace: "Calibri", color: C.midGray, align: "center", italic: true, margin: 0
});

// Bullets
const bulletStartY4 = imgY + imgH + 0.35;
s4.addText([
  { text: "Engagement panel sits on the right rail", options: { bold: true, fontSize: 12, color: C.textDark, fontFace: "Calibri", bullet: true } },
  { text: " — small footprint, alongside Chatter and Files.", options: { bold: false, fontSize: 12, color: C.textDark, fontFace: "Calibri", breakLine: true } },
  { text: 'One click "+ Add"', options: { bold: true, fontSize: 12, color: C.textDark, fontFace: "Calibri", bullet: true } },
  { text: " → role-picker modal → real OpportunityContactRole record created.", options: { bold: false, fontSize: 12, color: C.textDark, fontFace: "Calibri", breakLine: true } },
  { text: '"View all"', options: { bold: true, fontSize: 12, color: C.textDark, fontFace: "Calibri", bullet: true } },
  { text: " → grouped detail modal with per-asset history (multiple downloads of the same asset visible).", options: { bold: false, fontSize: 12, color: C.textDark, fontFace: "Calibri" } }
], { x: 0.5, y: bulletStartY4, w: 9, h: 5.375 - bulletStartY4 - 0.3, valign: "top", margin: [0, 0, 0, 10], paraSpaceAfter: 4 });

// ══════════════════════════════════════════════════════════════════════════
// SLIDE 5 — Outcomes + AI foundation  (dark background again)
// ══════════════════════════════════════════════════════════════════════════
const s5 = pres.addSlide();
s5.background = { color: C.navy };

// Left accent bar
s5.addShape("rect", {
  x: 0, y: 0, w: 0.12, h: 5.625,
  fill: { color: C.teal }, line: { color: C.teal }
});

// Title
s5.addText("Outcomes (From Prior Deployments) + AI Foundation", {
  x: 0.35, y: 0.22, w: 9.3, h: 0.65,
  fontSize: 22, fontFace: "Trebuchet MS", bold: true,
  color: C.white, valign: "middle", margin: 0
});

// Thin divider
s5.addShape("rect", {
  x: 0.35, y: 0.90, w: 9.3, h: 0.03,
  fill: { color: C.teal }, line: { color: C.teal }
});

// Column headers
const c5W = 4.35;
const c5X1 = 0.35;
const c5X2 = 0.35 + c5W + 0.3;

s5.addShape("rect", {
  x: c5X1, y: 1.0, w: c5W, h: 0.42,
  fill: { color: C.teal }, line: { color: C.teal }
});
s5.addText("Available Today", {
  x: c5X1, y: 1.0, w: c5W, h: 0.42,
  fontSize: 14, fontFace: "Trebuchet MS", bold: true, color: C.white,
  align: "center", valign: "middle", margin: 0
});

s5.addShape("rect", {
  x: c5X2, y: 1.0, w: c5W, h: 0.42,
  fill: { color: C.blue }, line: { color: C.blue }
});
s5.addText("Foundation for Tomorrow — AI / Next-Best-Action", {
  x: c5X2, y: 1.0, w: c5W, h: 0.42,
  fontSize: 12, fontFace: "Trebuchet MS", bold: true, color: C.white,
  align: "center", valign: "middle", margin: 0
});

// Left column bullets
const leftBullets = [
  "Attribution covers everyone who engaged, not just OCR members.",
  "Sales sees engagement signals tied to active opportunities.",
  "Event-level data preserved.",
  "Admin can add new touch types without engineering.",
  "Campaign Influence keeps working for baseline reporting."
];
s5.addText(
  leftBullets.map((t, i) => ({
    text: t,
    options: { bullet: true, color: C.white, fontSize: 13, fontFace: "Calibri", breakLine: i < leftBullets.length - 1 }
  })),
  { x: c5X1, y: 1.5, w: c5W, h: 2.9, valign: "top", margin: [0, 0, 0, 8], paraSpaceAfter: 8 }
);

// Right column bullets
const rightBullets = [
  'Per-rep next-best-action: "CFO at United Healthcare just downloaded pricing — third time. Reach out."',
  "Buying-motion detection: sequence-aware models (executive engagement → procurement → user).",
  "Cross-account influence: \"this consultant is active across three of our deals.\"",
  "Predictive deal scoring tied to engagement velocity, not just stage."
];
s5.addText(
  rightBullets.map((t, i) => ({
    text: t,
    options: { bullet: true, color: "B8D0F0", fontSize: 12, fontFace: "Calibri", breakLine: i < rightBullets.length - 1 }
  })),
  { x: c5X2, y: 1.5, w: c5W, h: 2.9, valign: "top", margin: [0, 0, 0, 8], paraSpaceAfter: 8 }
);

// Closing line
s5.addShape("rect", {
  x: 0.35, y: 4.62, w: 9.3, h: 0.55,
  fill: { color: "0A1520" }, line: { color: "0A1520" }
});
s5.addText(
  "“We’re not building the AI today. We’re making sure the data is in a shape that lets us build it.”",
  {
    x: 0.35, y: 4.62, w: 9.3, h: 0.55,
    fontSize: 13, fontFace: "Calibri", italic: true, color: "A0C4E8",
    align: "center", valign: "middle", margin: 0
  }
);

// Footer (dark variant)
s5.addShape("rect", {
  x: 0, y: 5.375, w: 10, h: 0.25,
  fill: { color: "071322" }, line: { color: "071322" }
});
s5.addText("May 2026", { x: 0.3, y: 5.375, w: 2, h: 0.25, fontSize: 9, color: "607080", valign: "middle", margin: 0 });
s5.addText("Engagement Attribution — Zelis", { x: 2.5, y: 5.375, w: 5, h: 0.25, fontSize: 9, color: "607080", align: "center", valign: "middle", margin: 0 });
s5.addText("5 / 6", { x: 7.7, y: 5.375, w: 2, h: 0.25, fontSize: 9, color: "607080", align: "right", valign: "middle", margin: 0 });

// ══════════════════════════════════════════════════════════════════════════
// SLIDE 6 — Appendix: Layer Fabric (detailed architecture)
// ══════════════════════════════════════════════════════════════════════════
const s6 = pres.addSlide();
s6.background = { color: C.offWhite };

addSlideTitle(s6, "Appendix: Layer Fabric (For Reference)");
addFooter(s6, 6, TOTAL);

// Detailed Mermaid diagram
// 1904 x 129 — very wide, short — fit to ~9" wide
const archDetailData = readImg("arch-detailed.png");
const detW = 9.0;
const detH = detW * (129 / 1904);
const detX = (10 - detW) / 2;

s6.addImage({
  data: archDetailData,
  x: detX, y: 1.05, w: detW, h: detH,
  altText: "Detailed layer architecture diagram"
});

const appBullets = [
  ["fflib-aligned layers:", " Service / Selector / Domain / UnitOfWork / Application factory."],
  ["Custom Metadata Types", " for admin-configurable routing rules."],
  ["Platform Events", " for async decoupling (ingest → routing; lead conversion → reparenting)."],
  ["Identity resolution", " treats unresolved touches as a first-class state (Pending Resolution)."]
];

const appBulletY = 1.05 + detH + 0.35;
s6.addText(
  appBullets.flatMap(([bold, rest], i) => {
    const isLast = i === appBullets.length - 1;
    return [
      { text: bold, options: { bold: true, color: C.textDark, fontSize: 13, fontFace: "Calibri", bullet: true } },
      { text: rest, options: { bold: false, color: C.textDark, fontSize: 13, fontFace: "Calibri", breakLine: !isLast } }
    ];
  }),
  { x: 0.6, y: appBulletY, w: 8.8, h: 5.375 - appBulletY - 0.35, valign: "top", margin: [0, 0, 0, 10], paraSpaceAfter: 5 }
);

// ── Write ──────────────────────────────────────────────────────────────────
pres.writeFile({ fileName: OUT }).then(() => {
  console.log("Written:", OUT);
}).catch(err => {
  console.error("ERROR:", err);
  process.exit(1);
});
