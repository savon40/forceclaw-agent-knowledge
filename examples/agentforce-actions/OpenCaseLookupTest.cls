@IsTest
private class OpenCaseLookupTest {

    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Open Case Lookup Test');
        insert acct;
        insert new List<Case>{
            new Case(AccountId = acct.Id, Subject = 'Open one', Status = 'New'),
            new Case(AccountId = acct.Id, Subject = 'Open two', Status = 'New')
        };
    }

    @IsTest
    static void returnsOpenCasesForAccount() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Open Case Lookup Test' LIMIT 1];
        OpenCaseLookup.Request req = new OpenCaseLookup.Request();
        req.accountId = acct.Id;

        Test.startTest();
        List<OpenCaseLookup.Result> results = OpenCaseLookup.getOpenCases(new List<OpenCaseLookup.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(2, results[0].cases.size());
    }

    @IsTest
    static void returnsErrorWhenAccountIdMissing() {
        List<OpenCaseLookup.Result> results = OpenCaseLookup.getOpenCases(new List<OpenCaseLookup.Request>{ new OpenCaseLookup.Request() });

        System.assertEquals(false, results[0].success);
        System.assertEquals('No Account Id was provided.', results[0].errorMessage);
        System.assertEquals(0, results[0].cases.size());
    }
}
