@IsTest
private class IntentClassifierQueueableTest {

    @IsTest
    static void triggerEnqueuesAndClassifies() {
        Test.startTest();
        MedicalInsight mi = TestDataFactory.insight(
            'HCP asks about trial site availability',
            'Trial enrollment question; eligibility unclear'
        );
        insert mi;
        Test.stopTest();

        MedicalInsight updated = [
            SELECT Intent_Classification__c FROM MedicalInsight WHERE Id = :mi.Id
        ];
        System.assertEquals('Trial Access Barrier', updated.Intent_Classification__c);
    }

    @IsTest
    static void skipsAlreadyClassified() {
        MedicalInsight mi = TestDataFactory.insight(
            'Already classified',
            'Dosing question',
            'Efficacy Question'
        );
        insert mi;

        Test.startTest();
        mi.Content = 'Dosing question updated';
        update mi;
        Test.stopTest();

        MedicalInsight after = [SELECT Intent_Classification__c FROM MedicalInsight WHERE Id = :mi.Id];
        System.assertEquals('Efficacy Question', after.Intent_Classification__c,
            'Should not re-classify records that already have an intent');
    }
}
