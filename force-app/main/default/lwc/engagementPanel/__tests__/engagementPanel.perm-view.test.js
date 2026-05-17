/**
 * Permission-gated render variant: View tier (read-only).
 *
 * Marketing_Influence_View = true, Marketing_Influence_Power_User = false.
 * Expected: panel renders contact rows + topic chips + relative dates, but
 * NO Add / Dismiss / View-all action buttons.
 *
 * Lives in a separate file because `@salesforce/customPermission/<name>`
 * resolves at module-load time. Re-importing inside `jest.isolateModules`
 * collides with LWC's process-global custom-element registry (lightning-icon
 * etc.). One file per perm variant gives each suite a clean module realm.
 */
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_View",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_Power_User",
  () => ({ default: false }),
  { virtual: true }
);

jest.mock("c/addToDealTeamModal", () => ({
  open: jest.fn().mockResolvedValue({ result: "closed" })
}));
jest.mock("c/alreadyAddedModal", () => ({
  open: jest.fn().mockResolvedValue({ result: "closed" })
}));
jest.mock("c/engagementDetailModal", () => ({
  open: jest.fn().mockResolvedValue({ result: "closed" })
}));

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn().mockResolvedValue(undefined) }),
  { virtual: true }
);

import { createElement } from "lwc";
import EngagementPanel from "c/engagementPanel";
import getForOpportunity from "@salesforce/apex/EngagementController.getForOpportunity";

jest.mock(
  "@salesforce/apex/EngagementController.getForOpportunity",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EngagementController.getForAccount",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/EngagementController.dismissContact",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const RECORD_ID_OPP = "006000000000001AAA";

const SARAH = {
  contactId: "003000000000001",
  name: "Sarah Johnson",
  title: "Chief Financial Officer",
  accountName: "United Healthcare",
  onOcr: false,
  ocrRole: null,
  isAcr: false,
  acrRole: null,
  isConsultant: false,
  topics: ["Network Management", "Payment Integrity"],
  touchCount: 3,
  lastTouchAt: "2026-05-09T14:00:00.000Z",
  assets: []
};
const MIKE = {
  contactId: "003000000000002",
  name: "Mike Chen",
  title: "VP Engineering",
  accountName: "United Healthcare",
  onOcr: true,
  ocrRole: "Technical Evaluator",
  isAcr: false,
  acrRole: null,
  isConsultant: false,
  topics: ["Claims Editing"],
  touchCount: 1,
  lastTouchAt: "2026-05-10T10:00:00.000Z",
  assets: []
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function buildPanel() {
  const element = createElement("c-engagement-panel", { is: EngagementPanel });
  element.recordId = RECORD_ID_OPP;
  element.recordContext = "Opportunity";
  document.body.appendChild(element);
  return element;
}

describe("c-engagement-panel — View-tier permission gating", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("viewerSeesPanel_withoutActions", async () => {
    const element = buildPanel();
    getForOpportunity.emit([SARAH, MIKE]);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("article.engagement-panel")
    ).not.toBeNull();
    expect(
      element.shadowRoot.querySelectorAll('[data-test="deal-team-row"]').length
    ).toBe(1);
    expect(
      element.shadowRoot.querySelectorAll('[data-test="not-on-team-row"]')
        .length
    ).toBe(1);
    expect(
      element.shadowRoot.querySelector('[data-test="view-all-button"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelectorAll('[data-test="add-button"]').length
    ).toBe(0);
    expect(
      element.shadowRoot.querySelectorAll('[data-test="dismiss-button"]').length
    ).toBe(0);
  });

  it("viewTierStillSeesTopicsAndDates", async () => {
    const element = buildPanel();
    getForOpportunity.emit([SARAH]);
    await flushPromises();

    expect(
      element.shadowRoot.querySelectorAll(".eng-topic-chip").length
    ).toBeGreaterThan(0);
    expect(
      element.shadowRoot.querySelector("lightning-relative-date-time")
    ).not.toBeNull();
  });
});
