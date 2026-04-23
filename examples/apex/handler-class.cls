/**
 * AccountTriggerHandler
 *
 * Handles all trigger logic for the Account object.
 * Called from AccountTrigger — the trigger itself has zero logic.
 *
 * Pattern:
 *   - run() routes to the correct handler method based on trigger context
 *   - Each handler method is focused on one execution context
 *   - All queries are bulkified — no SOQL or DML inside loops
 *   - Helper methods are private and named descriptively
 */
public class AccountTriggerHandler {

    public void run() {
        if (Trigger.isBefore) {
            if (Trigger.isInsert) {
                beforeInsert((List<Account>) Trigger.new);
            }
            if (Trigger.isUpdate) {
                beforeUpdate(
                    (List<Account>) Trigger.new,
                    (Map<Id, Account>) Trigger.oldMap
                );
            }
            if (Trigger.isDelete) {
                beforeDelete((List<Account>) Trigger.old);
            }
        }

        if (Trigger.isAfter) {
            if (Trigger.isInsert) {
                afterInsert((List<Account>) Trigger.new);
            }
            if (Trigger.isUpdate) {
                afterUpdate(
                    (List<Account>) Trigger.new,
                    (Map<Id, Account>) Trigger.oldMap
                );
            }
            if (Trigger.isDelete) {
                afterDelete((List<Account>) Trigger.old);
            }
        }
    }

    // ─── BEFORE ──────────────────────────────────────────────

    private void beforeInsert(List<Account> newAccounts) {
        setDefaultValues(newAccounts);
    }

    private void beforeUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        // Example: normalize website URL on change
        for (Account acc : newAccounts) {
            Account old = oldMap.get(acc.Id);
            if (acc.Website != old.Website && acc.Website != null) {
                acc.Website = acc.Website.toLowerCase().trim();
            }
        }
    }

    private void beforeDelete(List<Account> oldAccounts) {
        // Example: prevent deletion of accounts with open opportunities
        Set<Id> accountIds = new Map<Id, Account>(oldAccounts).keySet();

        Set<Id> accountsWithOpenOpps = new Set<Id>();
        for (Opportunity opp : [
            SELECT AccountId
            FROM Opportunity
            WHERE AccountId IN :accountIds
              AND IsClosed = false
            LIMIT 50000
        ]) {
            accountsWithOpenOpps.add(opp.AccountId);
        }

        for (Account acc : oldAccounts) {
            if (accountsWithOpenOpps.contains(acc.Id)) {
                acc.addError('Cannot delete an account with open opportunities.');
            }
        }
    }

    // ─── AFTER ───────────────────────────────────────────────

    private void afterInsert(List<Account> newAccounts) {
        // Example: create a default Contact for new accounts
        List<Contact> defaultContacts = new List<Contact>();
        for (Account acc : newAccounts) {
            defaultContacts.add(new Contact(
                AccountId = acc.Id,
                LastName = 'Primary Contact',
                Email = acc.Website != null
                    ? 'info@' + acc.Website.replace('http://', '').replace('https://', '')
                    : null
            ));
        }
        if (!defaultContacts.isEmpty()) {
            insert defaultContacts;
        }
    }

    private void afterUpdate(List<Account> newAccounts, Map<Id, Account> oldMap) {
        // Example: sync owner change to child contacts
        List<Contact> contactsToUpdate = new List<Contact>();
        Set<Id> ownerChangedIds = new Set<Id>();

        for (Account acc : newAccounts) {
            if (acc.OwnerId != oldMap.get(acc.Id).OwnerId) {
                ownerChangedIds.add(acc.Id);
            }
        }

        if (!ownerChangedIds.isEmpty()) {
            Map<Id, Account> changedAccounts = new Map<Id, Account>();
            for (Account acc : newAccounts) {
                if (ownerChangedIds.contains(acc.Id)) {
                    changedAccounts.put(acc.Id, acc);
                }
            }

            for (Contact c : [
                SELECT Id, AccountId FROM Contact WHERE AccountId IN :ownerChangedIds
            ]) {
                contactsToUpdate.add(new Contact(
                    Id = c.Id,
                    OwnerId = changedAccounts.get(c.AccountId).OwnerId
                ));
            }

            if (!contactsToUpdate.isEmpty()) {
                update contactsToUpdate;
            }
        }
    }

    private void afterDelete(List<Account> oldAccounts) {
        // Clean up related records or log deletions if needed
    }

    // ─── HELPERS ─────────────────────────────────────────────

    private void setDefaultValues(List<Account> accounts) {
        for (Account acc : accounts) {
            if (acc.Industry == null) {
                acc.Industry = 'Other';
            }
            if (acc.Rating == null) {
                acc.Rating = 'Cold';
            }
        }
    }
}
