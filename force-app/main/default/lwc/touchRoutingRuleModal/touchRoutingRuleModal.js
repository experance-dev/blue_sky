/**
 * @description LightningModal for creating or editing a
 *              `Touch_Routing_Rule__mdt` row from the Engagement Admin
 *              Console's Rule Coverage view. Two modes:
 *
 *              - Create — opens with a blank form; submit calls
 *                `EngagementAdminController.createTouchRoutingRule(payload)`.
 *              - Edit — opens with `developerName` + `existingRule`
 *                pre-populated; `DeveloperName` is immutable; submit calls
 *                `EngagementAdminController.updateTouchRoutingRule(...)`.
 *
 *              Mode is determined by whether `developerName` was supplied on
 *              `LightningModal.open(...)`. Same component, two flows —
 *              mirrors the `c-add-to-deal-team-modal` pattern.
 *
 *              The host (currently `c-engagement-rule-coverage`) is
 *              responsible for `refreshApex(...)` on the wiredCoverage
 *              result after this modal resolves with `created` / `updated`.
 *
 *              CMDT deploys are async — `createTouchRoutingRule` and
 *              `updateTouchRoutingRule` return a deploy job Id immediately.
 *              The modal closes on submit success; the host's refresh runs
 *              when the host chooses (typically debounced ~3-5s).
 *
 *              Close payloads:
 *                `{ result: 'created',   developerName, deployJobId }`
 *                `{ result: 'updated',   developerName, deployJobId }`
 *                `{ result: 'cancelled' }`
 *
 * @group Engagement Attribution
 * @author David Wood
 * @since May 2026
 */
import LightningModal from "lightning/modal";
import { api } from "lwc";
import createTouchRoutingRule from "@salesforce/apex/EngagementAdminController.createTouchRoutingRule";
import updateTouchRoutingRule from "@salesforce/apex/EngagementAdminController.updateTouchRoutingRule";

const MODE_EDIT = "edit";

const INTENT_LEVEL_OPTIONS = Object.freeze([
  { label: "— Any —", value: "" },
  { label: "Low", value: "Low" },
  { label: "Medium", value: "Medium" },
  { label: "High", value: "High" }
]);

// Stored on the CMDT row as a semicolon-joined string. The dual-listbox
// hands us a JS array — we join on submit, split on load.
const TOUCH_TYPE_OPTIONS = Object.freeze([
  { label: "Page", value: "Page" },
  { label: "Download", value: "Download" },
  { label: "Webinar", value: "Webinar" },
  { label: "Form", value: "Form" },
  { label: "Event", value: "Event" }
]);

const DEV_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]{0,39}$/;
const GENERIC_FAILURE =
  "Unable to save the rule. Try again or check the Engagement logs.";

export default class TouchRoutingRuleModal extends LightningModal {
  /**
   * @description `"create"` (default) or `"edit"`. In edit mode the modal
   *              expects `developerName` + `existingRule` to be provided.
   *              The modal accepts `mode` for explicit callers, but also
   *              treats a non-blank `developerName` as edit-mode.
   */
  @api mode;

  /**
   * @description CMDT `DeveloperName` of the row being edited. Required in
   *              edit mode. Immutable in the UI (the DeveloperName field is
   *              read-only when this prop is set).
   */
  @api developerName;

  /**
   * @description Pre-populating data for edit mode. Shape mirrors the
   *              `RuleCoverage` DTO returned by `getRuleCoverage`, plus the
   *              full set of editable fields. Missing properties default
   *              to blank/false.
   */
  @api existingRule;

  // ----- Form state -----

  formDeveloperName = "";
  formMasterLabel = "";
  formDescription = "";
  formMatchPath = "";
  formConfidence;
  formPriority;
  formActive = true;
  formRequireSameAccount = false;
  formRequireTopicMatch = false;
  formMinIntentLevel = "";
  formPersonaFilter = "";
  formTouchTypeFilter = []; // array; semicolon-joined on submit

  isSaving = false;
  errorMessage;

  // ----- Lifecycle -----

