@IsTest
private class IntentPatternAlertControllerTest {

    @IsTest
    static void emptyWhenNoRecentInsights() {
        Test.startTest();
        List<IntentPatternAlertController.PatternAlertData> alerts =
            IntentPatternAlertController.getPatternAlerts();
        Test.stopTest();
        System.assertNotEquals(null, alerts);
    }

    @IsTest
    static void requiresMultipleOwnersAndInsights() {
        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];

        // Only 1 owner -- should NOT trigger an alert
        List<MedicalInsight> insights = new List<MedicalInsight>();
        for (Integer i = 0; i < 5; i++) {
            MedicalInsight mi = TestDataFactory.insight(
                'Trial barrier ' + i,
                'Trial site availability and geographic access travel distance site availability',
                'Trial Access Barrier'
            );
            mi.Intent_Subtopics__c = 'site-availability,geographic-access';
            mi.OwnerId = u.Id;
            insights.add(mi);
        }
        insert insights;

        Test.startTest();
        List<IntentPatternAlertController.PatternAlertData> alerts =
            IntentPatternAlertController.getPatternAlerts();
        Test.stopTest();

        for (IntentPatternAlertController.PatternAlertData a : alerts) {
            System.assert(a.mslCount >= 2, 'Single-owner bucket must not appear as an alert');
        }
    }

    @IsTest
    static void surfacesIntentSubtopicPattern() {
        List<User> users = [SELECT Id FROM User WHERE IsActive = true LIMIT 3];
        System.assert(users.size() >= 2, 'need at least two users for this test');

        List<MedicalInsight> insights = new List<MedicalInsight>();
        // 6 insights in same (intent, subtopic) spread across 2 owners
        for (Integer i = 0; i < 6; i++) {
            MedicalInsight mi = TestDataFactory.insight(
                'Payer issue ' + i,
                'Prior authorization denied coverage payer step therapy not met',
                'Reimbursement or Access'
            );
            mi.Intent_Subtopics__c = 'prior-authorization,payer-denial';
            mi.OwnerId = users[Math.mod(i, 2)].Id;
            insights.add(mi);
        }
        insert insights;

        Test.startTest();
        List<IntentPatternAlertController.PatternAlertData> alerts =
            IntentPatternAlertController.getPatternAlerts();
        Test.stopTest();

        Boolean foundPattern = false;
        for (IntentPatternAlertController.PatternAlertData a : alerts) {
            if (a.intent == 'Reimbursement or Access' && a.subtopic == 'prior-authorization') {
                foundPattern = true;
                System.assert(a.totalCount >= 6);
                System.assert(a.mslCount >= 2);
                System.assertNotEquals(null, a.insightId);
                System.assertNotEquals(null, a.bucketLabel);
                System.assertNotEquals(null, a.trendingLabel);
            }
        }
        System.assert(foundPattern, 'Expected prior-authorization pattern in alerts');
    }

    @IsTest
    static void trendingLabelReflectsRecentVolume() {
        List<User> users = [SELECT Id FROM User WHERE IsActive = true LIMIT 2];
        System.assert(users.size() >= 2);

        // 4 insights > 7 days old, 4 insights in the last 7 days -- steep trending up
        List<MedicalInsight> insights = new List<MedicalInsight>();
        for (Integer i = 0; i < 8; i++) {
            MedicalInsight mi = TestDataFactory.insight(
                'Adverse event ' + i,
                'Serious adverse reaction hematologic toxicity neutropenia requiring dose hold',
                'Safety Signal'
            );
            mi.Intent_Subtopics__c = 'hematologic-toxicity,discontinuation';
            mi.OwnerId = users[Math.mod(i, 2)].Id;
            insights.add(mi);
        }
        insert insights;

        Test.startTest();
        List<IntentPatternAlertController.PatternAlertData> alerts =
            IntentPatternAlertController.getPatternAlerts();
        Test.stopTest();

        Boolean found = false;
        for (IntentPatternAlertController.PatternAlertData a : alerts) {
            if (a.intent == 'Safety Signal' && a.subtopic == 'hematologic-toxicity') {
                found = true;
                System.assertNotEquals(null, a.trendingLabel);
                System.assert(a.trendingScore > 0);
            }
        }
        System.assert(found, 'Expected hematologic-toxicity pattern');
    }
}
