/**
 * @description One-line trigger on Contact. Delegates to
 *              `ContactEngagementErasureHandler`, which extends the project's
 *              `TriggerHandler` framework. Fires `before delete` so the
 *              cascade can remove dependent Engagement Attribution rows
 *              before the platform clears their foreign-key references.
 *              No business logic in the trigger body itself.
 */
trigger ContactTrigger on Contact(before delete) {
  TriggerHandler.initialiseHandler(ContactEngagementErasureHandler.class);
}
