@IsTest
private class IntentInsightAnalyzerTest {

    @IsTest
    static void returnsEmptyWhenNoCandidates() {
        MedicalInsight mi = TestDataFactory.insight(
            'Trial question',
            'HCP asks about clinical trial enrollment and eligibility'
        );
        insert mi;

        Test.startTest();
        IntentInsightAnalyzer.PatternResult r = IntentInsightAnalyzer.analyzePattern(mi.Id);
        Test.stopTest();

        System.assertNotEquals(null, r);
        System.assertEquals(0, r.totalCount);
    }

    @IsTest
    static void returnsMessageForMissingInsight() {
        Test.startTest();
        IntentInsightAnalyzer.PatternResult r = IntentInsightAnalyzer.analyzePattern('1LR000000000000AAA');
        Test.stopTest();
        System.assertNotEquals(null, r);
        System.assertEquals('Insight not found', r.message);
    }

    @IsTest
    static void classifiesOnDemandWhenIntentBlank() {
        MedicalInsight mi = TestDataFactory.insight(
            'Safety report',
            'Serious adverse event observed with noticeable toxicity and infusion reaction'
        );
        insert mi;

        Test.startTest();
        IntentInsightAnalyzer.PatternResult r = IntentInsightAnalyzer.analyzePattern(mi.Id);
        Test.stopTest();

        System.assertEquals('Safety Signal', r.currentIntent);
    }

    @IsTest
    static void differentIntentsAreNotSimilar() {
        MedicalInsight trial = TestDataFactory.insight(
            'Trial enrollment barrier',
            'HCP asks about clinical trial site availability and eligibility inclusion criteria'
        );
        MedicalInsight safety = TestDataFactory.insight(
            'Safety concern',
            'Serious adverse event with hematologic toxicity and neutropenia requiring dose hold'
        );
        insert new List<MedicalInsight>{ trial, safety };
        IntentClassifier.classifyAndSave(trial.Id);
        IntentClassifier.classifyAndSave(safety.Id);

        Test.startTest();
        IntentInsightAnalyzer.PatternResult r = IntentInsightAnalyzer.analyzePattern(trial.Id);
        Test.stopTest();

        for (IntentInsightAnalyzer.SimilarInsight s : r.similarInsights) {
            System.assertNotEquals(safety.Id, s.insightId,
                'Different-intent insight must not appear in results');
        }
    }

    @IsTest
    static void matchesWhenSubtopicAndContentOverlap() {
        // Two insights in the same intent AND sharing site-availability + geographic-access
        MedicalInsight primary = TestDataFactory.insight(
            'Trial site availability question',
            'Physician says nearest enrolling trial site is 90 minutes travel distance ' +
            'asking about regional site availability and telemedicine options for the clinical trial'
        );
        MedicalInsight tightMatch = TestDataFactory.insight(
            'Regional trial site travel',
            'HCP reports patients face long travel distance to nearest trial site ' +
            'requesting regional site availability and telemedicine for clinical trial enrollment'
        );
        // Same intent but DIFFERENT sub-topic (eligibility, not site)
        MedicalInsight sameIntentLooseMatch = TestDataFactory.insight(
            'Eligibility criteria question',
            'Biomarker eligibility criteria for clinical trial inclusion prior therapy lines of therapy'
        );
        insert new List<MedicalInsight>{ primary, tightMatch, sameIntentLooseMatch };
        IntentClassifier.classifyAndSave(primary.Id);
        IntentClassifier.classifyAndSave(tightMatch.Id);
        IntentClassifier.classifyAndSave(sameIntentLooseMatch.Id);

        Test.startTest();
        IntentInsightAnalyzer.PatternResult r = IntentInsightAnalyzer.analyzePattern(primary.Id);
        Test.stopTest();

        System.assertEquals('Trial Access Barrier', r.currentIntent);
        System.assert(r.totalCount >= 1, 'Tight match must be included');
        System.assertEquals(tightMatch.Id, r.similarInsights[0].insightId,
            'Highest-scoring match must be the one with shared sub-topics + content overlap');
        System.assert(r.similarInsights[0].rationale.contains('Shared sub-topics'));
    }

    @IsTest
    static void subjectOverlapContributesToScore() {
        Subject parent = new Subject(Name = 'Test Area ' + Crypto.getRandomLong(), UsageType = 'MedicalInsight');
        insert parent;
        Subject child = new Subject(Name = 'Test Specific Cat ' + Crypto.getRandomLong(), ParentSubjectId = parent.Id, UsageType = 'MedicalInsight');
        insert child;

        MedicalInsight primary = TestDataFactory.insight(
            'Primary dosing question',
            'Dosing schedule for infusion administration every 2 weeks q2w cycle length'
        );
        MedicalInsight overlapper = TestDataFactory.insight(
            'Dosing follow-up question',
            'Administration infusion schedule every 2 weeks q2w cycle length'
        );
        insert new List<MedicalInsight>{ primary, overlapper };

        insert new List<SubjectAssignment>{
            new SubjectAssignment(Name = 'A', AssignmentId = primary.Id, SubjectId = child.Id),
            new SubjectAssignment(Name = 'B', AssignmentId = overlapper.Id, SubjectId = child.Id)
        };

        IntentClassifier.classifyAndSave(primary.Id);
        IntentClassifier.classifyAndSave(overlapper.Id);

        Test.startTest();
        IntentInsightAnalyzer.PatternResult r = IntentInsightAnalyzer.analyzePattern(primary.Id);
        Test.stopTest();

        System.assert(r.totalCount >= 1, 'Expected the matching insight to appear');
        Boolean rationaleMentionsSubject = false;
        for (IntentInsightAnalyzer.SimilarInsight s : r.similarInsights) {
            if (s.rationale != null && s.rationale.contains('Shared subjects')) {
                rationaleMentionsSubject = true;
                break;
            }
        }
        System.assert(rationaleMentionsSubject, 'Expected shared-subjects rationale');
    }
}
