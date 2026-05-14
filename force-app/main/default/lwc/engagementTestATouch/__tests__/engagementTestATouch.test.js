/**
 * Jest spec for c-engagement-test-a-touch. Per TEST_DESIGN.md.
 *
 * Imperative-only component. No wires. The Apex import is the only
 * round-trip the form makes.
 */
import { createElement } from "lwc";
import EngagementTestATouch from "c/engagementTestATouch";
import testTouch from "@salesforce/apex/EngagementAdminController.testTouch";

jest.mock(
  "@salesforce/apex/EngagementAdminController.testTouch",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function build() {
  const element = createElement("c-engagement-test-a-touch", {
    is: EngagementTestATouch
  });
  document.body.appendChild(element);
  return element;
}

function setField(element, fieldKey, value) {
  const input = element.shadowRoot.querySelector(`[data-test="${fieldKey}"]`);
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
}

function listenForToast(element) {
  const listener = jest.fn();
  element.addEventListener("lightning__showtoast", listener);
  return listener;
}

function resolvedFixture(overrides = {}) {
  return {
    touchId: "01x000000000001",
    resolutionStatus: "Resolved",
    contactId: "003000000000001",
    contactName: "Sarah Johnson",
    accountId: "001000000000001",
    accountName: "United Healthcare",
    signalsCreated: 2,
    signals: [
      {
        signalId: "0a1000000000001",
        opportunityId: "006000000000001",
        opportunityName: "Network Pricing Implementation",
        matchPath: "OCR",
        confidence: 95
      },
      {
        signalId: "0a1000000000002",
        opportunityId: "006000000000002",
        opportunityName: "Payment Integrity Renewal",
        matchPath: "Account",
        confidence: 55
      }
    ],
    messages: ["Routing produced 2 signals."],
    ...overrides
  };
}

describe("c-engagement-test-a-touch", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  describe("initial render", () => {
    it("rendersAllFormFields", async () => {
      const element = build();
      await flushPromises();
      [
        "input-email",
        "input-topic",
        "input-touchType",
        "input-persona",
        "input-intent",
        "input-asset",
        "submit-btn"
      ].forEach((key) => {
        expect(
          element.shadowRoot.querySelector(`[data-test="${key}"]`)
        ).not.toBeNull();
      });
    });

    it("submitButtonDisabledWhenEmailEmpty", async () => {
      const element = build();
      await flushPromises();
      const btn = element.shadowRoot.querySelector('[data-test="submit-btn"]');
      expect(btn.disabled).toBe(true);
    });

    it("submitButtonEnabledOnceEmailEntered", async () => {
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();
      const btn = element.shadowRoot.querySelector('[data-test="submit-btn"]');
      expect(btn.disabled).toBe(false);
    });

    it("touchTypeOptionsHaveFiveValues", async () => {
      const element = build();
      await flushPromises();
      const combo = element.shadowRoot.querySelector(
        '[data-test="input-touchType"]'
      );
      expect(combo.options.length).toBe(5);
      expect(combo.options.map((o) => o.value)).toEqual([
        "Download",
        "Form",
        "Webinar",
        "Page",
        "Event"
      ]);
    });

    it("personaOptionsHaveFiveValues", async () => {
      const element = build();
      await flushPromises();
      const combo = element.shadowRoot.querySelector(
        '[data-test="input-persona"]'
      );
      expect(combo.options.length).toBe(5);
    });

    it("intentOptionsHaveThreeValues", async () => {
      const element = build();
      await flushPromises();
      const combo = element.shadowRoot.querySelector(
        '[data-test="input-intent"]'
      );
      expect(combo.options.length).toBe(3);
      expect(combo.options.map((o) => o.value)).toEqual([
        "Low",
        "Medium",
        "High"
      ]);
    });
  });

  describe("form field interaction", () => {
    it("fieldChangesPropagateToApexCallPayload", async () => {
      testTouch.mockResolvedValue(resolvedFixture());
      const element = build();
      await flushPromises();

      setField(element, "input-email", "sarah@uhc.example.com");
      setField(element, "input-topic", "TOPIC_X");
      setField(element, "input-touchType", "Form");
      setField(element, "input-persona", "Technical");
      setField(element, "input-intent", "High");
      setField(element, "input-asset", "Asset One");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      expect(testTouch).toHaveBeenCalledWith({
        input: {
          email: "sarah@uhc.example.com",
          topicExternalCode: "TOPIC_X",
          touchType: "Form",
          persona: "Technical",
          intentLevel: "High",
          assetName: "Asset One"
        }
      });
    });

    it("handleFieldChangeIgnoresElementsWithoutDataField", async () => {
      // Invoke handleFieldChange directly with an event whose target
      // has no data-field — exercises the early-return guard. This is
      // exposed via the @api lifecycle: dispatch a change on a synthetic
      // element added to the shadow root, then verify the form payload
      // is unchanged on subsequent submit.
      testTouch.mockResolvedValue(resolvedFixture());
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      // Synthetic change event with target carrying no dataset.field.
      // Production handler reads `event.target.dataset.field`; we craft
      // a target that returns undefined for it.
      const stubTarget = { dataset: {}, value: "ignored" };
      const handler = element.shadowRoot.querySelector(
        '[data-test="input-email"]'
      );
      // Wrap a CustomEvent so the handler's `event.target` is our stub
      // via Object.defineProperty.
      const ev = new CustomEvent("change");
      Object.defineProperty(ev, "target", { value: stubTarget });
      handler.dispatchEvent(ev);
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      // Email survived; no `undefined` field was injected.
      const input = testTouch.mock.calls[0][0].input;
      expect(input.email).toBe("x@y.com");
      expect(input).not.toHaveProperty("undefined");
    });

    it("signalRowsReturnsEmptyArrayWhenSignalsNotArray", async () => {
      // Production code: `if (!Array.isArray(list)) return [];`
      // Force a result where `signals` is not an array.
      testTouch.mockResolvedValue({
        touchId: "x",
        resolutionStatus: "Resolved",
        contactId: null,
        contactName: null,
        accountId: null,
        accountName: null,
        signalsCreated: 0,
        signals: "not-an-array",
        messages: []
      });
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();
      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      // Result panel renders, but no signal rows.
      expect(
        element.shadowRoot.querySelectorAll('[data-test="signal-row"]').length
      ).toBe(0);
    });
  });

  describe("submit happy path", () => {
    it("submitCallsApexWithFormPayload", async () => {
      testTouch.mockResolvedValue(resolvedFixture());
      const element = build();
      await flushPromises();
      setField(element, "input-email", "sarah@uhc.example.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      expect(testTouch).toHaveBeenCalledTimes(1);
      expect(testTouch.mock.calls[0][0].input.email).toBe(
        "sarah@uhc.example.com"
      );
    });

    it("submitWithEmptyEmailIsNoOp", async () => {
      const element = build();
      await flushPromises();
      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      expect(testTouch).not.toHaveBeenCalled();
    });

    it("submitFiresSuccessToastForResolved", async () => {
      testTouch.mockResolvedValue(
        resolvedFixture({ resolutionStatus: "Resolved" })
      );
      const element = build();
      const onToast = listenForToast(element);
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      expect(onToast.mock.calls[0][0].detail.variant).toBe("success");
      expect(onToast.mock.calls[0][0].detail.title).toBe("Touch processed");
    });

    it("submitFiresInfoToastForNonResolved", async () => {
      testTouch.mockResolvedValue(
        resolvedFixture({ resolutionStatus: "NoMatch" })
      );
      const element = build();
      const onToast = listenForToast(element);
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      expect(onToast.mock.calls[0][0].detail.variant).toBe("info");
    });
  });

  describe("result panel render", () => {
    async function submitWithResult(element, result) {
      testTouch.mockResolvedValue(result);
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();
      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();
    }

    it("resultPanelReplacesFormOnSuccess", async () => {
      const element = build();
      await submitWithResult(element, resolvedFixture());
      expect(element.shadowRoot.querySelector('[data-test="form"]')).toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="result-panel"]')
      ).not.toBeNull();
    });

    it("statusBadgeClassResolvedIsSuccess", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ resolutionStatus: "Resolved" })
      );
      const badge = element.shadowRoot.querySelector(
        '[data-test="status-badge"]'
      );
      expect(badge.className).toContain("slds-theme_success");
      expect(badge.textContent.trim()).toBe("Resolved");
    });

    it("statusBadgeClassAmbiguousIsWarning", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ resolutionStatus: "Ambiguous" })
      );
      const badge = element.shadowRoot.querySelector(
        '[data-test="status-badge"]'
      );
      expect(badge.className).toContain("slds-theme_warning");
    });

    it("statusBadgeClassNoMatchIsError", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ resolutionStatus: "NoMatch" })
      );
      const badge = element.shadowRoot.querySelector(
        '[data-test="status-badge"]'
      );
      expect(badge.className).toContain("slds-theme_error");
    });

    it("statusBadgeClassUnknownIsBaseOnly", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ resolutionStatus: "Wat" })
      );
      const badge = element.shadowRoot.querySelector(
        '[data-test="status-badge"]'
      );
      expect(badge.className).toContain("slds-badge");
      expect(badge.className).not.toContain("slds-theme_");
    });

    it("showsContactLinkWhenContactIdPresent", async () => {
      const element = build();
      await submitWithResult(element, resolvedFixture());
      const link = element.shadowRoot.querySelector(
        '[data-test="contact-link"]'
      );
      expect(link).not.toBeNull();
      expect(link.getAttribute("href")).toBe(
        "/lightning/r/Contact/003000000000001/view"
      );
      expect(link.getAttribute("target")).toBe("_top");
    });

    it("omitsContactLinkWhenContactIdNull", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ contactId: null, contactName: null })
      );
      expect(
        element.shadowRoot.querySelector('[data-test="contact-link"]')
      ).toBeNull();
    });

    it("showsAccountLinkWhenAccountIdPresent", async () => {
      const element = build();
      await submitWithResult(element, resolvedFixture());
      const link = element.shadowRoot.querySelector(
        '[data-test="account-link"]'
      );
      expect(link).not.toBeNull();
      expect(link.getAttribute("href")).toBe(
        "/lightning/r/Account/001000000000001/view"
      );
    });

    it("omitsAccountLinkWhenAccountIdNull", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ accountId: null, accountName: null })
      );
      expect(
        element.shadowRoot.querySelector('[data-test="account-link"]')
      ).toBeNull();
    });

    it("signalCountPluralization", async () => {
      const elementZero = build();
      await submitWithResult(
        elementZero,
        resolvedFixture({ signalsCreated: 0, signals: [] })
      );
      expect(
        elementZero.shadowRoot
          .querySelector('[data-test="signal-count"]')
          .textContent.trim()
      ).toBe("0 signals created");

      const elementOne = build();
      await submitWithResult(
        elementOne,
        resolvedFixture({
          signalsCreated: 1,
          signals: [
            {
              signalId: "x",
              opportunityId: "y",
              opportunityName: "z",
              matchPath: "OCR",
              confidence: 90
            }
          ]
        })
      );
      expect(
        elementOne.shadowRoot
          .querySelector('[data-test="signal-count"]')
          .textContent.trim()
      ).toBe("1 signal created");
    });

    it("signalsListRendersAllRows", async () => {
      const element = build();
      await submitWithResult(element, resolvedFixture());
      const rows = element.shadowRoot.querySelectorAll(
        '[data-test="signal-row"]'
      );
      expect(rows.length).toBe(2);
    });

    it("signalConfidenceClampedTo100", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({
          signalsCreated: 1,
          signals: [
            {
              signalId: "x",
              opportunityId: "y",
              opportunityName: "z",
              matchPath: "OCR",
              confidence: 150
            }
          ]
        })
      );
      const fill = element.shadowRoot.querySelector(".confidence-bar__fill");
      expect(fill.style.width).toBe("100%");
    });

    it("signalConfidenceClampedTo0ForNegative", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({
          signalsCreated: 1,
          signals: [
            {
              signalId: "x",
              opportunityId: "y",
              opportunityName: "z",
              matchPath: "OCR",
              confidence: -25
            }
          ]
        })
      );
      const fill = element.shadowRoot.querySelector(".confidence-bar__fill");
      expect(fill.style.width).toBe("0%");
    });

    it("signalConfidenceNullDefaultsTo0Percent", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({
          signalsCreated: 1,
          signals: [
            {
              signalId: "x",
              opportunityId: "y",
              opportunityName: "z",
              matchPath: "OCR",
              confidence: undefined
            }
          ]
        })
      );
      const rowText = element.shadowRoot.querySelector(
        '[data-test="signal-row"]'
      ).textContent;
      expect(rowText).toContain("0%");
    });

    it("messagesListRendersWhenPresent", async () => {
      const element = build();
      await submitWithResult(
        element,
        resolvedFixture({ messages: ["one", "two"] })
      );
      const ul = element.shadowRoot.querySelector('[data-test="messages"]');
      expect(ul).not.toBeNull();
      expect(ul.querySelectorAll("li").length).toBe(2);
    });

    it("messagesHiddenWhenEmpty", async () => {
      const element = build();
      await submitWithResult(element, resolvedFixture({ messages: [] }));
      expect(
        element.shadowRoot.querySelector('[data-test="messages"]')
      ).toBeNull();
    });

    it("messagesHiddenWhenMissing", async () => {
      const element = build();
      await submitWithResult(element, resolvedFixture({ messages: undefined }));
      expect(
        element.shadowRoot.querySelector('[data-test="messages"]')
      ).toBeNull();
    });
  });

  describe("reset", () => {
    it("resetButtonClearsResultAndShowsForm", async () => {
      testTouch.mockResolvedValue(resolvedFixture());
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();
      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="result-panel"]')
      ).not.toBeNull();

      element.shadowRoot
        .querySelector('[data-test="reset-btn"]')
        .dispatchEvent(new CustomEvent("click"));
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="form"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="result-panel"]')
      ).toBeNull();
    });

    it("resetClearsFormStateForReSubmit", async () => {
      testTouch.mockResolvedValue(resolvedFixture());
      const element = build();
      await flushPromises();
      setField(element, "input-email", "first@y.com");
      await flushPromises();
      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="reset-btn"]')
        .dispatchEvent(new CustomEvent("click"));
      await flushPromises();

      // After reset, the submit button should be disabled again because
      // form.email is back to empty.
      const btn = element.shadowRoot.querySelector('[data-test="submit-btn"]');
      expect(btn.disabled).toBe(true);
    });
  });

  describe("error path", () => {
    it("rendersFormErrorMessageOnApexRejection", async () => {
      testTouch.mockRejectedValue({ body: { message: "X went wrong" } });
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="form-error"]');
      expect(err).not.toBeNull();
      expect(err.textContent).toMatch(/X went wrong/);
    });

    it("usesFallbackMessageWhenRejectionHasNoBody", async () => {
      testTouch.mockRejectedValue(new Error("naked"));
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();
      await flushPromises();

      const err = element.shadowRoot.querySelector('[data-test="form-error"]');
      expect(err.textContent).toMatch(/Unable to run the test/);
    });

    it("firesErrorToastOnApexRejection", async () => {
      testTouch.mockRejectedValue({ body: { message: "X went wrong" } });
      const element = build();
      const onToast = listenForToast(element);
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(onToast).toHaveBeenCalledTimes(1);
      expect(onToast.mock.calls[0][0].detail.variant).toBe("error");
    });

    it("keepsFormVisibleOnError", async () => {
      testTouch.mockRejectedValue({ body: { message: "X" } });
      const element = build();
      await flushPromises();
      setField(element, "input-email", "x@y.com");
      await flushPromises();

      element.shadowRoot
        .querySelector('[data-test="form"]')
        .dispatchEvent(new CustomEvent("submit"));
      await flushPromises();
      await flushPromises();
      await flushPromises();

      expect(
        element.shadowRoot.querySelector('[data-test="form"]')
      ).not.toBeNull();
      expect(
        element.shadowRoot.querySelector('[data-test="result-panel"]')
      ).toBeNull();
    });
  });
});
