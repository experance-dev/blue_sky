/**
 * @description Admin tool — synthesize a single Engagement_Touch__c, push it
 *              through identity resolution + routing, and render what came out.
 *              All state is local; the only Apex round-trip is an imperative
 *              `testTouch({ input })` call so admins watch the result panel
 *              update synchronously after submit.
 *
 *              Companion controller: `EngagementAdminController.testTouch`.
 *              Companion screen: `Engagement Admin Console` flexipage.
 *
 * @author David Wood
 * @since May 2026
 */
import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import testTouch from "@salesforce/apex/EngagementAdminController.testTouch";

const TOUCH_TYPES = ["Download", "Form", "Webinar", "Page", "Event"];
const PERSONAS = ["Executive", "Finance", "Technical", "Operational", "Other"];
const INTENT_LEVELS = ["Low", "Medium", "High"];

export default class EngagementTestATouch extends LightningElement {
  @track form = this.emptyForm();
  @track result = null;
  @track error = null;
  isSubmitting = false;

  // ----- Picklist option getters -----

  get touchTypeOptions() {
    return TOUCH_TYPES.map((v) => ({ label: v, value: v }));
  }

  get personaOptions() {
    return PERSONAS.map((v) => ({ label: v, value: v }));
  }

  get intentOptions() {
    return INTENT_LEVELS.map((v) => ({ label: v, value: v }));
  }

  // ----- Render-state getters (wire-getter pattern, lwc.md) -----

  get hasResult() {
    return this.result !== null;
  }

  get showForm() {
    return !this.hasResult;
  }

  get statusBadgeClass() {
    const base = "slds-badge";
    switch (this.result?.resolutionStatus) {
      case "Resolved":
        return `${base} slds-theme_success`;
      case "Ambiguous":
        return `${base} slds-theme_warning`;
      case "NoMatch":
        return `${base} slds-theme_error`;
      default:
        return base;
    }
  }

  get statusLabel() {
    return this.result?.resolutionStatus || "Unknown";
  }

  get contactUrl() {
    return this.result?.contactId
      ? `/lightning/r/Contact/${this.result.contactId}/view`
      : null;
  }

  get accountUrl() {
    return this.result?.accountId
      ? `/lightning/r/Account/${this.result.accountId}/view`
      : null;
  }

  get signalRows() {
    const list = this.result?.signals;
    if (!Array.isArray(list)) {
      return [];
    }
    return list.map((s) => ({
      ...s,
      key: s.signalId,
      opportunityUrl: `/lightning/r/Opportunity/${s.opportunityId}/view`,
      confidenceLabel: `${s.confidence ?? 0}%`,
      confidenceStyle: `width:${Math.min(100, Math.max(0, s.confidence ?? 0))}%`
    }));
  }

  get signalCountLabel() {
    const count = this.result?.signalsCreated ?? 0;
    return `${count} signal${count === 1 ? "" : "s"} created`;
  }

  get hasSignals() {
    return (this.result?.signalsCreated ?? 0) > 0;
  }

  get messages() {
    const list = this.result?.messages;
    if (!Array.isArray(list)) {
      return [];
    }
    return list.map((m, idx) => ({ key: `m-${idx}`, text: m }));
  }

  get submitDisabled() {
    return this.isSubmitting || !this.form.email;
  }

  // ----- Event handlers -----

  handleFieldChange(event) {
    const name = event.target.dataset.field;
    if (!name) {
      return;
    }
    this.form = { ...this.form, [name]: event.target.value };
  }

  async handleSubmit(event) {
    event.preventDefault();
    if (this.submitDisabled) {
      return;
    }
    this.isSubmitting = true;
    this.error = null;
    try {
      const response = await testTouch({ input: this.form });
      this.result = response;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Touch processed",
          message: response.resolutionStatus,
          variant: response.resolutionStatus === "Resolved" ? "success" : "info"
        })
      );
    } catch (e) {
      this.error = (e && e.body && e.body.message) || "Unable to run the test.";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: this.error,
          variant: "error"
        })
      );
    } finally {
      this.isSubmitting = false;
    }
  }

  handleReset() {
    this.form = this.emptyForm();
    this.result = null;
    this.error = null;
  }

  // ----- Helpers -----

  emptyForm() {
    return {
      email: "",
      topicExternalCode: "",
      touchType: "Download",
      persona: "Executive",
      intentLevel: "Medium",
      assetName: ""
    };
  }
}
