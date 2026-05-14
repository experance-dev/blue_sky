import { api } from "lwc";
import LightningModal from "lightning/modal";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import dismissContact from "@salesforce/apex/EngagementController.dismissContact";

/**
 * EngagementDetailModal
 *
 * Full-history "View all" modal opened from engagementPanel. Receives the
 * pre-fetched engagement list as a prop — does NOT call Apex itself for
 * reads. Writes (dismissContact) are imperative and update local state
 * optimistically.
 *
 * Public API
 *   @api engagements    List<EngagementDTO>
 *   @api recordContext  'Account' | 'Opportunity'
 *   @api recordName     Header label (e.g. 'United Healthcare')
 *   @api opportunityId  Pass-through for the Add-to-Team handoff
 *   @api accountId      Pass-through for Account-scope dismiss
 *
 * Close results
 *   { result: 'closed' }
 *   { result: 'add-to-team', payload: { contactId, contactName } }
 */
const TIMELINE_DOT_LIMIT = 100;
const DAY_MS = 24 * 60 * 60 * 1000;
const SIX_WEEKS_MS = 6 * 7 * DAY_MS;
const ONE_YEAR_MS = 365 * DAY_MS;

/**
 * Piecewise vertical scale for the buying-motion timeline:
 *   • Top half (0-50%): the last 6 weeks (weekly granularity)
 *   • Bottom half (50-100%): from 6 weeks ago to 1 year ago (monthly granularity)
 *   • Anything older than 1 year clamps to 100% (bottom).
 *
 * Returns the % from the top of the axis (0 = today, 100 = >=1 year ago).
 */
function timeAgoToPercent(msAgo) {
  if (msAgo <= 0) return 0;
  if (msAgo <= SIX_WEEKS_MS) {
    return (msAgo / SIX_WEEKS_MS) * 50;
  }
  if (msAgo >= ONE_YEAR_MS) return 100;
  const longRange = ONE_YEAR_MS - SIX_WEEKS_MS;
  return 50 + ((msAgo - SIX_WEEKS_MS) / longRange) * 50;
}
const PERSONA_COLOR = {
  Executive: "#2E75B6",
  Finance: "#16325c",
  Technical: "#28a745",
  Operational: "#fd7e14",
  Other: "#6c757d"
};

