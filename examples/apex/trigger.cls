/**
 * AccountTrigger
 *
 * One-trigger-per-object pattern: this trigger contains ZERO logic.
 * All work is delegated to AccountTriggerHandler.
 *
 * Register all events the handler needs. The handler's run() method
 * inspects Trigger context variables to route to the right method.
 */
trigger AccountTrigger on Account (
    before insert,
    before update,
    before delete,
    after insert,
    after update,
    after delete,
    after undelete
) {
    new AccountTriggerHandler().run();
}
