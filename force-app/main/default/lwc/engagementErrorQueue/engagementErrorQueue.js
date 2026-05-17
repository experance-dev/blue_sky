/**
 * @description Admin tool — surfaces Engagement Touches stuck in NoMatch,
 *              Ambiguous, or Processing Error so admins can retry or ignore
 *              them inline. Row actions hit
 *              `EngagementAdminController.retryResolution` /
 *              `EngagementAdminController.ignoreTouch`, then `refreshApex`
 *              the wired result so the table reflects the new state.
 *
 * @author David Wood
 * @since May 2026
 */
import { LightningElement, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getTouchesWithIssues from "@salesforce/apex/EngagementAdminController.getTouchesWithIssues";
import retryResolution from "@salesforce/apex/EngagementAdminController.retryResolution";
import ignoreTouch from "@salesforce/apex/EngagementAdminController.ignoreTouch";

const DEFAULT_LIMIT = 50;
const IGNORE_REASON_DEFAULT = "Admin marked as ignored";

const ROW_ACTIONS = [
  { label: "Retry", name: "retry" },
  { label: "Ignore", name: "ignore" }
];

const COLUMNS = [
  { label: "Touch #", fieldName: "touchName", initialWidth: 120 },
  { label: "Email", fieldName: "email", wrapText: true },
  { label: "Asset", fieldName: "assetName", wrapText: true },
  {
    label: "Status",
    fieldName: "resolutionStatus",
    initialWidth: 120,
    cellAttributes: {
      class: { fieldName: "statusClass" }
    }
  },
  { label: "Source", fieldName: "sourceSystem", initialWidth: 120 },
  {
    label: "Date",
    fieldName: "occurredAt",
    type: "date",
    typeAttributes: {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }
  },
  {
    type: "action",
    typeAttributes: { rowActions: ROW_ACTIONS }
  }
];

export default class EngagementErrorQueue extends LightningElement {
  wiredResult;
  columns = COLUMNS;
  isBusy = false;

  @wire(getTouchesWithIssues, { limitN: DEFAULT_LIMIT })
  wired(result) {
    this.wiredResult = result;
  }

  // ----- Template-facing getters (wire-getter pattern) -----

  get rows() {
    const data = this.wiredResult?.data;
    if (!Array.isArray(data)) {
      return [];
    }
    return data.map((r) => ({
      ...r,
      id: r.touchId,
      statusClass: this.statusClass(r.resolutionStatus)
    }));
  }

  get error() {
    return this.wiredResult?.error;
  }

  get hasError() {
    return !!this.error;
  }

  get errorMessage() {
    const e = this.error;
    return (e && e.body && e.body.message) || "Unable to load touches.";
  }

  get isLoading() {
    const w = this.wiredResult;
    return !!w && w.data === undefined && w.error === undefined;
  }

  get hasData() {
    return !this.isLoading && !this.hasError;
  }

  get isEmpty() {
    return this.hasData && this.rows.length === 0;
  }

  get countLabel() {
    return `${this.rows.length} touch${this.rows.length === 1 ? "" : "es"} pending review`;
  }

  statusClass(status) {
    switch (status) {
      case "NoMatch":
        return "slds-text-color_error";
      case "Ambiguous":
        return "slds-text-color_warning";
      default:
        return "slds-text-color_default";
    }
  }

  // ----- Row action handlers -----

  async handleRowAction(event) {
    const action = event.detail.action.name;
    const row = event.detail.row;
    if (!row || !row.touchId) {
      return;
    }
    if (action === "retry") {
      await this.runRetry(row);
    } else if (action === "ignore") {
      await this.runIgnore(row);
    }
  }

  async runRetry(row) {
    this.isBusy = true;
    try {
      const result = await retryResolution({ touchId: row.touchId });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Retry complete",
          message: `${row.touchName}: ${result.resolutionStatus}`,
          variant: result.resolutionStatus === "Resolved" ? "success" : "info"
        })
      );
      await refreshApex(this.wiredResult);
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Retry failed",
          message:
            (e && e.body && e.body.message) || "Unable to retry resolution.",
          variant: "error"
        })
      );
    } finally {
      this.isBusy = false;
    }
  }

  async runIgnore(row) {
    this.isBusy = true;
    try {
      await ignoreTouch({
        touchId: row.touchId,
        reason: IGNORE_REASON_DEFAULT
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Touch ignored",
          message: `${row.touchName} archived.`,
          variant: "success"
        })
      );
      await refreshApex(this.wiredResult);
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Ignore failed",
          message:
            (e && e.body && e.body.message) || "Unable to ignore this touch.",
          variant: "error"
        })
      );
    } finally {
      this.isBusy = false;
    }
  }
}