/**
 * Build the multi-line tooltip body shown on the `title` attribute of a
 * contact hotlink. Salesforce's record hovercard lights up separately
 * because the anchor's href matches the `/lightning/r/.../view` pattern.
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

export default class EngagementDetailModal extends LightningModal {
  @api engagements = [];
  @api recordContext;
  @api recordName;
  @api opportunityId;
  @api accountId;

  groupBy = "person";
  expandedRowKeys = new Set();
  focusedContactId = null;

  // ---- Header / toolbar -------------------------------------------------

  get modalLabel() {
    const name = this.recordName ? ` — ${this.recordName}` : "";
    return `Engagement Intelligence${name}`;
  }

  get groupByOptions() {
    return [
      { label: "Group by Person", value: "person" },
      { label: "Group by Campaign", value: "campaign" }
    ];
  }

  get isPersonGroup() {
    return this.groupBy === "person";
  }

  get peopleOrCampaignsLabel() {
    if (this.isPersonGroup) {
      return this.engagements.length === 1 ? "person" : "people";
    }
    return this.campaignGroups.length === 1 ? "campaign" : "campaigns";
  }

  get summaryCount() {
    return this.isPersonGroup
      ? this.engagements.length
      : this.campaignGroups.length;
  }

  // ---- Group derivation -------------------------------------------------

  get personGroups() {
    return this.engagements.map((e) => ({
      key: e.contactId,
      label: e.name,
      sublabel: e.title || "",
      count: e.touchCount,
      lastAt: e.lastTouchAt,
      isExpanded: this.expandedRowKeys.has(e.contactId),
      badges: this.computeBadges(e),
      assets: (e.assets || []).map((a, idx) => ({
        ...a,
        assetKey: `${e.contactId}::${a.assetName}::${idx}`
      })),
      contactId: e.contactId,
      contactName: e.name,
      onOcr: e.onOcr,
      iconName: "standard:contact",
      showAddButton: this.isPersonGroup && !e.onOcr,
      showDismissButton: this.isPersonGroup,
      isPerson: true,
      contactUrl: `/lightning/r/Contact/${e.contactId}/view`,
      summaryTooltip: buildSummaryTooltip(e)
    }));
  }

  get campaignGroups() {
    const byCampaign = new Map();
    this.engagements.forEach((e) => {
      (e.assets || []).forEach((a) => {
        const campaign = a.campaignName || "(No campaign)";
        if (!byCampaign.has(campaign)) {
          byCampaign.set(campaign, {
            key: campaign,
            label: campaign,
            assets: [],
            totalCount: 0,
            peopleSet: new Set()
          });
        }
        const bucket = byCampaign.get(campaign);
        bucket.assets.push({
          ...a,
          personName: e.name,
          assetKey: `${campaign}::${e.contactId}::${a.assetName}::${bucket.assets.length}`
        });
        bucket.totalCount += a.count || 1;
        bucket.peopleSet.add(e.name);
      });
    });
    return Array.from(byCampaign.values()).map((g) => ({
      key: g.key,
      label: g.label,
      sublabel: `${g.peopleSet.size} ${g.peopleSet.size === 1 ? "person" : "people"}, ${g.assets.length} assets`,
      count: g.totalCount,
      isExpanded: this.expandedRowKeys.has(g.key),
      assets: g.assets,
      badges: [],
      iconName: "standard:campaign",
      showAddButton: false,
      showDismissButton: false,
      onOcr: false,
      contactId: null,
      contactName: null,
      isPerson: false,
      contactUrl: null,
      summaryTooltip: null
    }));
  }

  get displayGroups() {
    return this.isPersonGroup ? this.personGroups : this.campaignGroups;
  }

  computeBadges(dto) {
    const badges = [];
    if (dto.onOcr) {
      badges.push({
        label: "✓ on team",
        cls: "slds-badge slds-theme_success slds-var-m-left_x-small"
      });
    }
    if (dto.isConsultant) {
      badges.push({
        label: "Consultant",
        cls: "slds-badge slds-theme_inverse slds-var-m-left_x-small"
      });
    } else if (dto.isAcr) {
      badges.push({
        label: "ACR",
        cls: "slds-badge slds-theme_inverse slds-var-m-left_x-small"
      });
    }
    return badges;
  }

  // ---- Event handlers ---------------------------------------------------

  handleGroupByChange(event) {
    this.groupBy = event.detail.value;
    this.expandedRowKeys = new Set();
    this.focusedContactId = null;
  }

  toggleRow(event) {
    const key = event.currentTarget.dataset.key;
    if (!key) return;
    if (this.expandedRowKeys.has(key)) {
      this.expandedRowKeys.delete(key);
    } else {
      this.expandedRowKeys.add(key);
    }
    // Reassign so the template re-renders — Set mutation is not reactive.
    this.expandedRowKeys = new Set(this.expandedRowKeys);

    // Sync the timeline focus: when a person row is expanded, the
    // timeline filters to that contact only; collapsing clears focus.
    // Campaign rows never set focus — their keys aren't contactIds.
    if (this.expandedRowKeys.has(key)) {
      this.focusedContactId = this.isPersonGroup ? key : null;
    } else {
      this.focusedContactId = null;
    }
  }

  handleRowKeyDown(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.toggleRow(event);
    }
  }

  handleAddToTeam(event) {
    // Stop the click from also toggling the row.
    event.stopPropagation();
    const contactId = event.currentTarget.dataset.contactId;
    const dto = this.engagements.find((e) => e.contactId === contactId);
    if (!dto) return;
    this.close({
      result: "add-to-team",
      payload: { contactId: dto.contactId, contactName: dto.name }
    });
  }

  handleClose() {
    this.close({ result: "closed" });
  }

  // ---- Stats strip ------------------------------------------------------

  /**
   * Aggregate roll-up rendered as the four-tile stats strip at the top
   * of the modal. Top topic is computed by summing each contact's
   * touchCount across the topics that contact engaged with — assets
   * don't carry topic so the engagement-level topics array is the
   * source of truth.
   */
  get stats() {
    const list = Array.isArray(this.engagements) ? this.engagements : [];
    const totalEngaged = list.length;
    const totalTouches = list.reduce((sum, e) => sum + (e.touchCount || 0), 0);
    const notOnDealTeam = list.filter((e) => !e.onOcr).length;

    const topicCounts = new Map();
    list.forEach((e) => {
      const topics = Array.isArray(e.topics) ? e.topics : [];
      const count = e.touchCount || 0;
      topics.forEach((t) => {
        topicCounts.set(t, (topicCounts.get(t) || 0) + count);
      });
    });

    let topTopic = "—";
    let topTopicCount = 0;
    topicCounts.forEach((c, t) => {
      if (c > topTopicCount) {
        topTopic = t;
        topTopicCount = c;
      }
    });

    const topTopicDisplay =
      topTopic.length > 20 ? `${topTopic.slice(0, 20)}…` : topTopic;
    const topTopicSubLabel =
      topTopicCount === 1 ? "1 touch" : `${topTopicCount} touches`;

    return {
      totalEngaged,
      totalTouches,
      notOnDealTeam,
      topTopic: topTopicDisplay,
      topTopicCount,
      topTopicSubLabel
    };
  }

  // ---- Buying-motion timeline ------------------------------------------

  get timelineTitle() {
    if (this.focusedContactId) {
      const dto = this.engagements.find(
        (e) => e.contactId === this.focusedContactId
      );
      return dto ? `${dto.name}'s buying motion` : "Buying motion";
    }
    return "Buying motion (all)";
  }

  get timelineContainerClass() {
    return this.focusedContactId
      ? "timeline-container timeline-container_focused"
      : "timeline-container";
  }

  // ---- Record hotlink (Account / Opportunity) --------------------------

  get recordUrl() {
    if (this.opportunityId) {
      return `/lightning/r/Opportunity/${this.opportunityId}/view`;
    }
    if (this.accountId) {
      return `/lightning/r/Account/${this.accountId}/view`;
    }
    return null;
  }

  get recordSummaryTooltip() {
    const total = this.engagements.length;
    const touches = this.engagements.reduce(
      (s, e) => s + (e.touchCount || 0),
      0
    );
    return `${total} engaged · ${touches} touches`;
  }

  /**
   * Flatten engagement assets into positioned dots over a 6-week axis.
   * Persona isn't carried in the DTO — fall back to 'Other' gray. Each
   * dot maps to one asset bucket (one row of `assets[]` per contact),
   * keyed by `lastAt`. Buckets with no `lastAt` are skipped (we have no
   * defensible position for them; placing at "today" would lie about
   * recency). Capped at 100 dots for render performance.
   */
  get timelineDots() {
    const now = Date.now();
    let list = Array.isArray(this.engagements) ? this.engagements : [];
    // When a person row is expanded, narrow the timeline to just that
    // contact's touches. `focusedContactId` is cleared on collapse and
    // on groupBy switch, so the unfiltered "everyone" path is the
    // default.
    if (this.focusedContactId) {
      list = list.filter((e) => e.contactId === this.focusedContactId);
    }

    const flat = [];
    list.forEach((e) => {
      const persona = e.persona || "Other";
      const color = PERSONA_COLOR[persona] || PERSONA_COLOR.Other;
      (e.assets || []).forEach((a, idx) => {
        const lastAt = a.lastAt ? new Date(a.lastAt).getTime() : null;
        if (!lastAt) {
          return;
        }
        const msAgo = Math.max(0, now - lastAt);
        const pct = timeAgoToPercent(msAgo);
        flat.push({
          key: `${e.contactId}-${idx}-${a.assetName}`,
          cls: "timeline-square",
          style: `top: ${pct.toFixed(2)}%; background:${color};`,
          tooltip: `${e.name} · ${a.assetName} · ${persona}`,
          persona,
          contactName: e.name,
          assetName: a.assetName,
          count: a.count || 1,
          date: a.lastAt
        });
      });
    });

    // Most-recent first so the 100-cap favors the freshest activity.
    flat.sort((a, b) => new Date(b.date) - new Date(a.date));
    return flat.slice(0, TIMELINE_DOT_LIMIT);
  }

  // ---- Per-row dismiss --------------------------------------------------

  /**
   * Per-user dismissal of an engaged Contact for the current scope.
   * Optimistically removes the row from local state; parent panel
   * picks up the persisted dismissal on its next refresh. Does NOT
   * close the modal.
   */
  async handleDismissRow(event) {
    event.stopPropagation();
    const contactId = event.currentTarget.dataset.contactId;
    const contactName = event.currentTarget.dataset.contactName;
    const isOpp = this.recordContext === "Opportunity";
    const oppId = isOpp ? this.opportunityId : null;
    const acctId = !isOpp ? this.accountId : null;
    try {
      await dismissContact({
        contactId,
        opportunityId: oppId,
        accountId: acctId
      });
      // eslint-disable-next-line @lwc/lwc/no-api-reassignments
      this.engagements = this.engagements.filter(
        (e) => e.contactId !== contactId
      );
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Dismissed",
          message: `${contactName} hidden until a new touch arrives.`,
          variant: "success",
          mode: "dismissable"
        })
      );
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
}
