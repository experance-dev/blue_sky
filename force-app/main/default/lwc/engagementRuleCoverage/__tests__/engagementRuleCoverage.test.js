/**
 * Jest spec for c-engagement-rule-coverage. Per TEST_DESIGN.md.
 *
 * Read-only admin component: one wire (getRuleCoverage), datatable render,
 * dead-rule banner + per-row rowClass highlighting. No row actions.
 */
import { createElement } from "lwc";
import EngagementRuleCoverage from "c/engagementRuleCoverage";
import getRuleCoverage from "@salesforce/apex/EngagementAdminController.getRuleCoverage";

jest.mock(
  "@salesforce/apex/EngagementAdminController.getRuleCoverage",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const RULE_LIVE_A = {
  ruleDeveloperName: "OCR_Exact_Match",
  ruleLabel: "OCR — Exact contact match",
  priority: 10,
  matchPath: "OCR",
  targetConfidence: 95,
  signalsLast30Days: 12,
  isActive: true
};

const RULE_LIVE_B = {
  ruleDeveloperName: "Account_Topic_Default",
  ruleLabel: "Account — Same account + topic",
  priority: 50,
  matchPath: "Account",
  targetConfidence: 55,
  signalsLast30Days: 4,
  isActive: true
};

const RULE_DEAD_A = {
  ruleDeveloperName: "Account_Match_High_Intent",
  ruleLabel: "Account — High intent only",
  priority: 30,
  matchPath: "Account",
  targetConfidence: 70,
  signalsLast30Days: 0,
  isActive: true
};

const RULE_DEAD_B = {
  ruleDeveloperName: "OCR_Stale_Path",
  ruleLabel: "OCR — Stale match path",
  priority: 90,
  matchPath: "OCR",
  targetConfidence: 90,
  signalsLast30Days: 0,
  isActive: true
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function build() {
  const element = createElement("c-engagement-rule-coverage", {
    is: EngagementRuleCoverage
  });
  document.body.appendChild(element);
  return element;
}

describe("c-engagement-rule-coverage", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  describe("wire states", () => {
    it("rendersSpinnerOnLoading", () => {
      const element = build();
      const spinner = element.shadowRoot.querySelector("lightning-spinner");
      expect(spinner).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="rules-table"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="error"]')
      ).toBeNull();
    });

    it("rendersDefaultServerErrorWhenWireErrorsWithoutBody", async () => {
      const element = build();
      getRuleCoverage.error();
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="error"]');
      expect(err).not.toBeNull();
      // wire-service-jest-util fabricates `{message:'An internal server
      // error has occurred'}` when error() is called with no body.
      expect(err.textContent).toMatch(/An internal server error has occurred/);
    });

    it("rendersCustomErrorMessageFromApexBody", async () => {
      const element = build();
      // `error(body, ...)` — first arg is the body. Production code
      // reads `e.body.message`.
      getRuleCoverage.error({ message: "Selector blew up" });
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="error"]');
      expect(err.textContent).toMatch(/Selector blew up/);
    });

    it("usesFallbackWhenErrorBodyHasNoMessage", async () => {
      const element = build();
      // Empty body with no message → component's fallback string.
      getRuleCoverage.error({});
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="error"]');
      expect(err.textContent).toMatch(/Unable to load rule coverage/);
    });

    it("rendersEmptyStateWhenWireReturnsEmptyArray", async () => {
      const element = build();
      getRuleCoverage.emit([]);
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="empty"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="rules-table"]')
      ).toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="dead-rule-banner"]')
      ).toBeNull();
    });
  });

  describe("populated render", () => {
    it("rendersDatatableWithAllRows", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_A, RULE_LIVE_B]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="rules-table"]'
      );
      expect(table).not.toBeNull();
      expect(table.data.length).toBe(2);
    });

    it("rowsHaveKeyFromRuleDeveloperName", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_A, RULE_LIVE_B]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="rules-table"]'
      );
      expect(table.data[0].key).toBe("OCR_Exact_Match");
      expect(table.data[1].key).toBe("Account_Topic_Default");
    });

    it("rowsPreserveInputOrder", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_B, RULE_LIVE_A]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="rules-table"]'
      );
      expect(table.data[0].ruleDeveloperName).toBe("Account_Topic_Default");
      expect(table.data[1].ruleDeveloperName).toBe("OCR_Exact_Match");
    });
  });

  describe("dead-rule highlighting", () => {
    it("hidesBannerWhenAllRulesHaveSignals", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_A, RULE_LIVE_B]);
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="dead-rule-banner"]')
      ).toBeNull();
    });

    it("showsBannerWhenAnyRuleAtZeroSignals", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_A, RULE_DEAD_A]);
      await flushPromises();

      const banner = element.shadowRoot.querySelector(
        '[data-test="dead-rule-banner"]'
      );
      expect(banner).not.toBeNull();
      expect(banner.textContent).toMatch(/zero signals/);
    });

    it("bannerCountSingularForOneDeadRule", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_A, RULE_DEAD_A]);
      await flushPromises();

      const banner = element.shadowRoot.querySelector(
        '[data-test="dead-rule-banner"]'
      );
      expect(banner.textContent).toMatch(/1 rule\s/);
      expect(banner.textContent).not.toMatch(/1 rules/);
    });

    it("bannerCountPluralForMultipleDeadRules", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_DEAD_A, RULE_DEAD_B, RULE_LIVE_A]);
      await flushPromises();

      const banner = element.shadowRoot.querySelector(
        '[data-test="dead-rule-banner"]'
      );
      expect(banner.textContent).toMatch(/2 rules/);
    });

    it("deadRuleRowClassMarksDeadRule", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_DEAD_A]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="rules-table"]'
      );
      expect(table.data[0].rowClass).toMatch(/dead-rule/);
      expect(table.data[0].rowClass).toMatch(/slds-text-color_error/);
      expect(table.data[0].rowClass).toMatch(/slds-text-title_bold/);
    });

    it("liveRuleRowClassIsDefault", async () => {
      const element = build();
      getRuleCoverage.emit([RULE_LIVE_A]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="rules-table"]'
      );
      expect(table.data[0].rowClass).toBe("slds-text-color_default");
    });

    it("mixedDeadAndLiveRulesFlagOnlyDeadOnes", async () => {
      const element = build();
      getRuleCoverage.emit([
        RULE_LIVE_A,
        RULE_DEAD_A,
        RULE_LIVE_B,
        RULE_DEAD_B
      ]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="rules-table"]'
      );
      expect(table.data.length).toBe(4);

      const banner = element.shadowRoot.querySelector(
        '[data-test="dead-rule-banner"]'
      );
      expect(banner.textContent).toMatch(/2 rules/);

      const deadRows = table.data.filter((r) =>
        r.rowClass.includes("dead-rule")
      );
      expect(deadRows.length).toBe(2);
      expect(deadRows.map((r) => r.ruleDeveloperName).sort()).toEqual([
        "Account_Match_High_Intent",
        "OCR_Stale_Path"
      ]);
    });
  });
});
