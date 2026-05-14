/**
 * Jest spec for c-engagement-panel. Per TEST_DESIGN.md.
 *
 * Mock-factory note: sfdx-lwc-jest resolves the `c/` namespace via its own
 * resolver. When `jest.mock('c/foo', () => ({...}))` runs, the FACTORY-
 * returned object IS what the test (and the production code) import
 * directly — there is no ESM `default` unwrap step. So the mock shape is
 * `{open: jest.fn()}` at the top level, NOT `{default: {open: jest.fn()}}`.
 * Confirmed by diagnostic in test-audit-2026-05-12 §3 Cluster G.
 */
// Default the custom-permission scoped imports to "granted" so this suite
// (which clicks Add / View-all / Dismiss throughout) runs as Power User.
// View-tier and no-perm variants live in sibling files
// (engagementPanel.perm-view.test.js, engagementPanel.perm-none.test.js)
// because `@salesforce/customPermission/<name>` resolves at module load —
// one file per perm-combo is the cleanest way to get isolated module realms
// without colliding with LWC's process-global custom-element registry.
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_View",
  () => ({ default: true }),
  { virtual: true }
);
jest.mock(
  "@salesforce/customPermission/Marketing_Influence_Power_User",
  () => ({ default: true }),
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
import getForAccount from "@salesforce/apex/EngagementController.getForAccount";
import dismissContact from "@salesforce/apex/EngagementController.dismissContact";
import AddToDealTeamModal from "c/addToDealTeamModal";
import AlreadyAddedModal from "c/alreadyAddedModal";
import EngagementDetailModal from "c/engagementDetailModal";
import { refreshApex } from "@salesforce/apex";

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
const RECORD_ID_ACCOUNT = "001000000000001AAA";

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

const MADONNA = {
  contactId: "003000000000003",
  name: "Madonna",
  title: "Artist",
  accountName: "United Healthcare",
  onOcr: false,
  isAcr: false,
  isConsultant: false,
  topics: [],
  touchCount: 0,
  lastTouchAt: null,
  assets: []
};

const NAMELESS = {
  contactId: "003000000000004",
  name: null,
  title: null,
  accountName: "United Healthcare",
  onOcr: false,
  isAcr: false,
  isConsultant: false,
  topics: [],
  touchCount: 1,
  lastTouchAt: null,
  assets: []
};

const CONSULTANT = {
  contactId: "003000000000005",
  name: "Marcus Webb",
  title: "Consultant",
  accountName: "Deloitte",
  onOcr: false,
  isAcr: true,
  isConsultant: true,
  topics: ["Implementation"],
  touchCount: 2,
  lastTouchAt: "2026-05-09T09:00:00.000Z",
  assets: []
};

const ACR_NOT_CONSULTANT = {
  contactId: "003000000000006",
  name: "Pat External",
  title: "Vendor",
  accountName: "United Healthcare",
  onOcr: false,
  isAcr: true,
  isConsultant: false,
  topics: ["Auditing"],
  touchCount: 1,
  lastTouchAt: "2026-05-09T09:00:00.000Z",
  assets: []
};

const MANY_TOPICS = {
  contactId: "003000000000007",
  name: "Topic Heavy",
  title: "Lead",
  accountName: "United Healthcare",
  onOcr: false,
  isAcr: false,
  isConsultant: false,
  topics: ["A", "B", "C", "D"],
  touchCount: 4,
  lastTouchAt: "2026-05-09T09:00:00.000Z",
  assets: []
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function buildPanel({ recordContext = "Opportunity", recordName = "" } = {}) {
  const element = createElement("c-engagement-panel", {
    is: EngagementPanel
  });
  element.recordId =
    recordContext === "Account" ? RECORD_ID_ACCOUNT : RECORD_ID_OPP;
  element.recordContext = recordContext;
  element.recordName = recordName;
  document.body.appendChild(element);
  return element;
}

describe("c-engagement-panel", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    // mockClear preserves implementations (`mockResolvedValue` default);
    // mockReset would nuke them.
    AddToDealTeamModal.open.mockClear();
    AlreadyAddedModal.open.mockClear();
    EngagementDetailModal.open.mockClear();
    AddToDealTeamModal.open.mockResolvedValue({ result: "closed" });
    AlreadyAddedModal.open.mockResolvedValue({ result: "closed" });
    EngagementDetailModal.open.mockResolvedValue({ result: "closed" });
    refreshApex.mockClear();
    dismissContact.mockReset();
  });

  describe("wire / render states", () => {
    it("rendersEmptyStateWhenNoEngagements", async () => {
      const element = buildPanel();
      getForOpportunity.emit([]);
      await flushPromises();

      const empty = element.shadowRoot.querySelector('[data-test="empty"]');
      expect(empty).not.toBeNull();
      expect(empty.textContent).toMatch(/No engagement activity/i);
    });

    it("rendersPersonRowsAndDealTeamPartition", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      const dealTeamRows = element.shadowRoot.querySelectorAll(
        '[data-test="deal-team-row"]'
      );
      const notOnTeamRows = element.shadowRoot.querySelectorAll(
        '[data-test="not-on-team-row"]'
      );
      expect(dealTeamRows.length).toBe(1);
      expect(notOnTeamRows.length).toBe(1);

      const dealLabel = element.shadowRoot.querySelector(
        '[data-test="deal-team-section-label"]'
      );
      const notOnLabel = element.shadowRoot.querySelector(
        '[data-test="not-on-team-section-label"]'
      );
      expect(dealLabel.textContent).toMatch(/Deal Team — 1 on OCR/);
      expect(notOnLabel.textContent).toMatch(/Engaged — not on Deal Team · 1/);
    });

    it("rendersFlatListForAccountScope", async () => {
      const element = buildPanel({ recordContext: "Account" });
      getForAccount.emit([SARAH, MIKE]);
      await flushPromises();

      const accountRows = element.shadowRoot.querySelectorAll(
        '[data-test="account-row"]'
      );
      expect(accountRows.length).toBe(2);
      expect(
        element.shadowRoot.querySelector(
          '[data-test="deal-team-section-label"]'
        )
      ).toBeNull();
    });

    it("accountScopeHidesAddButton", async () => {
      const element = buildPanel({ recordContext: "Account" });
      getForAccount.emit([SARAH]);
      await flushPromises();

      expect(
        element.shadowRoot.querySelectorAll('[data-test="add-button"]').length
      ).toBe(0);
    });

    it("onOcrRowShowsBadgeNotButton", async () => {
      const element = buildPanel();
      getForOpportunity.emit([MIKE]);
      await flushPromises();

      expect(
        element.shadowRoot.querySelectorAll('[data-test="add-button"]').length
      ).toBe(0);
      expect(
        element.shadowRoot.querySelectorAll('[data-test="on-team-badge"]')
          .length
      ).toBe(1);
    });
  });

  describe("row decoration", () => {
    it("singleNameInitialsFallback", async () => {
      const element = buildPanel();
      getForOpportunity.emit([MADONNA]);
      await flushPromises();
      const initials = element.shadowRoot.querySelector(
        '[data-test="not-on-team-row"] .slds-avatar__initials'
      );
      expect(initials.textContent.trim()).toBe("M");
    });

    it("emptyNameInitialsFallbackToQuestionMark", async () => {
      const element = buildPanel();
      getForOpportunity.emit([NAMELESS]);
      await flushPromises();
      const initials = element.shadowRoot.querySelector(
        '[data-test="not-on-team-row"] .slds-avatar__initials'
      );
      expect(initials.textContent.trim()).toBe("?");
    });

    it("avatarClassConsultantWinsOverAcr", async () => {
      const element = buildPanel();
      getForOpportunity.emit([CONSULTANT]);
      await flushPromises();
      const avatar = element.shadowRoot.querySelector(
        '[data-test="not-on-team-row"] .slds-avatar'
      );
      expect(avatar.className).toContain("av-consultant");
      expect(avatar.className).not.toContain("av-acr");
    });

    it("avatarClassAcrWhenNotConsultant", async () => {
      const element = buildPanel();
      getForOpportunity.emit([ACR_NOT_CONSULTANT]);
      await flushPromises();
      const avatar = element.shadowRoot.querySelector(
        '[data-test="not-on-team-row"] .slds-avatar'
      );
      expect(avatar.className).toContain("av-acr");
    });

    it("visibleTopicsCappedAtTwoWithHiddenCount", async () => {
      const element = buildPanel();
      getForOpportunity.emit([MANY_TOPICS]);
      await flushPromises();

      const row = element.shadowRoot.querySelector(
        '[data-test="not-on-team-row"]'
      );
      const chips = row.querySelectorAll(
        ".eng-topic-chip:not(.eng-topic-chip_more)"
      );
      expect(chips.length).toBe(2);
      const more = row.querySelector(".eng-topic-chip_more");
      expect(more).not.toBeNull();
      expect(more.textContent.trim()).toBe("+2 more");
    });

    it("noHiddenTopicsBadgeWhenAllFit", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH]);
      await flushPromises();
      const row = element.shadowRoot.querySelector(
        '[data-test="not-on-team-row"]'
      );
      expect(row.querySelector(".eng-topic-chip_more")).toBeNull();
    });

    it("contactHotlinkAttributes", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();
      const links = element.shadowRoot.querySelectorAll(
        '[data-test="contact-link"]'
      );
      expect(links.length).toBe(2);
      const hrefs = Array.from(links).map((a) => a.getAttribute("href"));
      expect(hrefs).toEqual(
        expect.arrayContaining([
          `/lightning/r/Contact/${SARAH.contactId}/view`,
          `/lightning/r/Contact/${MIKE.contactId}/view`
        ])
      );
      links.forEach((a) => expect(a.getAttribute("target")).toBe("_top"));
    });
  });

  describe("add flow", () => {
    it("addClickDispatchesLegacyEvent", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      const handler = jest.fn();
      element.addEventListener("addtodealteam", handler);

      element.shadowRoot.querySelector('[data-test="add-button"]').click();
      expect(handler).toHaveBeenCalledTimes(1);
      const detail = handler.mock.calls[0][0].detail;
      expect(detail.contactId).toBe(SARAH.contactId);
      expect(detail.name).toBe(SARAH.name);
      expect(detail.currentRole).toBeNull();
      expect(detail.isPrimary).toBe(false);
    });

    it("addClickOpensAddModalWithExpectedShape", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      element.shadowRoot.querySelector('[data-test="add-button"]').click();
      await flushPromises();

      expect(AddToDealTeamModal.open).toHaveBeenCalledTimes(1);
      const args = AddToDealTeamModal.open.mock.calls[0][0];
      expect(args.contactId).toBe(SARAH.contactId);
      expect(args.contactName).toBe(SARAH.name);
      expect(args.opportunityId).toBe(RECORD_ID_OPP);
      expect(args.recordContext).toBe("Opportunity");
    });

    it("addSuccessRefreshesPanel_noRace", async () => {
      AddToDealTeamModal.open.mockResolvedValue({
        result: "success",
        payload: { success: true, ocrId: "00K000000000001AAA" }
      });
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      // We assert on refreshApex (the underlying chain) rather than
      // spying on element.refresh — LWC's proxy refuses external
      // method overrides even for @api members.
      refreshApex.mockClear();

      element.shadowRoot.querySelector('[data-test="add-button"]').click();
      await flushPromises();
      await flushPromises();

      expect(refreshApex).toHaveBeenCalledTimes(1);
      expect(AlreadyAddedModal.open).not.toHaveBeenCalled();
    });

    it("addSuccessAlreadyExistsOpensAlreadyAddedModal", async () => {
      AddToDealTeamModal.open.mockResolvedValue({
        result: "success",
        payload: {
          success: false,
          alreadyExists: true,
          ocrId: "00K000000000001AAA",
          addedByUserName: "Jane Rep",
          addedAt: "2026-05-11T12:00:00.000Z"
        }
      });
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();
      jest.spyOn(element, "refresh").mockResolvedValue();

      element.shadowRoot.querySelector('[data-test="add-button"]').click();
      await flushPromises();
      await flushPromises();

      expect(AlreadyAddedModal.open).toHaveBeenCalledTimes(1);
      const args = AlreadyAddedModal.open.mock.calls[0][0];
      expect(args.contactName).toBe(SARAH.name);
      expect(args.addedByUserName).toBe("Jane Rep");
      expect(args.ocrId).toBe("00K000000000001AAA");
      expect(args.opportunityId).toBe(RECORD_ID_OPP);
    });

    it("addCancelDoesNotRefresh", async () => {
      AddToDealTeamModal.open.mockResolvedValue({ result: "cancel" });
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();
      // We assert on refreshApex (the underlying chain) rather than
      // spying on element.refresh — LWC's proxy refuses external
      // method overrides even for @api members.
      refreshApex.mockClear();

      element.shadowRoot.querySelector('[data-test="add-button"]').click();
      await flushPromises();
      await flushPromises();

      expect(refreshApex).not.toHaveBeenCalled();
      expect(AlreadyAddedModal.open).not.toHaveBeenCalled();
    });
  });

  describe("view-all flow", () => {
    it("viewAllClickDispatchesLegacyEvent", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      const handler = jest.fn();
      element.addEventListener("viewall", handler);

      element.shadowRoot.querySelector('[data-test="view-all-button"]').click();
      expect(handler).toHaveBeenCalledTimes(1);
      const detail = handler.mock.calls[0][0].detail;
      expect(detail.recordId).toBe(RECORD_ID_OPP);
      expect(detail.recordContext).toBe("Opportunity");
    });

    it("viewAllOpensDetailModalWithShape", async () => {
      const element = buildPanel({ recordName: "United Healthcare" });
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      element.shadowRoot.querySelector('[data-test="view-all-button"]').click();
      await flushPromises();

      expect(EngagementDetailModal.open).toHaveBeenCalledTimes(1);
      const args = EngagementDetailModal.open.mock.calls[0][0];
      expect(args.recordContext).toBe("Opportunity");
      expect(args.recordName).toBe("United Healthcare");
      expect(args.opportunityId).toBe(RECORD_ID_OPP);
      expect(Array.isArray(args.engagements)).toBe(true);
      expect(args.engagements.length).toBe(2);
    });

    it("viewAllChainsIntoAddFlowOnAddToTeam", async () => {
      EngagementDetailModal.open.mockResolvedValue({
        result: "add-to-team",
        payload: {
          contactId: SARAH.contactId,
          contactName: SARAH.name
        }
      });
      AddToDealTeamModal.open.mockResolvedValue({
        result: "success",
        payload: { success: true, ocrId: "00KX" }
      });
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();
      // We assert on refreshApex (the underlying chain) rather than
      // spying on element.refresh — LWC's proxy refuses external
      // method overrides even for @api members.
      refreshApex.mockClear();

      element.shadowRoot.querySelector('[data-test="view-all-button"]').click();
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(AddToDealTeamModal.open).toHaveBeenCalledTimes(1);
      const args = AddToDealTeamModal.open.mock.calls[0][0];
      expect(args.contactId).toBe(SARAH.contactId);
      expect(args.contactName).toBe(SARAH.name);
      expect(refreshApex).toHaveBeenCalledTimes(1);
    });

    it("viewAllChainSuccessRaceOpensAlreadyAdded", async () => {
      EngagementDetailModal.open.mockResolvedValue({
        result: "add-to-team",
        payload: {
          contactId: SARAH.contactId,
          contactName: SARAH.name
        }
      });
      AddToDealTeamModal.open.mockResolvedValue({
        result: "success",
        payload: {
          success: false,
          alreadyExists: true,
          ocrId: "00KX",
          addedByUserName: "Race User",
          addedAt: "2026-05-11T12:00:00.000Z"
        }
      });
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      element.shadowRoot.querySelector('[data-test="view-all-button"]').click();
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(AlreadyAddedModal.open).toHaveBeenCalledTimes(1);
      expect(AlreadyAddedModal.open.mock.calls[0][0].contactName).toBe(
        SARAH.name
      );
    });
  });

  describe("dismiss flow", () => {
    it("dismissOpportunityScopeCallsApexAndRefreshes", async () => {
      dismissContact.mockResolvedValue(undefined);
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();
      // We assert on refreshApex (the underlying chain) rather than
      // spying on element.refresh — LWC's proxy refuses external
      // method overrides even for @api members.
      refreshApex.mockClear();
      const onToast = jest.fn();
      element.addEventListener("lightning__showtoast", onToast);

      const dismissBtn = element.shadowRoot.querySelector(
        `[data-test="dismiss-button"][data-contact-id="${SARAH.contactId}"]`
      );
      dismissBtn.click();
      await flushPromises();
      await flushPromises();

      expect(dismissContact).toHaveBeenCalledWith({
        contactId: SARAH.contactId,
        opportunityId: RECORD_ID_OPP,
        accountId: null
      });
      expect(refreshApex).toHaveBeenCalledTimes(1);
      expect(onToast.mock.calls[0][0].detail.variant).toBe("success");
    });

    it("dismissAccountScopePassesAccountId", async () => {
      dismissContact.mockResolvedValue(undefined);
      const element = buildPanel({ recordContext: "Account" });
      getForAccount.emit([SARAH]);
      await flushPromises();
      jest.spyOn(element, "refresh").mockResolvedValue();

      element.shadowRoot
        .querySelector(
          `[data-test="dismiss-button"][data-contact-id="${SARAH.contactId}"]`
        )
        .click();
      await flushPromises();
      await flushPromises();

      expect(dismissContact).toHaveBeenCalledWith({
        contactId: SARAH.contactId,
        opportunityId: null,
        accountId: RECORD_ID_ACCOUNT
      });
    });

    it("dismissErrorFiresErrorToast", async () => {
      dismissContact.mockRejectedValue({
        body: { message: "Permission denied" }
      });
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();
      // We assert on refreshApex (the underlying chain) rather than
      // spying on element.refresh — LWC's proxy refuses external
      // method overrides even for @api members.
      refreshApex.mockClear();
      const onToast = jest.fn();
      element.addEventListener("lightning__showtoast", onToast);

      element.shadowRoot
        .querySelector(
          `[data-test="dismiss-button"][data-contact-id="${SARAH.contactId}"]`
        )
        .click();
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(refreshApex).not.toHaveBeenCalled();
      const detail = onToast.mock.calls[0][0].detail;
      expect(detail.variant).toBe("error");
      expect(detail.message).toBe("Permission denied");
    });

    it("dismissErrorFallbackMessage", async () => {
      dismissContact.mockRejectedValue(new Error("naked"));
      const element = buildPanel();
      getForOpportunity.emit([SARAH]);
      await flushPromises();
      const onToast = jest.fn();
      element.addEventListener("lightning__showtoast", onToast);

      element.shadowRoot
        .querySelector(
          `[data-test="dismiss-button"][data-contact-id="${SARAH.contactId}"]`
        )
        .click();
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(onToast.mock.calls[0][0].detail.message).toBe(
        "Unable to dismiss. Try again."
      );
    });
  });

  describe("refresh @api", () => {
    it("triggersRefreshApexAndDispatchesEvent", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH]);
      await flushPromises();

      const onRefresh = jest.fn();
      element.addEventListener("refresh", onRefresh);

      await element.refresh();
      expect(refreshApex).toHaveBeenCalledTimes(1);
      expect(onRefresh).toHaveBeenCalledTimes(1);
    });
  });

  describe("permission gating — Power User tier", () => {
    // Mocked-default state for this file is View=true, PowerUser=true, so
    // this suite asserts the affirmative case explicitly. View-tier and
    // no-perm cases live in sibling files (engagementPanel.perm-*.test.js)
    // because flipping `@salesforce/customPermission/<name>` requires a
    // separate module realm — `jest.isolateModules` collides with LWC's
    // process-global custom-element registry.
    it("powerUserSeesActions", async () => {
      const element = buildPanel();
      getForOpportunity.emit([SARAH, MIKE]);
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="view-all-button"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelectorAll('[data-test="add-button"]').length
      ).toBe(1);
      // Two dismiss buttons: one on the deal-team row, one on the not-on-team row.
      expect(
        element.shadowRoot.querySelectorAll('[data-test="dismiss-button"]')
          .length
      ).toBe(2);
    });
  });
});
