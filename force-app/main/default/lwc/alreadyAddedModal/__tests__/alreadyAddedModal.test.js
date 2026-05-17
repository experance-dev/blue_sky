/**
 * Jest spec for c-already-added-modal. Per TEST_DESIGN.md.
 *
 * Uses GLOBAL `lightning/modal` stub — close calls observed via
 * `lwc__modal_close` CustomEvent. Uses LOCAL `lightning/navigation` mock
 * (jest-mocks/lightning/navigation.js) which adds `getNavigateCalledWith`
 * + `__resetNavigationMockState` (the default sfdx-lwc-jest stub omits
 * these helpers).
 */
import { createElement } from "lwc";
import AlreadyAddedModal from "c/alreadyAddedModal";
import {
  getNavigateCalledWith,
  __resetNavigationMockState
} from "lightning/navigation";

const PROPS = {
  contactName: "Sarah Johnson",
  addedByUserName: "Alex Rivera",
  addedAt: "2026-05-11T14:30:00.000Z",
  ocrId: "00301000000abcdAAA",
  opportunityId: "0061000000xyzAAA"
};

function createModal(props = PROPS) {
  const element = createElement("c-already-added-modal", {
    is: AlreadyAddedModal
  });
  Object.assign(element, props);
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

describe("c-already-added-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    __resetNavigationMockState();
    jest.clearAllMocks();
  });

  describe("render", () => {
    it("rendersHeaderAndBodyContent", async () => {
      const element = createModal();
      await flush();

      const header = element.shadowRoot.querySelector("lightning-modal-header");
      expect(header.label).toBe("Already Added");

      const body = element.shadowRoot.querySelector("lightning-modal-body");
      expect(body.textContent).toContain("Sarah Johnson");
      expect(body.textContent).toContain("Alex Rivera");
      expect(body.textContent).toContain(
        "Would you like to view the OCR record?"
      );
    });

    it("rendersFormattedDateTimeForAddedAt", async () => {
      const element = createModal();
      await flush();

      const dateEl = element.shadowRoot.querySelector(
        "lightning-formatted-date-time"
      );
      expect(dateEl).not.toBeNull();
      expect(dateEl.value).toBe(PROPS.addedAt);
      // Formatting attributes preserved for SLDS consistency.
      expect(dateEl.year).toBe("numeric");
      expect(dateEl.month).toBe("short");
      expect(dateEl.day).toBe("2-digit");
      expect(dateEl.hour).toBe("2-digit");
      expect(dateEl.minute).toBe("2-digit");
    });

    it("rendersNoBeforeYesForFocusTrap", async () => {
      const element = createModal();
      await flush();

      const footer = element.shadowRoot.querySelector("lightning-modal-footer");
      const buttons = footer.querySelectorAll("lightning-button");
      expect(buttons[0].dataset.button).toBe("no");
      expect(buttons[1].dataset.button).toBe("yes");
    });

    it("bothButtonsHaveTitlesForA11y", async () => {
      const element = createModal();
      await flush();

      const noBtn = element.shadowRoot.querySelector('[data-button="no"]');
      const yesBtn = element.shadowRoot.querySelector('[data-button="yes"]');
      expect(noBtn.title).toBe("Close without navigating");
      expect(yesBtn.title).toBe("Open the OpportunityContactRole record");
      expect(noBtn.label).toBe("No");
      expect(yesBtn.label).toBe("Yes, view OCR");
    });
  });

  describe("Yes path", () => {
    it("yesClickFiresNavigateWithOcrConfig", async () => {
      const element = createModal();
      await flush();

      const yesBtn = element.shadowRoot.querySelector('[data-button="yes"]');
      yesBtn.dispatchEvent(new CustomEvent("click"));
      await flush();

      const navConfig = getNavigateCalledWith();
      expect(navConfig).toEqual({
        type: "standard__recordPage",
        attributes: {
          recordId: PROPS.ocrId,
          objectApiName: "OpportunityContactRole",
          actionName: "view"
        }
      });
    });

    it("yesClickClosesModalWithNavigatedResult", async () => {
      const element = createModal();
      const onClose = listenForClose(element);
      await flush();

      const yesBtn = element.shadowRoot.querySelector('[data-button="yes"]');
      yesBtn.dispatchEvent(new CustomEvent("click"));
      await flush();

      expect(onClose).toHaveBeenCalledTimes(1);
      expect(onClose.mock.calls[0][0].detail).toEqual({
        result: "navigated"
      });
    });
  });

  describe("No path", () => {
    it("noClickDoesNotNavigate", async () => {
      const element = createModal();
      await flush();

      const noBtn = element.shadowRoot.querySelector('[data-button="no"]');
      noBtn.dispatchEvent(new CustomEvent("click"));
      await flush();

      expect(getNavigateCalledWith()).toBeUndefined();
    });

    it("noClickClosesWithClosedResult", async () => {
      const element = createModal();
      const onClose = listenForClose(element);
      await flush();

      const noBtn = element.shadowRoot.querySelector('[data-button="no"]');
      noBtn.dispatchEvent(new CustomEvent("click"));
      await flush();

      expect(onClose).toHaveBeenCalledTimes(1);
      expect(onClose.mock.calls[0][0].detail).toEqual({
        result: "closed"
      });
    });
  });
});
