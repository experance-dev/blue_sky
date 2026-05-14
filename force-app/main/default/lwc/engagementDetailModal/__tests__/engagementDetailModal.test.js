/**
 * Jest spec for c-engagement-detail-modal. Per TEST_DESIGN.md.
 *
 * Uses GLOBAL lightning/modal stub — close calls observed via
 * `lwc__modal_close` CustomEvent.
 */
import { createElement } from "lwc";
import EngagementDetailModal from "c/engagementDetailModal";
import dismissContact from "@salesforce/apex/EngagementController.dismissContact";

jest.mock(
  "@salesforce/apex/EngagementController.dismissContact",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// Freeze time so timeline-position math is deterministic.
const NOW_ISO = "2026-05-12T12:00:00.000Z";
const NOW_MS = new Date(NOW_ISO).getTime();
const DAY = 24 * 60 * 60 * 1000;

beforeAll(() => {
  jest.useFakeTimers().setSystemTime(new Date(NOW_ISO));
});

afterAll(() => {
  jest.useRealTimers();
});

const SARAH = {
  contactId: "003000000000001",
  name: "Sarah Johnson",
  title: "CFO",
  accountName: "United Healthcare",
  onOcr: false,
  isAcr: false,
  isConsultant: false,
  persona: "Finance",
  topics: ["Network Management", "Payment Integrity"],
  touchCount: 4,
  lastTouchAt: new Date(NOW_MS - 2 * DAY).toISOString(),
  assets: [
    {
      assetName: "Zelis Pricing Whitepaper",
      touchType: "Download",
      count: 3,
      firstAt: new Date(NOW_MS - 6 * DAY).toISOString(),
      lastAt: new Date(NOW_MS - 2 * DAY).toISOString(),
      campaignName: "Q2 Zelis Pricing Promo"
    },
    {
      assetName: "/pricing/calculator",
      touchType: "Page View",
      count: 1,
      firstAt: new Date(NOW_MS - 2 * DAY).toISOString(),
      lastAt: new Date(NOW_MS - 2 * DAY).toISOString(),
      campaignName: null
    }
  ]
};

const JANE = {
  contactId: "003000000000002",
  name: "Jane Smith",
  title: "CRO",
  accountName: "United Healthcare",
  onOcr: true,
  ocrRole: "Decision Maker",
  isAcr: true,
  isConsultant: false,
  persona: "Executive",
  topics: ["Network Management"],
  touchCount: 3,
  lastTouchAt: new Date(NOW_MS - 4 * DAY).toISOString(),
  assets: [
    {
      assetName: "Zelis Pricing Whitepaper",
      touchType: "Download",
      count: 2,
      firstAt: new Date(NOW_MS - 11 * DAY).toISOString(),
      lastAt: new Date(NOW_MS - 4 * DAY).toISOString(),
      campaignName: "Q2 Zelis Pricing Promo"
    }
  ]
};

const MARCUS = {
  contactId: "003000000000003",
  name: "Marcus Webb",
  title: "Implementation Consultant",
  accountName: "Deloitte",
  onOcr: false,
  isAcr: true,
  isConsultant: true,
  persona: "Technical",
  topics: [],
  touchCount: 2,
  lastTouchAt: new Date(NOW_MS - 3 * DAY).toISOString(),
  assets: [
    {
      assetName: "Network Pricing Playbook",
      touchType: "Download",
      count: 1,
      firstAt: new Date(NOW_MS - 3 * DAY).toISOString(),
      lastAt: new Date(NOW_MS - 3 * DAY).toISOString(),
      campaignName: "Implementation Toolkit"
    }
  ]
};

const FIXTURE = [SARAH, JANE, MARCUS];

function createModal(props = {}) {
  const element = createElement("c-engagement-detail-modal", {
    is: EngagementDetailModal
  });
  element.engagements = props.engagements ?? FIXTURE;
  element.recordContext = props.recordContext ?? "Opportunity";
  element.recordName = props.recordName ?? "Network Pricing Implementation";
  element.opportunityId = Object.prototype.hasOwnProperty.call(
    props,
    "opportunityId"
  )
    ? props.opportunityId
    : "006000000000001";
  element.accountId = Object.prototype.hasOwnProperty.call(props, "accountId")
    ? props.accountId
    : null;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

function listenForClose(element) {
  const listener = jest.fn();
  element.addEventListener("lwc__modal_close", listener);
  return listener;
}

function listenForToast(element) {
  const listener = jest.fn();
  element.addEventListener("lightning__showtoast", listener);
  return listener;
}

describe("c-engagement-detail-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  describe("stats strip", () => {
    it("rendersTotalEngagedCount", async () => {
      const element = createModal();
      await flush();
      expect(
        element.shadowRoot
          .querySelector('[data-test="stat-total-engaged"]')
          .textContent.trim()
      ).toBe("3");
    });

    it("rendersTotalTouchesSum", async () => {
      const element = createModal();
      await flush();
      // 4 + 3 + 2 = 9
      expect(
        element.shadowRoot
          .querySelector('[data-test="stat-total-touches"]')
          .textContent.trim()
      ).toBe("9");
    });

    it("rendersNotOnDealTeamCount", async () => {
      const element = createModal();
      await flush();
      // Sarah + Marcus = 2 (Jane is on OCR)
      expect(
        element.shadowRoot
          .querySelector('[data-test="stat-not-on-deal-team"]')
          .textContent.trim()
      ).toBe("2");
    });

    it("rendersTopTopicByTouchWeight", async () => {
      const element = createModal();
      await flush();
      // Network Management gets (4 from Sarah + 3 from Jane) = 7;
      // Payment Integrity gets 4 from Sarah only.
      const top = element.shadowRoot.querySelector(
        '[data-test="stat-top-topic"]'
      );
      expect(top.textContent.trim()).toBe("Network Management");
    });

    it("topTopicTruncatedAt20Chars", async () => {
      const longTopic = "ThisTopicNameIsWayLongerThan20Characters";
      const dto = {
        ...SARAH,
        topics: [longTopic],
        touchCount: 5
      };
      const element = createModal({ engagements: [dto] });
      await flush();
      const top = element.shadowRoot.querySelector(
        '[data-test="stat-top-topic"]'
      );
      expect(top.textContent.trim()).toMatch(/…$/);
      expect(top.textContent.trim().length).toBeLessThanOrEqual(21);
    });

    it("topTopicEmDashWhenNoTopics", async () => {
      const dto = { ...SARAH, topics: [] };
      const element = createModal({ engagements: [dto] });
      await flush();
      const top = element.shadowRoot.querySelector(
        '[data-test="stat-top-topic"]'
      );
      expect(top.textContent.trim()).toBe("—");
    });
  });

  describe("person rows", () => {
    it("rendersOneRowPerEngagement", async () => {
      const element = createModal();
      await flush();
      expect(
        element.shadowRoot.querySelectorAll(".engagement-row").length
      ).toBe(FIXTURE.length);
    });

    it("personRowsRenderInProvidedOrder", async () => {
      const element = createModal();
      await flush();
      const labels = Array.from(
        element.shadowRoot.querySelectorAll(".engagement-row strong")
      ).map((s) => s.textContent.trim());
      expect(labels).toEqual(["Sarah Johnson", "Jane Smith", "Marcus Webb"]);
    });

    it("personRowTouchBadgeReflectsDto", async () => {
      const element = createModal();
      await flush();
      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      const counts = Array.from(rows).map((r) => {
        const badges = r.querySelectorAll(".slds-badge");
        return badges[badges.length - 1].textContent.trim();
      });
      expect(counts).toEqual(["4 touches", "3 touches", "2 touches"]);
    });

    it("ocrMemberShowsOnTeamBadge", async () => {
      const element = createModal();
      await flush();
      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      const janeBadges = Array.from(
        rows[1].querySelectorAll(".slds-badge")
      ).map((b) => b.textContent.trim());
      expect(janeBadges).toContain("✓ on team");
    });

    it("consultantBadge", async () => {
      const element = createModal();
      await flush();
      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      const marcusBadges = Array.from(
        rows[2].querySelectorAll(".slds-badge")
      ).map((b) => b.textContent.trim());
      expect(marcusBadges).toContain("Consultant");
    });

    it("acrBadgeWhenAcrButNotConsultant", async () => {
      const acrOnly = {
        ...SARAH,
        isAcr: true,
        isConsultant: false
      };
      const element = createModal({ engagements: [acrOnly] });
      await flush();
      const badges = Array.from(
        element.shadowRoot.querySelectorAll(".slds-badge")
      ).map((b) => b.textContent.trim());
      expect(badges).toContain("ACR");
    });

    it("personRowHotlinkAndTooltip", async () => {
      const element = createModal();
      await flush();
      const firstRow = element.shadowRoot.querySelector(".engagement-row");
      const anchor = firstRow.querySelector("a.contact-link");
      expect(anchor.getAttribute("href")).toBe(
        "/lightning/r/Contact/003000000000001/view"
      );
      expect(anchor.getAttribute("target")).toBe("_top");
      const tooltip = anchor.getAttribute("title");
      expect(tooltip).toContain("4 touches");
      expect(tooltip).toContain("Not on Deal Team");
    });
  });

  describe("add-to-team", () => {
    it("addButtonAbsentForOcrMembers", async () => {
      const element = createModal();
      await flush();
      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      expect(rows[1].querySelector(".add-to-team-btn")).toBeNull();
      expect(rows[0].querySelector(".add-to-team-btn")).not.toBeNull();
      expect(rows[2].querySelector(".add-to-team-btn")).not.toBeNull();
    });

    it("addToTeamClickClosesWithCorrectPayload", async () => {
      const element = createModal();
      const onClose = listenForClose(element);
      await flush();
      const addBtn = element.shadowRoot.querySelector(".add-to-team-btn");
      addBtn.click();
      await flush();

      expect(onClose).toHaveBeenCalledTimes(1);
      expect(onClose.mock.calls[0][0].detail).toEqual({
        result: "add-to-team",
        payload: {
          contactId: SARAH.contactId,
          contactName: SARAH.name
        }
      });
    });
  });

  describe("group-by switch", () => {
    it("switchToCampaignGroupingChangesRowSet", async () => {
      const element = createModal();
      await flush();

      const radio = element.shadowRoot.querySelector("lightning-radio-group");
      radio.dispatchEvent(
        new CustomEvent("change", { detail: { value: "campaign" } })
      );
      await flush();

      const labels = Array.from(
        element.shadowRoot.querySelectorAll(".engagement-row strong")
      ).map((s) => s.textContent.trim());
      // Q2 Zelis Pricing Promo (Sarah+Jane), '(No campaign)' (Sarah page view),
      // Implementation Toolkit (Marcus).
      expect(labels.sort()).toEqual(
        [
          "(No campaign)",
          "Implementation Toolkit",
          "Q2 Zelis Pricing Promo"
        ].sort()
      );
      // Add buttons must NOT render in campaign mode.
      expect(
        element.shadowRoot.querySelectorAll(".add-to-team-btn").length
      ).toBe(0);
      // Dismiss buttons must NOT render in campaign mode.
      expect(
        element.shadowRoot.querySelectorAll(".dismiss-row-btn").length
      ).toBe(0);
    });

    it("switchClearsExpansionAndFocus", async () => {
      const element = createModal();
      await flush();
      // Expand Sarah.
      element.shadowRoot.querySelectorAll(".engagement-row")[0].click();
      await flush();
      expect(
        element.shadowRoot.querySelector(".engagement-row__detail")
      ).not.toBeNull();

      const radio = element.shadowRoot.querySelector("lightning-radio-group");
      radio.dispatchEvent(
        new CustomEvent("change", { detail: { value: "campaign" } })
      );
      await flush();

      expect(
        element.shadowRoot.querySelector(".engagement-row__detail")
      ).toBeNull();
    });

    it("campaignBucketAggregatesCountAcrossPeople", async () => {
      const element = createModal();
      await flush();
      const radio = element.shadowRoot.querySelector("lightning-radio-group");
      radio.dispatchEvent(
        new CustomEvent("change", { detail: { value: "campaign" } })
      );
      await flush();

      // Q2 Zelis Pricing Promo bucket: Sarah's whitepaper (3) + Jane's
      // whitepaper (2) = 5 total touches in the bucket-count badge.
      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      const promoRow = Array.from(rows).find((r) =>
        r.textContent.includes("Q2 Zelis Pricing Promo")
      );
      const badges = promoRow.querySelectorAll(".slds-badge");
      // The count-touches badge is the last one in the row.
      expect(badges[badges.length - 1].textContent.trim()).toBe("5 touches");
    });
  });

  describe("expansion", () => {
    it("clickingRowExpandsThenCollapses", async () => {
      const element = createModal();
      await flush();

      const firstRow = element.shadowRoot.querySelector(".engagement-row");
      firstRow.click();
      await flush();
      let detail = element.shadowRoot.querySelector(".engagement-row__detail");
      expect(detail).not.toBeNull();
      expect(detail.querySelectorAll(".asset-row").length).toBe(2);

      firstRow.click();
      await flush();
      detail = element.shadowRoot.querySelector(".engagement-row__detail");
      expect(detail).toBeNull();
    });

    it("keyboardEnterTogglesRow", async () => {
      const element = createModal();
      await flush();
      const firstRow = element.shadowRoot.querySelector(".engagement-row");
      const ev = new KeyboardEvent("keydown", {
        key: "Enter",
        bubbles: true,
        cancelable: true
      });
      firstRow.dispatchEvent(ev);
      await flush();
      expect(
        element.shadowRoot.querySelector(".engagement-row__detail")
      ).not.toBeNull();
    });

    it("keyboardSpaceTogglesRow", async () => {
      const element = createModal();
      await flush();
      const firstRow = element.shadowRoot.querySelector(".engagement-row");
      firstRow.dispatchEvent(
        new KeyboardEvent("keydown", {
          key: " ",
          bubbles: true,
          cancelable: true
        })
      );
      await flush();
      expect(
        element.shadowRoot.querySelector(".engagement-row__detail")
      ).not.toBeNull();
    });
  });

  describe("timeline focus", () => {
    it("clickingPersonRowFocusesTimeline", async () => {
      const element = createModal();
      await flush();
      const before = element.shadowRoot.querySelectorAll(
        '[data-test="timeline-dot"]'
      ).length;
      expect(before).toBeGreaterThanOrEqual(3);

      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      rows[1].click(); // Jane
      await flush();

      const after = element.shadowRoot.querySelectorAll(
        '[data-test="timeline-dot"]'
      );
      expect(after.length).toBe(1);
      expect(after[0].getAttribute("title")).toContain("Jane Smith");
    });

    it("collapsingFocusedRowRestoresDots", async () => {
      const element = createModal();
      await flush();
      const baseline = element.shadowRoot.querySelectorAll(
        '[data-test="timeline-dot"]'
      ).length;

      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      rows[1].click();
      await flush();
      rows[1].click();
      await flush();

      expect(
        element.shadowRoot.querySelectorAll('[data-test="timeline-dot"]').length
      ).toBe(baseline);
    });

    it("focusedContactTitleUpdates", async () => {
      const element = createModal();
      await flush();
      const rows = element.shadowRoot.querySelectorAll(".engagement-row");
      rows[1].click();
      await flush();
      const title = element.shadowRoot.querySelector(".timeline-title");
      expect(title.textContent).toContain("Jane Smith");
    });

    it("timelineSkipsAssetsWithoutLastAt", async () => {
      const dto = {
        ...SARAH,
        assets: [
          {
            assetName: "Without lastAt",
            touchType: "Download",
            count: 1,
            firstAt: new Date(NOW_MS - DAY).toISOString(),
            lastAt: null,
            campaignName: null
          },
          {
            assetName: "With lastAt",
            touchType: "Download",
            count: 1,
            firstAt: new Date(NOW_MS - DAY).toISOString(),
            lastAt: new Date(NOW_MS - DAY).toISOString(),
            campaignName: null
          }
        ]
      };
      const element = createModal({ engagements: [dto] });
      await flush();
      const dots = element.shadowRoot.querySelectorAll(
        '[data-test="timeline-dot"]'
      );
      expect(dots.length).toBe(1);
    });

    it("timelineCapsAt100DotsKeepingMostRecent", async () => {
      const manyAssets = [];
      for (let i = 0; i < 150; i++) {
        manyAssets.push({
          assetName: `Asset ${i}`,
          touchType: "Download",
          count: 1,
          firstAt: new Date(NOW_MS - (i + 1) * DAY).toISOString(),
          lastAt: new Date(NOW_MS - (i + 1) * DAY).toISOString(),
          campaignName: null
        });
      }
      const dto = { ...SARAH, assets: manyAssets };
      const element = createModal({ engagements: [dto] });
      await flush();
      const dots = element.shadowRoot.querySelectorAll(
        '[data-test="timeline-dot"]'
      );
      expect(dots.length).toBe(100);
      // Most recent (day-1) should be present; oldest (day-150) should not.
      const tooltips = Array.from(dots).map((d) => d.getAttribute("title"));
      expect(tooltips).toContain("Sarah Johnson · Asset 0 · Finance");
      // Asset 149 (oldest) should be dropped because we kept only 100 most-recent.
      expect(tooltips).not.toContain("Sarah Johnson · Asset 149 · Finance");
    });

    it("timelineDotTodayPositionIsZeroPercent", async () => {
      const dto = {
        ...SARAH,
        assets: [
          {
            assetName: "Just now",
            touchType: "Download",
            count: 1,
            firstAt: NOW_ISO,
            lastAt: NOW_ISO,
            campaignName: null
          }
        ]
      };
      const element = createModal({ engagements: [dto] });
      await flush();
      const dot = element.shadowRoot.querySelector(
        '[data-test="timeline-dot"]'
      );
      expect(dot.style.top).toBe("0.00%");
    });

    it("timelineDotOlderThanOneYearClampsTo100Percent", async () => {
      const dto = {
        ...SARAH,
        assets: [
          {
            assetName: "Way old",
            touchType: "Download",
            count: 1,
            firstAt: new Date(NOW_MS - 400 * DAY).toISOString(),
            lastAt: new Date(NOW_MS - 400 * DAY).toISOString(),
            campaignName: null
          }
        ]
      };
      const element = createModal({ engagements: [dto] });
      await flush();
      const dot = element.shadowRoot.querySelector(
        '[data-test="timeline-dot"]'
      );
      expect(dot.style.top).toBe("100.00%");
    });
  });

  describe("dismiss row", () => {
    it("optimisticallyRemovesRowAndCallsApex_OpportunityScope", async () => {
      dismissContact.mockResolvedValue(undefined);
      const element = createModal();
      const onToast = listenForToast(element);
      await flush();

      const dismissBtn = element.shadowRoot.querySelector(
        '.dismiss-row-btn[data-contact-id="003000000000001"]'
      );
      dismissBtn.click();
      await flush();
      await flush();

      expect(dismissContact).toHaveBeenCalledWith({
        contactId: "003000000000001",
        opportunityId: "006000000000001",
        accountId: null
      });
      expect(
        element.shadowRoot.querySelectorAll(".engagement-row").length
      ).toBe(2);
      const toastDetail = onToast.mock.calls[0][0].detail;
      expect(toastDetail.title).toBe("Dismissed");
      expect(toastDetail.variant).toBe("success");
    });

    it("dismissAccountScopePassesAccountId", async () => {
      dismissContact.mockResolvedValue(undefined);
      const element = createModal({
        recordContext: "Account",
        opportunityId: null,
        accountId: "001000000000999"
      });
      await flush();

      element.shadowRoot
        .querySelector('.dismiss-row-btn[data-contact-id="003000000000001"]')
        .click();
      await flush();
      await flush();

      expect(dismissContact).toHaveBeenCalledWith({
        contactId: "003000000000001",
        opportunityId: null,
        accountId: "001000000000999"
      });
    });

    it("dismissErrorKeepsRowAndFiresErrorToast", async () => {
      dismissContact.mockRejectedValue({
        body: { message: "Locked out" }
      });
      const element = createModal();
      const onToast = listenForToast(element);
      await flush();

      element.shadowRoot
        .querySelector('.dismiss-row-btn[data-contact-id="003000000000001"]')
        .click();
      await flush();
      await flush();
      await flush();

      expect(
        element.shadowRoot.querySelectorAll(".engagement-row").length
      ).toBe(3);
      expect(onToast.mock.calls[0][0].detail.variant).toBe("error");
      expect(onToast.mock.calls[0][0].detail.message).toBe("Locked out");
    });

    it("dismissErrorFallbackMessage", async () => {
      dismissContact.mockRejectedValue(new Error("naked"));
      const element = createModal();
      const onToast = listenForToast(element);
      await flush();

      element.shadowRoot
        .querySelector('.dismiss-row-btn[data-contact-id="003000000000001"]')
        .click();
      await flush();
      await flush();
      await flush();

      expect(onToast.mock.calls[0][0].detail.message).toBe(
        "Unable to dismiss. Try again."
      );
    });
  });

  describe("close button", () => {
    it("closesWithClosedResult", async () => {
      const element = createModal();
      const onClose = listenForClose(element);
      await flush();

      const buttons = element.shadowRoot.querySelectorAll("lightning-button");
      const closeBtn = Array.from(buttons).find((b) => b.label === "Close");
      closeBtn.click();
      await flush();

      expect(onClose).toHaveBeenCalledTimes(1);
      expect(onClose.mock.calls[0][0].detail).toEqual({
        result: "closed"
      });
    });
  });

  describe("record hotlink", () => {
    it("rendersOpportunityRecordLinkWhenOpportunityIdPresent", async () => {
      const element = createModal();
      await flush();
      const link = element.shadowRoot.querySelector(
        '[data-test="record-link"]'
      );
      expect(link).not.toBeNull();
      expect(link.getAttribute("href")).toBe(
        "/lightning/r/Opportunity/006000000000001/view"
      );
    });

    it("rendersAccountRecordLinkWhenAccountIdPresent", async () => {
      const element = createModal({
        opportunityId: null,
        accountId: "001ABCDEF"
      });
      await flush();
      const link = element.shadowRoot.querySelector(
        '[data-test="record-link"]'
      );
      expect(link.getAttribute("href")).toBe(
        "/lightning/r/Account/001ABCDEF/view"
      );
    });

    it("rendersNoRecordLinkWhenBothIdsAbsent", async () => {
      const element = createModal({
        opportunityId: null,
        accountId: null
      });
      await flush();
      expect(
        element.shadowRoot.querySelector('[data-test="record-link"]')
      ).toBeNull();
    });
  });

  describe("empty / edge", () => {
    it("rendersGracefullyOnEmptyEngagements", async () => {
      const element = createModal({ engagements: [] });
      await flush();
      expect(
        element.shadowRoot.querySelectorAll(".engagement-row").length
      ).toBe(0);
      expect(
        element.shadowRoot
          .querySelector('[data-test="stat-total-engaged"]')
          .textContent.trim()
      ).toBe("0");
      expect(
        element.shadowRoot
          .querySelector('[data-test="stat-top-topic"]')
          .textContent.trim()
      ).toBe("—");
    });
  });
});
