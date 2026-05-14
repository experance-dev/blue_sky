/**
 * @description Right-rail "Engagement Intelligence" panel. Renders engaged
 *              Contacts for the current Account or Opportunity record page.
 *              Layout follows docs/wireframes/sales-console-{opportunity,account}.html.
 *
 *              Two parallel @wire adapters are declared (one per Apex method)
 *              so the platform LDS cache stays warm. Only the wire whose
 *              parameter id is non-null actually fires — see `opportunityIdParam`
 *              / `accountIdParam` reactive getters. This preserves cacheable=true
 *              semantics and lets `refreshApex` target the active wired result
 *              after a write.
 *
 *              On "+ Add" the panel opens `c/addToDealTeamModal` directly via
 *              LightningModal.open(); on a successful add it calls @api refresh
 *              to re-fire the active wire. A server-side race
 *              (payload.alreadyExists) chains into `c/alreadyAddedModal`.
 *              "View all" opens `c/engagementDetailModal`; if that modal closes
 *              with `result:'add-to-team'` the panel chains into the
 *              addToDealTeamModal flow.
 *
 *              Public events (preserved for external listeners / tests):
 *                - addtodealteam : { contactId, name, currentRole, isPrimary }
 *                - viewall       : { recordId, recordContext }
 *                - refresh       : {} (fired after a successful add)
 *
 * @author David Wood
 * @since May 2026
 */
import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getForOpportunity from "@salesforce/apex/EngagementController.getForOpportunity";
import getForAccount from "@salesforce/apex/EngagementController.getForAccount";
import dismissContact from "@salesforce/apex/EngagementController.dismissContact";
import AddToDealTeamModal from "c/addToDealTeamModal";
import AlreadyAddedModal from "c/alreadyAddedModal";
import EngagementDetailModal from "c/engagementDetailModal";

const CONTEXT_ACCOUNT = "Account";
const CONTEXT_OPPORTUNITY = "Opportunity";
const MAX_VISIBLE_TOPICS = 2;

/**
 * Build the multi-line tooltip body for a contact hotlink. SF's record
 * hovercard attaches automatically to the `/lightning/r/.../view` href —
 * the `title` attribute provides the lightweight fallback shown
 * immediately on hover (before the ~1s hovercard delay).
 */
function buildSummaryTooltip(dto) {
  const parts = [];
  const touchCount = dto.touchCount || 0;
  parts.push(`${touchCount} touch${touchCount === 1 ? "" : "es"}`);
  if (dto.topics && dto.topics.length > 0) {
    parts.push(`Topics: ${dto.topics.join(", ")}`);
  }
  if (dto.lastTouchAt) {
    parts.push(`Last touch: ${new Date(dto.lastTouchAt).toLocaleDateString()}`);
  }
  if (dto.onOcr) {
    parts.push(`On Deal Team (Role: ${dto.ocrRole || "—"})`);
  } else {
    parts.push("Not on Deal Team");
  }
  if (dto.isConsultant) {
    parts.push("Consultant");
  } else if (dto.isAcr) {
    parts.push("External contact (ACR)");
  }
  return parts.join("\n");
}

export default class EngagementPanel extends NavigationMixin(LightningElement) {
  @api recordId;
  @api recordContext = CONTEXT_OPPORTUNITY;
  @api recordName;

  wiredOppResult;
  wiredAccountResult;

  // ----- Reactive wire parameters -----
  // The non-active scope's param resolves to null so its wire short-circuits.

  get opportunityIdParam() {
    return this.recordContext === CONTEXT_OPPORTUNITY ? this.recordId : null;
  }

  get accountIdParam() {
    return this.recordContext === CONTEXT_ACCOUNT ? this.recordId : null;
  }

  // ----- Wire adapters -----

  @wire(getForOpportunity, { opportunityId: "$opportunityIdParam" })
  wiredOpportunity(result) {
    this.wiredOppResult = result;
  }

