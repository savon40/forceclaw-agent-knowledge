/**
 * INVOCABLE APEX example for an Agentforce action (target "apex://OpenCaseLookup").
 *
 * Pattern:
 *  - exactly one @InvocableMethod, bulk-safe (one query for all requests)
 *  - every @InvocableVariable has a label AND a description — the agent reads them
 *  - errors are RETURNED in the result (success=false + errorMessage), never thrown,
 *    so the agent can explain the failure instead of hitting a generic error
 *  - nested wrapper list → Agent Script output type list[object] with
 *    complex_data_type_name "@apexClassType/c__OpenCaseLookup$CaseInfo"
 */
public with sharing class OpenCaseLookup {

    public class Request {
        @InvocableVariable(required=true label='Account Id' description='Id of the Account to find open cases for.')
        public Id accountId;
    }

    public class CaseInfo {
        @InvocableVariable(label='Case Id' description='Case record Id.')
        public Id caseId;
        @InvocableVariable(label='Case Number' description='Case number shown to users.')
        public String caseNumber;
        @InvocableVariable(label='Subject' description='Case subject.')
        public String subject;
        @InvocableVariable(label='Status' description='Current case status.')
        public String status;
        @InvocableVariable(label='Priority' description='Case priority.')
        public String priority;
    }

    public class Result {
        @InvocableVariable(label='Cases' description='Open cases for the account, newest first (max 10). Empty when there are none or the lookup failed.')
        public List<CaseInfo> cases;
        @InvocableVariable(label='Success' description='True when the lookup ran; false when it failed (see Error Message).')
        public Boolean success;
        @InvocableVariable(label='Error Message' description='Why the lookup failed. Empty on success.')
        public String errorMessage;
    }

    @InvocableMethod(
        label='Get Open Cases for Account'
        description='Returns up to 10 open cases for an account, newest first. Failures are returned in the result (Success=false) rather than thrown.'
        category='Service'
    )
    public static List<Result> getOpenCases(List<Request> requests) {
        Set<Id> accountIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.accountId != null) {
                accountIds.add(req.accountId);
            }
        }

        Map<Id, List<CaseInfo>> casesByAccount = new Map<Id, List<CaseInfo>>();
        String queryError;
        try {
            for (Case c : [
                SELECT Id, CaseNumber, Subject, Status, Priority, AccountId
                FROM Case
                WHERE AccountId IN :accountIds AND IsClosed = false
                ORDER BY CreatedDate DESC
                LIMIT 1000
            ]) {
                List<CaseInfo> forAccount = casesByAccount.get(c.AccountId);
                if (forAccount == null) {
                    forAccount = new List<CaseInfo>();
                    casesByAccount.put(c.AccountId, forAccount);
                }
                if (forAccount.size() < 10) {
                    CaseInfo info = new CaseInfo();
                    info.caseId = c.Id;
                    info.caseNumber = c.CaseNumber;
                    info.subject = c.Subject;
                    info.status = c.Status;
                    info.priority = c.Priority;
                    forAccount.add(info);
                }
            }
        } catch (Exception e) {
            queryError = e.getTypeName() + ': ' + e.getMessage();
        }

        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result res = new Result();
            res.cases = new List<CaseInfo>();
            if (req == null || req.accountId == null) {
                res.success = false;
                res.errorMessage = 'No Account Id was provided.';
            } else if (queryError != null) {
                res.success = false;
                res.errorMessage = queryError;
            } else {
                res.success = true;
                if (casesByAccount.containsKey(req.accountId)) {
                    res.cases = casesByAccount.get(req.accountId);
                }
            }
            results.add(res);
        }
        return results;
    }
}
