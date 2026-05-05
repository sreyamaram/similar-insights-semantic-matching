@IsTest
private class IntentClassifierTest {

    @IsTest
    static void classifiesTrialAccessBarrier() {
        MedicalInsight mi = TestDataFactory.insight(
            'HCP asks about clinical trial enrollment',
            'Physician wants to know eligibility and inclusion criteria for the upcoming trial site.'
        );
        insert mi;

        Test.startTest();
        IntentClassifier.Classification c = IntentClassifier.classify(mi.Id);
        Test.stopTest();

        System.assertEquals('Trial Access Barrier', c.intent);
        System.assertEquals('rule-based', c.source);
        System.assert(c.confidence >= 0.55, 'confidence should scale with hits');
        System.assertNotEquals(null, c.rationale);
    }

    @IsTest
    static void classifiesPatientEducation() {
        MedicalInsight mi = TestDataFactory.insight(
            'Spanish-Speaking Patient Need',
            'Language barrier complicating treatment. Patient education materials and consent documents only available in English.'
        );
        insert mi;

        Test.startTest();
        IntentClassifier.Classification c = IntentClassifier.classify(mi.Id);
        Test.stopTest();

        System.assertEquals('Patient Education Gap', c.intent);
    }

    @IsTest
    static void classifiesReimbursement() {
        MedicalInsight mi = TestDataFactory.insight(
            'Insurance coverage issue',
            'Prior authorization denied. Payer requires additional documentation before reimbursement.'
        );
        insert mi;

        Test.startTest();
        IntentClassifier.Classification c = IntentClassifier.classify(mi.Id);
        Test.stopTest();

        System.assertEquals('Reimbursement or Access', c.intent);
    }

    @IsTest
    static void classifiesOtherWhenNoSignal() {
        MedicalInsight mi = TestDataFactory.insight(
            'Generic note',
            'Just checking in after last visit.'
        );
        insert mi;

        Test.startTest();
        IntentClassifier.Classification c = IntentClassifier.classify(mi.Id);
        Test.stopTest();

        System.assertEquals('Other', c.intent);
        System.assertEquals(0.40, c.confidence);
    }

    @IsTest
    static void classifyAndSaveWritesFields() {
        MedicalInsight mi = TestDataFactory.insight(
            'Adverse event report',
            'Patient experienced serious adverse reaction with noted toxicity.'
        );
        insert mi;

        Test.startTest();
        IntentClassifier.classifyAndSave(mi.Id);
        Test.stopTest();

        MedicalInsight updated = [
            SELECT Intent_Classification__c, Intent_Confidence__c, Intent_Rationale__c, Intent_Classified_At__c
            FROM MedicalInsight WHERE Id = :mi.Id
        ];
        System.assertEquals('Safety Signal', updated.Intent_Classification__c);
        System.assertNotEquals(null, updated.Intent_Confidence__c);
        System.assertNotEquals(null, updated.Intent_Classified_At__c);
    }

    @IsTest
    static void flowInvocableUsesProvidedValues() {
        MedicalInsight mi = TestDataFactory.insight('Whatever', 'Whatever');
        insert mi;

        IntentClassifier.ClassifyRequest r = new IntentClassifier.ClassifyRequest();
        r.insightId = mi.Id;
        r.intent = 'Efficacy Question';
        r.confidence = 0.92;
        r.rationale = 'Einstein said so';
        r.subtopicsCsv = 'survival-data,response-rates';

        Test.startTest();
        IntentClassifier.classifyAndSaveFromFlow(new List<IntentClassifier.ClassifyRequest>{ r });
        Test.stopTest();

        MedicalInsight updated = [
            SELECT Intent_Classification__c, Intent_Confidence__c, Intent_Rationale__c, Intent_Subtopics__c
            FROM MedicalInsight WHERE Id = :mi.Id
        ];
        System.assertEquals('Efficacy Question', updated.Intent_Classification__c);
        System.assertEquals(0.92, updated.Intent_Confidence__c);
        System.assertEquals('Einstein said so', updated.Intent_Rationale__c);
        System.assertEquals('survival-data,response-rates', updated.Intent_Subtopics__c);
    }

    @IsTest
    static void flowInvocableFallsBackWhenIntentBlank() {
        MedicalInsight mi = TestDataFactory.insight(
            'Off-label ask',
            'HCP asking about off-label indication'
        );
        insert mi;

        IntentClassifier.ClassifyRequest r = new IntentClassifier.ClassifyRequest();
        r.insightId = mi.Id;

        Test.startTest();
        IntentClassifier.classifyAndSaveFromFlow(new List<IntentClassifier.ClassifyRequest>{ r });
        Test.stopTest();

        MedicalInsight updated = [
            SELECT Intent_Classification__c FROM MedicalInsight WHERE Id = :mi.Id
        ];
        System.assertEquals('Off-Label Information Request', updated.Intent_Classification__c);
    }
}