  connectedCallback() {
    if (this.isEditMode) {
      this.hydrateFromExistingRule();
    }
  }

  // ----- Mode / option getters -----

  get isEditMode() {
    return (
      this.mode === MODE_EDIT ||
      (typeof this.developerName === "string" &&
        this.developerName.trim().length > 0)
    );
  }

  get isCreateMode() {
    return !this.isEditMode;
  }

  get modalHeaderLabel() {
    return this.isEditMode ? "Edit Routing Rule" : "New Routing Rule";
  }

  get submitButtonLabel() {
    return this.isEditMode ? "Save Changes" : "Create Rule";
  }

  get developerNameIsReadOnly() {
    // DeveloperName is immutable on CMDT — locked in edit mode.
    return this.isEditMode;
  }

  get intentLevelOptions() {
    return INTENT_LEVEL_OPTIONS;
  }

  get touchTypeOptions() {
    return TOUCH_TYPE_OPTIONS;
  }

  // ----- Hydration (edit mode) -----

  hydrateFromExistingRule() {
    const r = this.existingRule || {};
    this.formDeveloperName = this.developerName || r.ruleDeveloperName || "";
    this.formMasterLabel = r.ruleLabel ?? r.masterLabel ?? "";
    this.formDescription = r.description ?? "";
    this.formMatchPath = r.matchPath ?? "";
    this.formConfidence =
      r.targetConfidence !== undefined && r.targetConfidence !== null
        ? Number(r.targetConfidence)
        : r.confidence !== undefined && r.confidence !== null
          ? Number(r.confidence)
          : undefined;
    this.formPriority =
      r.priority !== undefined && r.priority !== null
        ? Number(r.priority)
        : undefined;
    this.formActive = r.isActive ?? r.active ?? true;
    this.formRequireSameAccount = r.requireSameAccount ?? false;
    this.formRequireTopicMatch = r.requireTopicMatch ?? false;
    this.formMinIntentLevel = r.minIntentLevel ?? "";
    this.formPersonaFilter = r.personaFilter ?? "";
    this.formTouchTypeFilter = this.splitTouchTypeFilter(r.touchTypeFilter);
  }

  splitTouchTypeFilter(raw) {
    if (!raw) return [];
    if (Array.isArray(raw)) return raw.filter((v) => !!v);
    return String(raw)
      .split(";")
      .map((v) => v.trim())
      .filter((v) => v.length > 0);
  }

  // ----- Field change handlers -----

  handleDeveloperNameChange(event) {
    this.formDeveloperName = event.target.value;
  }

  handleMasterLabelChange(event) {
    this.formMasterLabel = event.target.value;
  }

  handleDescriptionChange(event) {
    this.formDescription = event.target.value;
  }

  handleMatchPathChange(event) {
    this.formMatchPath = event.target.value;
  }

  handleConfidenceChange(event) {
    const v = event.target.value;
    this.formConfidence = v === "" || v === null ? undefined : Number(v);
  }

  handlePriorityChange(event) {
    const v = event.target.value;
    this.formPriority = v === "" || v === null ? undefined : Number(v);
  }

  handleActiveChange(event) {
    this.formActive = event.target.checked;
  }

  handleRequireSameAccountChange(event) {
    this.formRequireSameAccount = event.target.checked;
  }

  handleRequireTopicMatchChange(event) {
    this.formRequireTopicMatch = event.target.checked;
  }

  handleMinIntentLevelChange(event) {
    this.formMinIntentLevel = event.detail.value;
  }

  handlePersonaFilterChange(event) {
    this.formPersonaFilter = event.target.value;
  }

  handleTouchTypeFilterChange(event) {
    // lightning-dual-listbox fires { detail: { value: [...] } }.
    this.formTouchTypeFilter = Array.isArray(event.detail?.value)
      ? event.detail.value.slice()
      : [];
  }

  // ----- Validation -----

