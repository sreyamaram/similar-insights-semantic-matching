/**
 * Classifies the semantic intent AND fine-grained sub-topics of a MedicalInsight.
 *
 * Two-tier taxonomy:
 *   - Intent = broad category (Trial Access Barrier, Safety Signal, etc.)
 *   - Subtopics = specific themes within that intent (site-availability, adverse-reaction, ...)
 *
 * The rule-based fallback ships with the package so it works in any org. Customers with
 * Einstein can wire a Flow through the classifyAndSaveFromFlow invocable to use the
 * bundled Prompt Template instead (richer output, same field shape).
 */
public with sharing class IntentClassifier {

    public class Classification {
        @AuraEnabled public String intent;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String rationale;
        @AuraEnabled public String source;
        @AuraEnabled public List<String> subtopics;
    }

    public class ClassifyRequest {
        @InvocableVariable(required=true) public Id insightId;
        @InvocableVariable public String intent;
        @InvocableVariable public Decimal confidence;
        @InvocableVariable public String rationale;
        @InvocableVariable public String subtopicsCsv;
    }

    @InvocableMethod(label='Classify Medical Insight Intent' description='Classifies a MedicalInsight and writes intent + subtopic fields. Pass intent/confidence/rationale/subtopicsCsv from a Prompt Template action, or leave blank to use the bundled rule-based classifier.')
    public static void classifyAndSaveFromFlow(List<ClassifyRequest> requests) {
        for (ClassifyRequest r : requests) {
            if (String.isNotBlank(r.intent)) {
                saveClassification(r.insightId, buildFromInputs(r));
            } else {
                saveClassification(r.insightId, classify(r.insightId));
            }
        }
    }

    @AuraEnabled
    public static Classification classifyForLWC(Id insightId) {
        return classify(insightId);
    }

    public static Classification classify(Id insightId) {
        MedicalInsight mi = [
            SELECT Id, Name, Content FROM MedicalInsight WHERE Id = :insightId LIMIT 1
        ];
        List<String> subjectNames = new List<String>();
        for (SubjectAssignment sa : [
            SELECT Subject.Name FROM SubjectAssignment WHERE AssignmentId = :insightId
        ]) {
            if (sa.Subject != null && sa.Subject.Name != null) {
                subjectNames.add(sa.Subject.Name);
            }
        }
        return ruleBased(mi, subjectNames);
    }

    public static Classification classifyInMemory(MedicalInsight mi, List<String> subjectNames) {
        return ruleBased(mi, subjectNames);
    }

    public static void classifyAndSave(Id insightId) {
        saveClassification(insightId, classify(insightId));
    }

    private static void saveClassification(Id insightId, Classification c) {
        if (c == null || String.isBlank(c.intent)) return;
        MedicalInsight mi = new MedicalInsight(Id = insightId);
        mi.put('Intent_Classification__c', c.intent);
        mi.put('Intent_Confidence__c', c.confidence);
        mi.put('Intent_Rationale__c', c.rationale);
        mi.put('Intent_Classified_At__c', System.now());
        mi.put('Intent_Subtopics__c', c.subtopics != null && !c.subtopics.isEmpty()
            ? String.join(c.subtopics, ',').left(255) : null);
        update mi;
    }

    private static Classification buildFromInputs(ClassifyRequest r) {
        Classification c = new Classification();
        c.intent = r.intent;
        c.confidence = r.confidence != null ? r.confidence : 0.85;
        c.rationale = String.isNotBlank(r.rationale) ? r.rationale : 'Intent produced by Einstein Prompt Template.';
        c.source = 'einstein';
        c.subtopics = new List<String>();
        if (String.isNotBlank(r.subtopicsCsv)) {
            for (String s : r.subtopicsCsv.split(',')) {
                if (String.isNotBlank(s)) c.subtopics.add(s.trim().toLowerCase());
            }
        }
        return c;
    }

    @TestVisible
    private static Classification ruleBased(MedicalInsight mi, List<String> subjectNames) {
        String haystack = ((mi.Name != null ? mi.Name : '') + ' ' +
                           (mi.Content != null ? mi.Content : '') + ' ' +
                           String.join(subjectNames, ' ')).toLowerCase();

        List<IntentRule> rules = buildRules();

        IntentRule best = null;
        Integer bestHits = 0;
        for (IntentRule r : rules) {
            Integer hits = 0;
            for (String k : r.keywords) {
                if (haystack.contains(k)) hits++;
            }
            if (hits > bestHits) {
                bestHits = hits;
                best = r;
            }
        }

        Classification c = new Classification();
        c.source = 'rule-based';
        c.subtopics = new List<String>();

        if (best == null) {
            c.intent = 'Other';
            c.confidence = 0.40;
            c.rationale = 'No strong semantic signal found; defaulting to Other.';
            return c;
        }

        c.intent = best.intent;
        c.confidence = Math.min(0.95, 0.55 + (bestHits * 0.10));
        c.rationale = best.rationale;

        for (SubtopicRule sr : best.subtopics) {
            for (String k : sr.keywords) {
                if (haystack.contains(k)) {
                    c.subtopics.add(sr.tag);
                    break;
                }
            }
        }
        return c;
    }

    private static List<IntentRule> buildRules() {
        return new List<IntentRule>{
            new IntentRule('Trial Access Barrier',
                new Set<String>{'clinical trial','trial site','trial availability','enrollment','eligibility','trial access','inclusion criteria'},
                'Mentions clinical trial access, eligibility, or enrollment friction.',
                new List<SubtopicRule>{
                    new SubtopicRule('site-availability', new Set<String>{'trial site','site availability','nearest site','enrolling site','regional site'}),
                    new SubtopicRule('geographic-access', new Set<String>{'travel','distance','miles from','minutes from','telemedicine','remote','rural'}),
                    new SubtopicRule('eligibility-criteria', new Set<String>{'eligibility','inclusion criteria','exclusion criteria','biomarker','prior therapy','line of therapy','qualif'}),
                    new SubtopicRule('enrollment-logistics', new Set<String>{'enrollment process','enroll patients','referral','screening visit','consent process'}),
                    new SubtopicRule('trial-financial', new Set<String>{'trial coverage','trial insurance','travel stipend','trial reimburs'})
                }),
            new IntentRule('Patient Education Gap',
                new Set<String>{'patient education','education material','brochure','language barrier','consent document','health literacy','translated'},
                'HCP is asking for patient-facing education material or calling out a comprehension gap.',
                new List<SubtopicRule>{
                    new SubtopicRule('language-access', new Set<String>{'spanish','language barrier','translated','non-english','limited english'}),
                    new SubtopicRule('consent-literacy', new Set<String>{'consent document','consent form','informed consent','health literacy'}),
                    new SubtopicRule('caregiver-materials', new Set<String>{'caregiver','family member','support person'}),
                    new SubtopicRule('disease-state-education', new Set<String>{'disease state','understand diagnosis','what is','explain treatment'}),
                    new SubtopicRule('side-effect-education', new Set<String>{'side effect education','what to expect','management brochure'})
                }),
            new IntentRule('Off-Label Information Request',
                new Set<String>{'off-label','off label','unapproved indication','unlicensed use'},
                'Request references an off-label use of the product.',
                new List<SubtopicRule>{
                    new SubtopicRule('unapproved-indication', new Set<String>{'unapproved','not approved','different indication'}),
                    new SubtopicRule('pediatric-use', new Set<String>{'pediatric','children','adolescent','minor'}),
                    new SubtopicRule('combination-use', new Set<String>{'combined with','in combination','added to','alongside'})
                }),
            new IntentRule('Safety Signal',
                new Set<String>{'adverse event','side effect','toxicity','safety concern','reaction','serious adverse'},
                'Contains an adverse event or safety concern.',
                new List<SubtopicRule>{
                    new SubtopicRule('hematologic-toxicity', new Set<String>{'neutropenia','thrombocytopenia','anemia','cytopenia','blood count'}),
                    new SubtopicRule('infusion-reaction', new Set<String>{'infusion reaction','hypersensitivity','allergic','anaphyl'}),
                    new SubtopicRule('dermatologic', new Set<String>{'rash','skin reaction','dermatitis','pruritus'}),
                    new SubtopicRule('gi-toxicity', new Set<String>{'nausea','vomiting','diarrhea','gi adverse','gastrointestinal'}),
                    new SubtopicRule('organ-toxicity', new Set<String>{'hepatotoxic','nephrotoxic','cardiotoxic','pneumonitis','liver function'}),
                    new SubtopicRule('discontinuation', new Set<String>{'discontinue','stop treatment','hold dose','dose interruption'})
                }),
            new IntentRule('Efficacy Question',
                new Set<String>{'efficacy','response rate','progression free','overall survival','outcomes data','real-world evidence'},
                'HCP is probing product efficacy or outcomes data.',
                new List<SubtopicRule>{
                    new SubtopicRule('survival-data', new Set<String>{'overall survival','os data','median survival'}),
                    new SubtopicRule('response-rates', new Set<String>{'response rate','orr','complete response','partial response'}),
                    new SubtopicRule('real-world-evidence', new Set<String>{'real-world','real world','rwe','community practice'}),
                    new SubtopicRule('subgroup-analysis', new Set<String>{'subgroup','elderly','prior treated','biomarker positive','brca'})
                }),
            new IntentRule('Dosing or Administration',
                new Set<String>{'dose','dosing','administration','infusion','schedule','titration'},
                'Question is about dosing regimen or administration.',
                new List<SubtopicRule>{
                    new SubtopicRule('dose-modification', new Set<String>{'dose reduction','dose adjust','dose modify','hold dose'}),
                    new SubtopicRule('administration-route', new Set<String>{'infusion','iv','subcutaneous','oral','injection site'}),
                    new SubtopicRule('dosing-schedule', new Set<String>{'every 2 weeks','every 3 weeks','q2w','q3w','cycle length','schedule'}),
                    new SubtopicRule('renal-hepatic-adjustment', new Set<String>{'renal impairment','hepatic impairment','creatinine clearance','liver function'})
                }),
            new IntentRule('Reimbursement or Access',
                new Set<String>{'insurance','coverage','reimbursement','prior authorization','copay','payer'},
                'Raises a reimbursement, coverage, or payer-access concern.',
                new List<SubtopicRule>{
                    new SubtopicRule('prior-authorization', new Set<String>{'prior authorization','prior auth','pa required','pa denial'}),
                    new SubtopicRule('copay-assistance', new Set<String>{'copay','co-pay','out of pocket','patient assistance','foundation support'}),
                    new SubtopicRule('payer-denial', new Set<String>{'denied','denial','rejected','not covered','appeal'}),
                    new SubtopicRule('medicare-medicaid', new Set<String>{'medicare','medicaid','part b','part d'})
                }),
            new IntentRule('Competitive or Comparative',
                new Set<String>{'versus',' vs ','compared to','competitor','head to head','head-to-head'},
                'Comparative question against another therapy.',
                new List<SubtopicRule>{
                    new SubtopicRule('direct-comparison', new Set<String>{'head to head','head-to-head','versus','vs.'}),
                    new SubtopicRule('switch-therapy', new Set<String>{'switch from','switched to','change therapy','replace with'}),
                    new SubtopicRule('sequencing', new Set<String>{'after progression','next line','sequence','following failure'})
                }),
            new IntentRule('Guideline or Protocol',
                new Set<String>{'guideline','nccn','protocol','standard of care','treatment pathway'},
                'References a treatment guideline or protocol.',
                new List<SubtopicRule>{
                    new SubtopicRule('nccn-guideline', new Set<String>{'nccn','national comprehensive'}),
                    new SubtopicRule('institutional-protocol', new Set<String>{'institutional','hospital protocol','local pathway'}),
                    new SubtopicRule('standard-of-care', new Set<String>{'standard of care','soc','first line standard'})
                })
        };
    }

    private class IntentRule {
        String intent;
        Set<String> keywords;
        String rationale;
        List<SubtopicRule> subtopics;
        IntentRule(String intent, Set<String> keywords, String rationale, List<SubtopicRule> subtopics) {
            this.intent = intent;
            this.keywords = keywords;
            this.rationale = rationale;
            this.subtopics = subtopics;
        }
    }

    private class SubtopicRule {
        String tag;
        Set<String> keywords;
        SubtopicRule(String tag, Set<String> keywords) {
            this.tag = tag;
            this.keywords = keywords;
        }
    }
}
