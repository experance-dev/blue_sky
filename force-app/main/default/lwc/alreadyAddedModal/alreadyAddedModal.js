import { api } from "lwc";
import LightningModal from "lightning/modal";
import { NavigationMixin } from "lightning/navigation";

/**
 * Confirmation modal shown when a server-side race is detected on
 * "+ Add to Deal Team" — the contact was already added to OCR between
 * render and click. Offers Yes (navigate to OCR record) / No (default focus).
 *
 * Opened by the engagementPanel host after addToDealTeamModal closes with
 * `payload.alreadyExists === true`.
 */
export default class AlreadyAddedModal extends NavigationMixin(LightningModal) {
  @api contactName;
  @api addedByUserName;
  @api addedAt; // ISO string
  @api ocrId;
  @api opportunityId;

  handleYes() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.ocrId,
        objectApiName: "OpportunityContactRole",
        actionName: "view"
      }
    });
    this.close({ result: "navigated" });
  }

  handleNo() {
    this.close({ result: "closed" });
  }
}