  /**
   * @description Validates the form against CMDT field constraints. Returns
   *              a user-facing error message on the first failure, or
   *              `undefined` when the form is submittable. Mirrors the
   *              server-side validation in `EngagementAdminController` so
   *              users see the failure before round-tripping to Apex.
   */
  validate() {
    if (this.isCreateMode) {
      if (!this.formDeveloperName || this.formDeveloperName.trim() === "") {
        return "Developer Name is required.";
      }
      if (!DEV_NAME_PATTERN.test(this.formDeveloperName)) {
        return "Developer Name must start with a letter and contain only letters, numbers, and underscores (max 40 chars).";
      }
    }
    if (!this.formMasterLabel || this.formMasterLabel.trim() === "") {
      return "Label is required.";
    }
    if (this.formMasterLabel.length > 80) {
      return "Label must be 80 characters or fewer.";
    }
    if (this.formDescription && this.formDescription.length > 255) {
      return "Description must be 255 characters or fewer.";
    }
    if (!this.formMatchPath || this.formMatchPath.trim() === "") {
      return "Match Path is required.";
    }
    if (this.formMatchPath.length > 80) {
      return "Match Path must be 80 characters or fewer.";
    }
    if (
      this.formConfidence === undefined ||
      this.formConfidence === null ||
      Number.isNaN(this.formConfidence)
    ) {
      return "Confidence is required.";
    }
    if (this.formConfidence < 0 || this.formConfidence > 100) {
      return "Confidence must be between 0 and 100.";
    }
    if (!Number.isInteger(this.formConfidence)) {
      return "Confidence must be a whole number.";
    }
    if (
      this.formPriority === undefined ||
      this.formPriority === null ||
      Number.isNaN(this.formPriority)
    ) {
      return "Priority is required.";
    }
    if (!Number.isInteger(this.formPriority) || this.formPriority < 1) {
      return "Priority must be a whole number ≥ 1.";
    }
    if (this.formPersonaFilter && this.formPersonaFilter.length > 80) {
      return "Persona Filter must be 80 characters or fewer.";
    }
    return undefined;
  }

  // ----- Submit / cancel -----

  /**
   * @description Assembles the JSON payload that Apex receives as
   *              `Map<String, Object>`. In create mode the payload includes
   *              `developerName`; in edit mode `developerName` is passed
   *              alongside as a separate top-level parameter and the
   *              payload carries only mutable fields.
   */
  buildPayload() {
    const base = {
      masterLabel: this.formMasterLabel,
      description: this.formDescription || null,
      matchPath: this.formMatchPath,
      confidence: this.formConfidence,
      priority: this.formPriority,
      active: !!this.formActive,
      requireSameAccount: !!this.formRequireSameAccount,
      requireTopicMatch: !!this.formRequireTopicMatch,
      minIntentLevel: this.formMinIntentLevel || null,
      personaFilter: this.formPersonaFilter || null,
      touchTypeFilter:
        Array.isArray(this.formTouchTypeFilter) &&
        this.formTouchTypeFilter.length > 0
          ? this.formTouchTypeFilter.join(";")
          : null
    };
    if (this.isCreateMode) {
      base.developerName = this.formDeveloperName;
    }
    return base;
  }

  handleCancel() {
    this.close({ result: "cancelled" });
  }

  async handleSubmit() {
    const validationError = this.validate();
    if (validationError) {
      this.errorMessage = validationError;
      return;
    }
    this.errorMessage = undefined;
    this.isSaving = true;
    try {
      const payload = this.buildPayload();
      let deployJobId;
      let developerName;
      if (this.isEditMode) {
        developerName = this.developerName;
        deployJobId = await updateTouchRoutingRule({
          developerName: this.developerName,
          payload
        });
        this.close({
          result: "updated",
          developerName,
          deployJobId
        });
      } else {
        developerName = this.formDeveloperName;
        deployJobId = await createTouchRoutingRule({ payload });
        this.close({
          result: "created",
          developerName,
          deployJobId
        });
      }
    } catch (e) {
      this.errorMessage = (e && e.body && e.body.message) || GENERIC_FAILURE;
    } finally {
      this.isSaving = false;
    }
  }
}
