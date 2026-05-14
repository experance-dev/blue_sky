/**
 * @description One-line trigger on Lead. Delegates to two handlers, both
 *              extending the project's `TriggerHandler` framework (see
 *              best-practices/architecture.md §Trigger framework):
 *                - `LeadEngagementReparentHandler` (after update) — reparents
 *                  touches when a Lead converts.
 *                - `LeadEngagementErasureHandler` (before delete) —
 *                  cascade-deletes engagement data for CCPA / GDPR subject
 *                  erasure.
 *              The framework dispatcher picks the right hook for the current
 *              event context, so both handlers are safe to instantiate on
 *              every trigger fire. No business logic in the trigger body.
 */
trigger LeadTrigger on Lead(after update, before delete) {
  TriggerHandler.initialiseHandler(LeadEngagementReparentHandler.class);
  TriggerHandler.initialiseHandler(LeadEngagementErasureHandler.class);
}
