/**
 * Global Jest mock for `lightning/modal`. The real `lightning/modal` base
 * class cannot mount in jsdom, and `@salesforce/sfdx-lwc-jest` does not
 * ship a stub for it.
 *
 * close-call assertion strategy:
 *   LWC's proxy blocks external access to non-@api fields — `element.close`
 *   reads as `undefined` from outside the component. To give tests a stable
 *   observation point without modifying production code, the stub's
 *   `close()` method dispatches a synthetic `lwc__modal_close` CustomEvent
 *   that carries the close args on `detail`. Tests use:
 *
 *     const onClose = jest.fn();
 *     element.addEventListener('lwc__modal_close', onClose);
 *     // ...drive the modal...
 *     expect(onClose).toHaveBeenCalledTimes(1);
 *     expect(onClose.mock.calls[0][0].detail).toEqual({ result: 'cancel' });
 *
 *   Production code calls `this.close(args)` exactly as it does against the
 *   real platform base class, so behavior is preserved.
 *
 * Registered in `jest.config.js` via `moduleNameMapper`.
 */
const { LightningElement } = require("lwc");

class LightningModal extends LightningElement {
  close(args) {
    this.dispatchEvent(new CustomEvent("lwc__modal_close", { detail: args }));
  }

  static open() {
    return Promise.resolve({ result: "closed", payload: undefined });
  }
}

module.exports = LightningModal;
module.exports.default = LightningModal;
module.exports.__esModule = true;
