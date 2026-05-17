/**
 * Permission-gated render variant: no permissions.
 *
 * Marketing_Influence_View = false. The LWC's `canViewPanel` getter blocks
 * the entire <article>. FlexiPage Component Visibility is the first line of
 * defense; this is the LWC-internal defense-in-depth.
 */
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_View",
  () => ({ default: false }),
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
  onOcr: false,
  isAcr: false,
  isConsultant: false,
  topics: [],
  touchCount: 1,
  lastTouchAt: null,
  assets: []
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-engagement-panel — no permissions", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("panelHiddenWithoutViewPerm", async () => {
    const element = createElement("c-engagement-panel", {
      is: EngagementPanel
    });
    element.recordId = RECORD_ID_OPP;
    element.recordContext = "Opportunity";
    document.body.appendChild(element);
    getForOpportunity.emit([SARAH]);
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("article.engagement-panel")
    ).toBeNull();
  });
});
