/**
 * @description Admin tool — surfaces `Touch_Routing_Rule__mdt` next to the
 *              signal volume each match path has produced in the last 30
 *              days. Rules at zero are highlighted so admins can spot
 *              potentially dead rules (mis-configured filters, bad
 *              priority order, or simply unused match paths).
 *
 *              Read-only wire — `cacheable=true`. To refresh after rule
 *              edits, the host page can re-mount the component.
 *
 * @author David Wood
 * @since May 2026
 */
import { LightningElement, wire } from "lwc";
import getRuleCoverage from "@salesforce/apex/EngagementAdminController.getRuleCoverage";

const COLUMNS = [
  { label: "Rule", fieldName: "ruleLabel", wrapText: true },
  {
    label: "Priority",
    fieldName: "priority",
    type: "number",
    initialWidth: 100
  },
  { label: "Match Path", fieldName: "matchPath", initialWidth: 140 },
  {
    label: "Target Confidence",
    fieldName: "targetConfidence",
    type: "number",
    initialWidth: 160
  },
  {
    label: "Signals (30d)",
    fieldName: "signalsLast30Days",
    type: "number",
    cellAttributes: {
      class: { fieldName: "rowClass" }
    },
    initialWidth: 140
  },
  { label: "Active", fieldName: "isActive", type: "boolean", initialWidth: 100 }
];

export default class EngagementRuleCoverage extends LightningElement {
  wiredResult;
  columns = COLUMNS;

  @wire(getRuleCoverage)
  wired(result) {
    this.wiredResult = result;
  }

  // ----- Template-facing getters (wire-getter pattern) -----

  get rows() {
    const data = this.wiredResult?.data;
    if (!Array.isArray(data)) {
      return [];
    }
    return data.map((row) => ({
      ...row,
      key: row.ruleDeveloperName,
      // Visual indicator: zero-signal rules render in muted/error color
      // via the `rowClass` cell-attribute binding above.
      rowClass:
        row.signalsLast30Days === 0
          ? "slds-text-color_error slds-text-title_bold dead-rule"
          : "slds-text-color_default"
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
    return (e && e.body && e.body.message) || "Unable to load rule coverage.";
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

  get deadRuleCount() {
    return this.rows.filter((r) => r.signalsLast30Days === 0).length;
  }

  get hasDeadRules() {
    return this.deadRuleCount > 0;
  }

  get deadRuleBanner() {
    const n = this.deadRuleCount;
    return `${n} rule${n === 1 ? "" : "s"} produced zero signals in the last 30 days.`;
  }
}
