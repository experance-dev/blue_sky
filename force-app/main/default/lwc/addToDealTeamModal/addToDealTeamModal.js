/**
 * @description Modal opened from EngagementPanel's "+ Add" button. Extends
 *              LightningModal so callers can invoke via `LightningModal.open()`.
 *              Collects Role + (optional) Opportunity + Primary flag, then calls
 *              `EngagementController.addToOcrSafe`. Closes with the AddToOcrResult
 *              payload so the parent host can decide whether to chain into the
 *              AlreadyAddedModal (race-detected) flow.
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
import LightningModal from "lightning/modal";
import { api } from "lwc";
import addToOcrSafe from "@salesforce/apex/EngagementController.addToOcrSafe";

const ROLE_OPTIONS = Object.freeze([
  { label: "Decision Maker", value: "Decision Maker" },
  { label: "Economic Buyer", value: "Economic Buyer" },
  { label: "Technical Evaluator", value: "Technical Evaluator" },
  { label: "Champion", value: "Champion" },
  { label: "Influencer", value: "Influencer" },
  { label: "Business User", value: "Business User" },
  { label: "Other", value: "Other" }
]);

export default class AddToDealTeamModal extends LightningModal {
  @api contactId;
  @api contactName;
  @api opportunityId;
  @api recordContext;

  role = "";
  isPrimary = false;
  isSaving = false;
  errorMessage;

  get roleOptions() {
    return ROLE_OPTIONS;
  }

  get isAccountScope() {
    return this.recordContext === "Account";
  }

  handleRoleChange(event) {
    this.role = event.detail.value;
  }

  handlePrimaryToggle(event) {
    this.isPrimary = event.target.checked;
  }

  handleOppChange(event) {
    // eslint-disable-next-line @lwc/lwc/no-api-reassignments
    this.opportunityId = event.detail.value;
  }

  handleCancel() {
    this.close({ result: "cancel" });
  }

  async handleSave() {
    if (!this.role || !this.opportunityId) {
      this.errorMessage = "Role and Opportunity are required.";
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      const result = await addToOcrSafe({
        contactId: this.contactId,
        opportunityId: this.opportunityId,
        role: this.role,
        isPrimary: this.isPrimary
      });
      // Note: alreadyExists=true is NOT a failure here. We pass the
      // payload up; the caller (engagementPanel) inspects it and decides
      // whether to open AlreadyAddedModal.
      this.close({ result: "success", payload: result });
    } catch (e) {
      this.errorMessage =
        (e && e.body && e.body.message) || "Failed to add. Try again.";
    } finally {
      this.isSaving = false;
    }
  }
}
