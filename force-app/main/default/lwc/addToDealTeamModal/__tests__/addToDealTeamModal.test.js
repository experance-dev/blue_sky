/**
 * Jest spec for c-add-to-deal-team-modal. Per TEST_DESIGN.md.
 *
 * Uses the GLOBAL `lightning/modal` stub from
 * `force-app/test/jest-mocks/lightning/modal.js`. The stub dispatches a
 * `lwc__modal_close` CustomEvent whenever production code calls
 * `this.close(args)` — tests subscribe via `addEventListener` to capture
 * the close shape (LWC's proxy blocks direct `element.close` reads).
 */
import { createElement } from "lwc";
import AddToDealTeamModal from "c/addToDealTeamModal";
import addToOcrSafe from "@salesforce/apex/EngagementController.addToOcrSafe";

jest.mock(
  "@salesforce/apex/EngagementController.addToOcrSafe",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CONTACT_ID = "003000000000001AAA";
const OPPORTUNITY_ID = "006000000000001AAA";
const OCR_ID = "00K000000000001AAA";

function buildModal(opts = {}) {
  const recordContext = opts.recordContext ?? "Opportunity";
  const hasExplicitOppId = Object.prototype.hasOwnProperty.call(
    opts,
    "opportunityId"
  );
  const opportunityId = hasExplicitOppId ? opts.opportunityId : OPPORTUNITY_ID;
  const element = createElement("c-add-to-deal-team-modal", {
    is: AddToDealTeamModal
  });
  element.contactId = CONTACT_ID;
  element.contactName = "Sarah Johnson";
  if (hasExplicitOppId) {
    element.opportunityId = opportunityId;
  } else {
    element.opportunityId = opportunityId;
  }
  element.recordContext = recordContext;
  document.body.appendChild(element);
  return element;
}

function flushMicrotasks() {
  return Promise.resolve().then(() => Promise.resolve());
}

function findButton(element, label) {
  const buttons = element.shadowRoot.querySelectorAll("lightning-button");
  return Array.from(buttons).find((b) => b.label === label);
}

function setRole(element, role) {
  const combo = element.shadowRoot.querySelector("lightning-combobox");
  combo.dispatchEvent(new CustomEvent("change", { detail: { value: role } }));
}

function setPrimary(element, primary) {
  const cb = element.shadowRoot.querySelector("lightning-input");
  cb.checked = primary;
  cb.dispatchEvent(new CustomEvent("change"));
}

function listenForClose(element) {
  const listener = jest.fn();
  element.addEventListener("lwc__modal_close", listener);
  return listener;
}

function closeArgs(listener, callIdx = 0) {
  return listener.mock.calls[callIdx][0].detail;
}

describe("c-add-to-deal-team-modal", () => {
  beforeEach(() => {
    addToOcrSafe.mockReset();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  describe("render / state", () => {
    it("rendersHeaderAndContactName", async () => {
      const element = buildModal();
      await flushMicrotasks();
      const header = element.shadowRoot.querySelector("lightning-modal-header");
      expect(header.label).toBe("Add to Deal Team");
      const body = element.shadowRoot.querySelector("lightning-modal-body");
      expect(body.textContent).toContain("Sarah Johnson");
    });

    it("rendersAllSevenRoleOptions", async () => {
      const element = buildModal();
      await flushMicrotasks();
      const combo = element.shadowRoot.querySelector("lightning-combobox");
      expect(combo.options.length).toBe(7);
      const values = combo.options.map((o) => o.value);
      expect(values).toEqual([
        "Decision Maker",
        "Economic Buyer",
        "Technical Evaluator",
        "Champion",
        "Influencer",
        "Business User",
        "Other"
      ]);
    });

    it("hidesOpportunityPickerInOpportunityScope", async () => {
      const element = buildModal({ recordContext: "Opportunity" });
      await flushMicrotasks();
      expect(
        element.shadowRoot.querySelector("lightning-record-picker")
      ).toBeNull();
    });

    it("showsOpportunityPickerInAccountScope", async () => {
      const element = buildModal({ recordContext: "Account" });
      await flushMicrotasks();
      const picker = element.shadowRoot.querySelector(
        "lightning-record-picker"
      );
      expect(picker).not.toBeNull();
      expect(picker.objectApiName).toBe("Opportunity");
      expect(picker.required).toBe(true);
    });

    it("primaryCheckboxDefaultsUnchecked", async () => {
      const element = buildModal();
      await flushMicrotasks();
      const cb = element.shadowRoot.querySelector("lightning-input");
      expect(cb.checked).toBe(false);
    });
  });

  describe("validation (bad path)", () => {
    it("requiresRoleBeforeSave_OpportunityScope", async () => {
      const element = buildModal({ recordContext: "Opportunity" });
      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();

      const alert = element.shadowRoot.querySelector('[role="alert"]');
      expect(alert).not.toBeNull();
      expect(alert.textContent).toMatch(/required/i);
      expect(addToOcrSafe).not.toHaveBeenCalled();
    });

    it("requiresOpportunityBeforeSave_AccountScope", async () => {
      const element = buildModal({
        recordContext: "Account",
        opportunityId: null
      });
      await flushMicrotasks();
      // Sanity check: @api property reflects what we set.
      expect(element.opportunityId).toBeFalsy();
      // Role IS set; opportunity is NOT picked.
      setRole(element, "Champion");
      await flushMicrotasks();
      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();

      const alert = element.shadowRoot.querySelector('[role="alert"]');
      expect(alert).not.toBeNull();
      expect(alert.textContent).toMatch(/required/i);
      expect(addToOcrSafe).not.toHaveBeenCalled();
    });

    it("clearsErrorOnSubsequentSuccessfulSave", async () => {
      addToOcrSafe.mockRejectedValueOnce({
        body: { message: "Boom one" }
      });
      addToOcrSafe.mockResolvedValueOnce({
        success: true,
        alreadyExists: false,
        ocrId: OCR_ID
      });
      const element = buildModal();
      setRole(element, "Champion");

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();
      expect(
        element.shadowRoot.querySelector('[role="alert"]').textContent.trim()
      ).toMatch(/Boom one/);

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();
      await flushMicrotasks();
      expect(element.shadowRoot.querySelector('[role="alert"]')).toBeNull();
    });
  });

  describe("happy path", () => {
    it("callsAddToOcrSafeWithExpectedParams", async () => {
      addToOcrSafe.mockResolvedValue({
        success: true,
        alreadyExists: false,
        ocrId: OCR_ID
      });
      const element = buildModal();
      setRole(element, "Economic Buyer");
      setPrimary(element, true);

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();

      expect(addToOcrSafe).toHaveBeenCalledTimes(1);
      expect(addToOcrSafe).toHaveBeenCalledWith({
        contactId: CONTACT_ID,
        opportunityId: OPPORTUNITY_ID,
        role: "Economic Buyer",
        isPrimary: true
      });
    });

    it("closesWithSuccessPayloadOnCleanSave", async () => {
      const payload = {
        success: true,
        alreadyExists: false,
        ocrId: OCR_ID,
        role: "Economic Buyer",
        isPrimary: false
      };
      addToOcrSafe.mockResolvedValue(payload);
      const element = buildModal();
      const onClose = listenForClose(element);
      setRole(element, "Economic Buyer");

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();

      expect(onClose).toHaveBeenCalledTimes(1);
      expect(closeArgs(onClose)).toEqual({
        result: "success",
        payload
      });
    });

    it("closesWithSuccessOnAlreadyExistsRace", async () => {
      const payload = {
        success: false,
        alreadyExists: true,
        ocrId: OCR_ID,
        addedByUserId: "005000000000001AAA",
        addedByUserName: "Jane Rep",
        addedAt: "2026-05-11T12:00:00.000Z",
        role: "Decision Maker",
        isPrimary: false
      };
      addToOcrSafe.mockResolvedValue(payload);
      const element = buildModal();
      const onClose = listenForClose(element);
      setRole(element, "Decision Maker");

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();

      // alreadyExists is NOT a failure — modal still resolves success.
      expect(closeArgs(onClose)).toEqual({
        result: "success",
        payload
      });
    });
  });

  describe("bad path / errors", () => {
    it("displaysServerErrorMessage", async () => {
      addToOcrSafe.mockRejectedValue({
        body: { message: "Server exploded." }
      });
      const element = buildModal();
      const onClose = listenForClose(element);
      setRole(element, "Champion");

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();
      await flushMicrotasks();

      const alert = element.shadowRoot.querySelector('[role="alert"]');
      expect(alert).not.toBeNull();
      expect(alert.textContent).toMatch(/Server exploded/);
      // Failure path does NOT close the modal.
      expect(onClose).not.toHaveBeenCalled();
    });

    it("displaysFallbackErrorWhenApexRejectsWithNoBody", async () => {
      addToOcrSafe.mockRejectedValue(new Error("naked"));
      const element = buildModal();
      setRole(element, "Champion");

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();
      await flushMicrotasks();

      const alert = element.shadowRoot.querySelector('[role="alert"]');
      expect(alert.textContent).toMatch(/Failed to add\. Try again\./);
    });
  });

  describe("interactions / lifecycle", () => {
    it("cancelClickClosesWithoutApexInvocation", async () => {
      const element = buildModal();
      const onClose = listenForClose(element);
      findButton(element, "Cancel").dispatchEvent(new CustomEvent("click"));
      await flushMicrotasks();

      expect(addToOcrSafe).not.toHaveBeenCalled();
      expect(closeArgs(onClose)).toEqual({ result: "cancel" });
    });

    it("isSavingDisablesSaveButtonDuringApexCall", async () => {
      let resolveApex;
      addToOcrSafe.mockReturnValue(
        new Promise((resolve) => {
          resolveApex = resolve;
        })
      );
      const element = buildModal();
      const onClose = listenForClose(element);
      setRole(element, "Champion");

      const saveBtn = findButton(element, "Add to Deal Team");
      expect(saveBtn.disabled).toBe(false);

      saveBtn.dispatchEvent(new CustomEvent("click"));
      await flushMicrotasks();
      // Apex still pending → isSaving is true → button disabled.
      expect(findButton(element, "Add to Deal Team").disabled).toBe(true);

      resolveApex({
        success: true,
        alreadyExists: false,
        ocrId: OCR_ID
      });
      await flushMicrotasks();
      await flushMicrotasks();
      // Close was invoked once Apex resolved.
      expect(onClose).toHaveBeenCalledTimes(1);
    });
  });

  describe("opportunity scope picker change", () => {
    it("handleOppChangeUpdatesOpportunityIdForSave", async () => {
      // Account scope, user picks an opportunity then saves.
      addToOcrSafe.mockResolvedValue({
        success: true,
        alreadyExists: false,
        ocrId: OCR_ID
      });
      const element = buildModal({
        recordContext: "Account",
        opportunityId: undefined
      });
      await flushMicrotasks();

      const picker = element.shadowRoot.querySelector(
        "lightning-record-picker"
      );
      picker.dispatchEvent(
        new CustomEvent("change", {
          detail: { value: "006000000000999AAA" }
        })
      );
      setRole(element, "Influencer");

      findButton(element, "Add to Deal Team").dispatchEvent(
        new CustomEvent("click")
      );
      await flushMicrotasks();
      await flushMicrotasks();

      expect(addToOcrSafe).toHaveBeenCalledWith({
        contactId: CONTACT_ID,
        opportunityId: "006000000000999AAA",
        role: "Influencer",
        isPrimary: false
      });
    });
  });
});