  @wire(getForAccount, { accountId: "$accountIdParam" })
  wiredAccount(result) {
    this.wiredAccountResult = result;
  }

  // ----- Template-facing getters (per best-practices/lwc.md wire-getter pattern) -----

  get activeWire() {
    return this.isOpportunityScope
      ? this.wiredOppResult
      : this.wiredAccountResult;
  }

  get engagements() {
    const data = this.activeWire?.data;
    if (!Array.isArray(data)) {
      return [];
    }
    return data.map((dto) => this.decorate(dto));
  }

  get error() {
    return this.activeWire?.error;
  }

  get isLoading() {
    const w = this.activeWire;
    // No reply yet: undefined data + undefined error => still loading.
    return !!w && w.data === undefined && w.error === undefined;
  }

  get hasError() {
    return !!this.error;
  }

  get hasData() {
    return !this.isLoading && !this.hasError;
  }

  get isEmpty() {
    return this.hasData && this.engagements.length === 0;
  }

  get isOpportunityScope() {
    return this.recordContext === CONTEXT_OPPORTUNITY;
  }

  get isAccountScope() {
    return this.recordContext === CONTEXT_ACCOUNT;
  }

  get dealTeam() {
    return this.engagements.filter((p) => p.onOcr === true);
  }

  get notOnDealTeam() {
    return this.engagements.filter((p) => p.onOcr !== true);
  }

  get dealTeamCount() {
    return this.dealTeam.length;
  }

  get notOnDealTeamCount() {
    return this.notOnDealTeam.length;
  }

  get totalCount() {
    return this.engagements.length;
  }

  get dealTeamSectionLabel() {
    return `Deal Team — ${this.dealTeamCount} on OCR`;
  }

  get notOnDealTeamSectionLabel() {
    return `Engaged — not on Deal Team · ${this.notOnDealTeamCount}`;
  }

  get countBadgeLabel() {
    return `${this.totalCount} engaged`;
  }

  // ----- Row decoration -----

  decorate(dto) {
    const topics = Array.isArray(dto.topics) ? dto.topics : [];
    const visibleTopics = topics.slice(0, MAX_VISIBLE_TOPICS);
    const hiddenTopicCount = Math.max(0, topics.length - MAX_VISIBLE_TOPICS);

    return {
      ...dto,
      key: dto.contactId,
      initials: this.initialsFor(dto.name),
      avatarClass: this.avatarClassFor(dto),
      visibleTopics: visibleTopics.map((t, idx) => ({
        key: `${dto.contactId}-topic-${idx}`,
        label: t
      })),
      hiddenTopicCount,
      hasHiddenTopics: hiddenTopicCount > 0,
      hiddenTopicsLabel: `+${hiddenTopicCount} more`,
      touchSummary: this.touchSummary(dto),
      showAddButton: dto.onOcr !== true && this.isOpportunityScope,
      showOnTeamBadge: dto.onOcr === true,
      ariaLabel: dto.name,
      contactUrl: `/lightning/r/Contact/${dto.contactId}/view`,
      summaryTooltip: buildSummaryTooltip(dto)
    };
  }

  initialsFor(name) {
    if (!name) {
      return "?";
    }
    const parts = name.trim().split(/\s+/);
    if (parts.length === 1) {
      return parts[0].charAt(0).toUpperCase();
    }
    return (
      parts[0].charAt(0) + parts[parts.length - 1].charAt(0)
    ).toUpperCase();
  }

  avatarClassFor(dto) {
    const base = "slds-avatar slds-avatar_circle slds-avatar_small";
    if (dto.isConsultant) {
      return `${base} av-consultant`;
    }
    if (dto.isAcr) {
      return `${base} av-acr`;
    }
    return base;
  }

  touchSummary(dto) {
    const count = dto.touchCount || 0;
    const label = count === 1 ? "1 touch" : `${count} touches`;
    return label;
  }

  // ----- Event handlers -----

