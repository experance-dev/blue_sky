/**
 * Jest spec for c-engagement-error-queue. Per TEST_DESIGN.md.
 */
import { createElement } from "lwc";
import EngagementErrorQueue from "c/engagementErrorQueue";
import getTouchesWithIssues from "@salesforce/apex/EngagementAdminController.getTouchesWithIssues";
import retryResolution from "@salesforce/apex/EngagementAdminController.retryResolution";
import ignoreTouch from "@salesforce/apex/EngagementAdminController.ignoreTouch";

jest.mock(
  "@salesforce/apex",
  () => ({
    refreshApex: jest.fn().mockResolvedValue(undefined)
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/EngagementAdminController.getTouchesWithIssues",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/EngagementAdminController.retryResolution",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/EngagementAdminController.ignoreTouch",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// Import refreshApex AFTER its mock declaration.
// eslint-disable-next-line import/order
import { refreshApex } from "@salesforce/apex";

const NO_MATCH_ROW = {
  touchId: "a0x000000000001",
  touchName: "ET-0001",
  email: "unknown@nowhere.example.com",
  assetName: "Network Pricing Whitepaper",
  resolutionStatus: "NoMatch",
  processingMessage: null,
  occurredAt: "2026-05-10T14:00:00.000Z",
  sourceSystem: "HubSpot"
};

const AMBIGUOUS_ROW = {
  touchId: "a0x000000000002",
  touchName: "ET-0002",
  email: "twin@uhc.example.com",
  assetName: "Payment Integrity Brief",
  resolutionStatus: "Ambiguous",
  processingMessage: null,
  occurredAt: "2026-05-09T10:00:00.000Z",
  sourceSystem: "HubSpot"
};

const RESOLVED_ROW = {
  touchId: "a0x000000000003",
  touchName: "ET-0003",
  email: "ok@uhc.example.com",
  assetName: "Topical Brief",
  resolutionStatus: "Resolved",
  processingMessage: null,
  occurredAt: "2026-05-08T10:00:00.000Z",
  sourceSystem: "HubSpot"
};

const SAMPLE = [NO_MATCH_ROW, AMBIGUOUS_ROW];

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function build() {
  const element = createElement("c-engagement-error-queue", {
    is: EngagementErrorQueue
  });
  document.body.appendChild(element);
  return element;
}

function listenForToast(element) {
  const listener = jest.fn();
  element.addEventListener("lightning__showtoast", listener);
  return listener;
}

function fireRowAction(table, actionName, row) {
  table.dispatchEvent(
    new CustomEvent("rowaction", {
      detail: { action: { name: actionName }, row }
    })
  );
}

describe("c-engagement-error-queue", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  describe("wire states", () => {
    it("rendersSpinnerOnLoading", () => {
      const element = build();
      expect(
        element.shadowRoot.querySelector("lightning-spinner")
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="touches-table"]')
      ).toBeNull();
    });

    it("rendersErrorOnWireError_withDefaultServerMessage", async () => {
      const element = build();
      getTouchesWithIssues.error();
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="error"]');
      expect(err).not.toBeNull();
      expect(err.textContent).toMatch(/internal server/);
    });

    it("rendersCustomErrorMessageFromApex", async () => {
      const element = build();
      getTouchesWithIssues.error({ message: "Selector blew up" });
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="error"]');
      expect(err.textContent).toMatch(/Selector blew up/);
    });

    it("usesFallbackWhenErrorBodyHasNoMessage", async () => {
      const element = build();
      getTouchesWithIssues.error({});
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="error"]');
      expect(err.textContent).toMatch(/Unable to load touches/);
    });

    it("rendersEmptyStateWhenNoTouches", async () => {
      const element = build();
      getTouchesWithIssues.emit([]);
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="empty"]')
      ).not.toBeNull();
      const count = element.shadowRoot.querySelector(
        '[data-test="count-label"]'
      );
      expect(count.textContent).toMatch(/0 touches pending review/);
    });

    it("rendersDatatableWhenPopulated", async () => {
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      expect(table).not.toBeNull();
      expect(table.data.length).toBe(2);
      const count = element.shadowRoot.querySelector(
        '[data-test="count-label"]'
      );
      expect(count.textContent).toMatch(/2 touches pending review/);
    });

    it("countLabelSingularForOneRow", async () => {
      const element = build();
      getTouchesWithIssues.emit([NO_MATCH_ROW]);
      await flushPromises();

      const count = element.shadowRoot.querySelector(
        '[data-test="count-label"]'
      );
      expect(count.textContent).toMatch(/1 touch pending review/);
      expect(count.textContent).not.toMatch(/1 touches/);
    });
  });

  describe("row decoration", () => {
    it("eachRowGetsIdFromTouchId", async () => {
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      expect(table.data[0].id).toBe("a0x000000000001");
      expect(table.data[1].id).toBe("a0x000000000002");
    });

    it("statusClassNoMatchIsError", async () => {
      const element = build();
      getTouchesWithIssues.emit([NO_MATCH_ROW]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      expect(table.data[0].statusClass).toBe("slds-text-color_error");
    });

    it("statusClassAmbiguousIsWarning", async () => {
      const element = build();
      getTouchesWithIssues.emit([AMBIGUOUS_ROW]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      expect(table.data[0].statusClass).toBe("slds-text-color_warning");
    });

    it("statusClassUnknownIsDefault", async () => {
      const element = build();
      getTouchesWithIssues.emit([RESOLVED_ROW]);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      expect(table.data[0].statusClass).toBe("slds-text-color_default");
    });
  });

  describe("retry row action", () => {
    it("retryActionCallsApexWithTouchId", async () => {
      retryResolution.mockResolvedValue({
        resolutionStatus: "Resolved",
        touchId: NO_MATCH_ROW.touchId
      });
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", NO_MATCH_ROW);
      await flushPromises();
      await flushPromises();

      expect(retryResolution).toHaveBeenCalledTimes(1);
      expect(retryResolution).toHaveBeenCalledWith({
        touchId: NO_MATCH_ROW.touchId
      });
    });

    it("retrySuccessFiresSuccessToastForResolved", async () => {
      retryResolution.mockResolvedValue({
        resolutionStatus: "Resolved",
        touchId: NO_MATCH_ROW.touchId
      });
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", NO_MATCH_ROW);
      await flushPromises();
      await flushPromises();

      expect(onToast).toHaveBeenCalledTimes(1);
      const detail = onToast.mock.calls[0][0].detail;
      expect(detail.title).toBe("Retry complete");
      expect(detail.variant).toBe("success");
      expect(detail.message).toContain("ET-0001");
      expect(detail.message).toContain("Resolved");
    });

    it("retrySuccessFiresInfoToastForNonResolvedStatus", async () => {
      retryResolution.mockResolvedValue({
        resolutionStatus: "Ambiguous",
        touchId: NO_MATCH_ROW.touchId
      });
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", NO_MATCH_ROW);
      await flushPromises();
      await flushPromises();

      expect(onToast.mock.calls[0][0].detail.variant).toBe("info");
    });

    it("retryRefreshesWireOnSuccess", async () => {
      retryResolution.mockResolvedValue({
        resolutionStatus: "Resolved",
        touchId: NO_MATCH_ROW.touchId
      });
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", NO_MATCH_ROW);
      await flushPromises();
      await flushPromises();

      expect(refreshApex).toHaveBeenCalledTimes(1);
    });

    it("retryErrorPathFiresErrorToastWithBodyMessage", async () => {
      retryResolution.mockRejectedValue({
        body: { message: "Resolver offline" }
      });
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", NO_MATCH_ROW);
      await flushPromises();
      await flushPromises();
      await flushPromises();

      const detail = onToast.mock.calls[0][0].detail;
      expect(detail.title).toBe("Retry failed");
      expect(detail.variant).toBe("error");
      expect(detail.message).toBe("Resolver offline");
    });

    it("retryErrorPathUsesFallbackMessageWhenNoBody", async () => {
      retryResolution.mockRejectedValue(new Error("naked"));
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", NO_MATCH_ROW);
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(onToast.mock.calls[0][0].detail.message).toBe(
        "Unable to retry resolution."
      );
    });
  });

  describe("ignore row action", () => {
    it("ignoreActionCallsApexWithReason", async () => {
      ignoreTouch.mockResolvedValue(undefined);
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "ignore", AMBIGUOUS_ROW);
      await flushPromises();
      await flushPromises();

      expect(ignoreTouch).toHaveBeenCalledTimes(1);
      expect(ignoreTouch).toHaveBeenCalledWith({
        touchId: AMBIGUOUS_ROW.touchId,
        reason: "Admin marked as ignored"
      });
    });

    it("ignoreSuccessFiresSuccessToast", async () => {
      ignoreTouch.mockResolvedValue(undefined);
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "ignore", AMBIGUOUS_ROW);
      await flushPromises();
      await flushPromises();

      const detail = onToast.mock.calls[0][0].detail;
      expect(detail.title).toBe("Touch ignored");
      expect(detail.variant).toBe("success");
      expect(detail.message).toContain("ET-0002");
    });

    it("ignoreRefreshesWireOnSuccess", async () => {
      ignoreTouch.mockResolvedValue(undefined);
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "ignore", AMBIGUOUS_ROW);
      await flushPromises();
      await flushPromises();

      expect(refreshApex).toHaveBeenCalledTimes(1);
    });

    it("ignoreErrorPathFiresErrorToastWithBodyMessage", async () => {
      ignoreTouch.mockRejectedValue({
        body: { message: "Archive table locked" }
      });
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "ignore", AMBIGUOUS_ROW);
      await flushPromises();
      await flushPromises();
      await flushPromises();

      const detail = onToast.mock.calls[0][0].detail;
      expect(detail.title).toBe("Ignore failed");
      expect(detail.variant).toBe("error");
      expect(detail.message).toBe("Archive table locked");
    });

    it("ignoreErrorPathFallbackMessage", async () => {
      ignoreTouch.mockRejectedValue(new Error("naked"));
      const element = build();
      const onToast = listenForToast(element);
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "ignore", AMBIGUOUS_ROW);
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(onToast.mock.calls[0][0].detail.message).toBe(
        "Unable to ignore this touch."
      );
    });
  });

  describe("row action guards", () => {
    it("rowActionWithoutTouchIdIsNoOp", async () => {
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "retry", {});
      fireRowAction(table, "retry", null);
      await flushPromises();

      expect(retryResolution).not.toHaveBeenCalled();
      expect(ignoreTouch).not.toHaveBeenCalled();
    });

    it("rowActionWithUnknownNameIsNoOp", async () => {
      const element = build();
      getTouchesWithIssues.emit(SAMPLE);
      await flushPromises();

      const table = element.shadowRoot.querySelector(
        '[data-test="touches-table"]'
      );
      fireRowAction(table, "delete", NO_MATCH_ROW);
      await flushPromises();

      expect(retryResolution).not.toHaveBeenCalled();
      expect(ignoreTouch).not.toHaveBeenCalled();
    });
  });
});