  async handleAddClick(event) {
    const { contactId, name } = event.currentTarget.dataset;

    // Preserve existing event dispatch so external listeners (and tests)
    // can still observe the intent.
    this.dispatchEvent(
      new CustomEvent("addtodealteam", {
        detail: {
          contactId,
          name,
          currentRole: null,
          isPrimary: false
        },
        bubbles: true,
        composed: true
      })
    );

    // Open the role-picker modal directly. On Account scope opportunityId
    // is null — the modal renders its own Opportunity selector.
    const oppId = this.isOpportunityScope ? this.recordId : null;

    const result = await AddToDealTeamModal.open({
      size: "small",
      contactId,
      contactName: name,
      opportunityId: oppId,
      recordContext: this.recordContext
    });

    if (result && result.result === "success" && result.payload) {
      if (result.payload.alreadyExists) {
        // Server-side race — pop the AlreadyAddedModal.
        await AlreadyAddedModal.open({
          size: "small",
          contactName: name,
          addedByUserName: result.payload.addedByUserName,
          addedAt: result.payload.addedAt,
          ocrId: result.payload.ocrId,
          opportunityId: oppId
        });
      } else {
        // True save — refresh the panel data.
        await this.refresh();
      }
    }
  }

  async handleViewAll() {
    // Preserve existing event dispatch.
    this.dispatchEvent(
      new CustomEvent("viewall", {
        detail: {
          recordId: this.recordId,
          recordContext: this.recordContext
        },
        bubbles: true,
        composed: true
      })
    );

    const oppId = this.isOpportunityScope ? this.recordId : null;
    const result = await EngagementDetailModal.open({
      size: "medium",
      engagements: this.engagements,
      recordContext: this.recordContext,
      recordName: this.recordName || "",
      opportunityId: oppId
    });

    // Chain: if user clicked "+ Add" inside the detail modal, open
    // AddToDealTeamModal next.
    if (result && result.result === "add-to-team" && result.payload) {
      const addResult = await AddToDealTeamModal.open({
        size: "small",
        contactId: result.payload.contactId,
        contactName: result.payload.contactName,
        opportunityId: oppId,
        recordContext: this.recordContext
      });
      if (addResult && addResult.result === "success" && addResult.payload) {
        if (addResult.payload.alreadyExists) {
          await AlreadyAddedModal.open({
            size: "small",
            contactName: result.payload.contactName,
            addedByUserName: addResult.payload.addedByUserName,
            addedAt: addResult.payload.addedAt,
            ocrId: addResult.payload.ocrId,
            opportunityId: oppId
          });
        } else {
          await this.refresh();
        }
      }
    }
  }

  /**
   * Per-user dismissal of an engaged Contact for the current scope.
   * The server records a dismissal that filters this Contact out of
   * subsequent reads UNTIL a new Engagement_Touch__c arrives — then
   * the Contact re-appears automatically.
   */
  async handleDismissClick(event) {
    event.stopPropagation();
    const contactId = event.currentTarget.dataset.contactId;
    const contactName = event.currentTarget.dataset.contactName;
    const oppId = this.isOpportunityScope ? this.recordId : null;
    const acctId = this.isAccountScope ? this.recordId : null;
    try {
      await dismissContact({
        contactId,
        opportunityId: oppId,
        accountId: acctId
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Dismissed",
          message: `${contactName} hidden until a new touch arrives.`,
          variant: "success",
          mode: "dismissable"
        })
      );
      await this.refresh();
    } catch (e) {
      const msg =
        (e && e.body && e.body.message) || "Unable to dismiss. Try again.";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: msg,
          variant: "error"
        })
      );
    }
  }

  /**
   * Public entry-point for the host to call after a successful add.
   * Re-fires the active wire so the panel reflects the new OCR row.
   */
  @api
  async refresh() {
    const target = this.activeWire;
    if (target) {
      await refreshApex(target);
    }
    this.dispatchEvent(new CustomEvent("refresh"));
  }
}
