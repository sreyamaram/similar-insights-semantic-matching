/**
 * Finds semantically similar insights by combining three signals:
 *   1. Same intent               (hard gate — required)
 *   2. Shared sub-topics          +5 each (max 15)
 *   3. Content Jaccard overlap    Jaccard * 10 (0-10)
 *   4. Shared specific subjects   +1 each (max 3, broad disease tags excluded)
 *
 * Minimum score 8 to appear; top 15 by score. This prevents the "every Oncology insight
 * looks similar" problem while still allowing partial-subject matches when intent and
 * content line up.
 */
public with sharing class IntentInsightAnalyzer {

    private static final Integer MIN_SCORE = 8;
    private static final Integer MAX_MATCHES = 15;

    private static final Set<String> BROAD_SUBJECTS = new Set<String>{
        'oncology','tnbc','disease areas','triple negative breast cancer',
        'categories','indications','disease states','territory','products'
    };

    private static final Set<String> STOPWORDS = new Set<String>{
        'the','a','an','and','or','but','if','of','in','on','for','to','from','with','without','by','is','are','was','were','be','been','has','have','had','do','does','did','this','that','these','those','it','its','as','at','i','me','my','we','our','you','your','they','their','he','she','his','her','about','into','over','under','will','would','can','could','should','may','might','also','than','then','so','not','no','yes','up','down','out','more','most','some','any','all','each','other','such','only','own','same','very','just','get','got','asking','asks','ask','wants','want','needs','need','said','says','say','patient','patients','hcp','physician','doctor','dr','clinic','practice','office','reports','reported','report','discuss','discussed','discussing','regarding','around','area','within','nearest'
    };

    @AuraEnabled(cacheable=false)
    public static PatternResult analyzePattern(Id insightId) {
        PatternResult result = new PatternResult();
        result.totalCount = 0;
        result.similarInsights = new List<SimilarInsight>();
        result.intentBreakdown = new List<IntentCount>();
        result.tagBreakdown = new List<TagCount>();

        MedicalInsight current;
        try {
            current = [
                SELECT Id, Name, Content, Intent_Classification__c, Intent_Confidence__c,
                       Intent_Rationale__c, Intent_Subtopics__c
                FROM MedicalInsight WHERE Id = :insightId LIMIT 1
            ];
        } catch (Exception e) {
            result.message = 'Insight not found';
            return result;
        }

        if (String.isBlank(current.Intent_Classification__c)) {
            IntentClassifier.classifyAndSave(insightId);
            current = [
                SELECT Id, Name, Content, Intent_Classification__c, Intent_Confidence__c,
                       Intent_Rationale__c, Intent_Subtopics__c
                FROM MedicalInsight WHERE Id = :insightId LIMIT 1
            ];
        }

        result.currentIntent = current.Intent_Classification__c;
        result.currentConfidence = current.Intent_Confidence__c;
        result.currentRationale = current.Intent_Rationale__c;
        result.currentSubtopics = current.Intent_Subtopics__c;

        Set<String> currentTokens = tokenize(current.Content);
        Set<String> currentSubtopics = splitCsv(current.Intent_Subtopics__c);

        Set<Id> currentSubjectIds = new Set<Id>();
        Map<Id, String> currentSubjectNames = new Map<Id, String>();
        for (SubjectAssignment sa : [
            SELECT SubjectId, Subject.Name FROM SubjectAssignment WHERE AssignmentId = :insightId
        ]) {
            String nm = sa.Subject != null ? sa.Subject.Name : null;
            if (nm != null && !BROAD_SUBJECTS.contains(nm.toLowerCase())) {
                currentSubjectIds.add(sa.SubjectId);
                currentSubjectNames.put(sa.SubjectId, nm);
            }
        }

        // Only candidates with the SAME intent qualify — hard gate
        List<MedicalInsight> candidates = [
            SELECT Id, Name, Content, CreatedDate, Owner.Name,
                   Intent_Classification__c, Intent_Subtopics__c
            FROM MedicalInsight
            WHERE Id != :insightId
            AND CreatedDate = LAST_N_DAYS:60
            AND Intent_Classification__c = :current.Intent_Classification__c
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        if (candidates.isEmpty()) {
            result.message = 'No other insights with intent "' + current.Intent_Classification__c + '" in the last 60 days';
            return result;
        }

        Set<Id> candidateIds = new Set<Id>();
        for (MedicalInsight mi : candidates) candidateIds.add(mi.Id);

        Map<Id, Set<Id>> subjectsByInsight = new Map<Id, Set<Id>>();
        Map<Id, Map<Id, String>> subjectNamesByInsight = new Map<Id, Map<Id, String>>();
        for (SubjectAssignment sa : [
            SELECT AssignmentId, SubjectId, Subject.Name
            FROM SubjectAssignment WHERE AssignmentId IN :candidateIds
        ]) {
            String nm = sa.Subject != null ? sa.Subject.Name : null;
            if (nm == null || BROAD_SUBJECTS.contains(nm.toLowerCase())) continue;
            if (!subjectsByInsight.containsKey(sa.AssignmentId)) {
                subjectsByInsight.put(sa.AssignmentId, new Set<Id>());
                subjectNamesByInsight.put(sa.AssignmentId, new Map<Id, String>());
            }
            subjectsByInsight.get(sa.AssignmentId).add(sa.SubjectId);
            subjectNamesByInsight.get(sa.AssignmentId).put(sa.SubjectId, nm);
        }

        Map<String, Integer> subtopicCounts = new Map<String, Integer>();
        Map<String, Integer> tagCounts = new Map<String, Integer>();
        List<ScoredInsight> scored = new List<ScoredInsight>();

        for (MedicalInsight cand : candidates) {
            Integer score = 0;
            List<String> reasons = new List<String>();

            Set<String> candSubtopics = splitCsv(cand.Intent_Subtopics__c);
            Set<String> sharedSubtopics = intersect(candSubtopics, currentSubtopics);
            Integer subtopicPoints = Math.min(15, sharedSubtopics.size() * 5);
            score += subtopicPoints;
            if (!sharedSubtopics.isEmpty()) {
                reasons.add('Shared sub-topics: ' + String.join(new List<String>(sharedSubtopics), ', '));
            }

            Set<String> candTokens = tokenize(cand.Content);
            Decimal jaccard = jaccardScore(currentTokens, candTokens);
            Integer contentPoints = (Integer) Math.max(0, Math.min(10, Math.round(jaccard * 10)));
            score += contentPoints;
            if (jaccard >= 0.15) {
                reasons.add('Content overlap: ' + (Integer)(jaccard * 100) + '%');
            }

            Set<Id> candSubjects = subjectsByInsight.get(cand.Id);
            Set<String> sharedSubjectNames = new Set<String>();
            if (candSubjects != null) {
                Set<Id> overlap = candSubjects.clone();
                overlap.retainAll(currentSubjectIds);
                Integer subjectPoints = Math.min(3, overlap.size());
                score += subjectPoints;
                for (Id sid : overlap) {
                    sharedSubjectNames.add(currentSubjectNames.get(sid));
                }
                if (!overlap.isEmpty()) {
                    reasons.add('Shared subjects: ' + String.join(new List<String>(sharedSubjectNames), ', '));
                }
            }

            // Same intent is the gate; prepend it to the rationale
            List<String> withIntent = new List<String>{ 'Same intent: ' + cand.Intent_Classification__c };
            withIntent.addAll(reasons);
            reasons = withIntent;

            if (score < MIN_SCORE) continue;

            ScoredInsight si = new ScoredInsight();
            si.record = cand;
            si.score = score;
            si.subtopicPoints = subtopicPoints;
            si.contentPoints = contentPoints;
            si.rationale = String.join(reasons, ' | ');
            scored.add(si);

            for (String st : candSubtopics) {
                subtopicCounts.put(st, (subtopicCounts.get(st) == null ? 0 : subtopicCounts.get(st)) + 1);
            }
            if (candSubjects != null) {
                Map<Id, String> nameMap = subjectNamesByInsight.get(cand.Id);
                for (Id sid : candSubjects) {
                    String tn = nameMap.get(sid);
                    if (String.isNotBlank(tn)) {
                        tagCounts.put(tn, (tagCounts.get(tn) == null ? 0 : tagCounts.get(tn)) + 1);
                    }
                }
            }
        }

        scored.sort();

        Integer emitted = 0;
        for (ScoredInsight s : scored) {
            if (emitted >= MAX_MATCHES) break;
            SimilarInsight match = new SimilarInsight();
            match.insightId = s.record.Id;
            match.insightName = s.record.Name;
            match.content = s.record.Content != null ? s.record.Content.left(240) : '';
            match.ownerName = s.record.Owner != null ? s.record.Owner.Name : '';
            match.createdDate = s.record.CreatedDate;
            match.intent = s.record.Intent_Classification__c;
            match.sameIntent = true;
            match.matchScore = s.score;
            match.rationale = s.rationale;
            match.subtopics = s.record.Intent_Subtopics__c;
            result.similarInsights.add(match);
            emitted++;
        }
        result.totalCount = result.similarInsights.size();

        for (String k : subtopicCounts.keySet()) {
            IntentCount ic = new IntentCount();
            ic.intent = k;
            ic.count = subtopicCounts.get(k);
            result.intentBreakdown.add(ic);
        }
        result.intentBreakdown.sort();

        for (String k : tagCounts.keySet()) {
            TagCount tc = new TagCount();
            tc.tagName = k;
            tc.count = tagCounts.get(k);
            result.tagBreakdown.add(tc);
        }
        result.tagBreakdown.sort();

        if (result.totalCount == 0) {
            result.message = 'No tightly matching insights. ' + scored.size()
                + ' share the same intent but did not meet the similarity threshold.';
        } else {
            result.message = 'Found ' + result.totalCount + ' tightly similar '
                + (scored.size() > MAX_MATCHES ? '(top ' + MAX_MATCHES + ' of ' + scored.size() + ')' : '')
                + ' insights with intent "' + current.Intent_Classification__c + '"';
        }
        return result;
    }

    @TestVisible
    private static Set<String> tokenize(String text) {
        Set<String> tokens = new Set<String>();
        if (String.isBlank(text)) return tokens;
        String cleaned = text.toLowerCase().replaceAll('[^a-z0-9 ]', ' ');
        for (String t : cleaned.split('\\s+')) {
            if (t.length() < 4) continue;
            if (STOPWORDS.contains(t)) continue;
            tokens.add(t);
        }
        return tokens;
    }

    @TestVisible
    private static Decimal jaccardScore(Set<String> a, Set<String> b) {
        if (a.isEmpty() || b.isEmpty()) return 0;
        Set<String> inter = a.clone();
        inter.retainAll(b);
        Set<String> uni = a.clone();
        uni.addAll(b);
        if (uni.isEmpty()) return 0;
        return Decimal.valueOf(inter.size()).divide(Decimal.valueOf(uni.size()), 4);
    }

    private static Set<String> splitCsv(String csv) {
        Set<String> out = new Set<String>();
        if (String.isBlank(csv)) return out;
        for (String s : csv.split(',')) {
            if (String.isNotBlank(s)) out.add(s.trim().toLowerCase());
        }
        return out;
    }

    private static Set<String> intersect(Set<String> a, Set<String> b) {
        Set<String> c = a.clone();
        c.retainAll(b);
        return c;
    }

    private class ScoredInsight implements Comparable {
        MedicalInsight record;
        Integer score;
        Integer subtopicPoints;
        Integer contentPoints;
        String rationale;
        public Integer compareTo(Object o) {
            return ((ScoredInsight) o).score - this.score;
        }
    }

    public class PatternResult {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public String message;
        @AuraEnabled public String currentIntent;
        @AuraEnabled public Decimal currentConfidence;
        @AuraEnabled public String currentRationale;
        @AuraEnabled public String currentSubtopics;
        @AuraEnabled public List<SimilarInsight> similarInsights;
        @AuraEnabled public List<IntentCount> intentBreakdown;
        @AuraEnabled public List<TagCount> tagBreakdown;
    }

    public class SimilarInsight {
        @AuraEnabled public Id insightId;
        @AuraEnabled public String insightName;
        @AuraEnabled public String content;
        @AuraEnabled public String ownerName;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String intent;
        @AuraEnabled public Boolean sameIntent;
        @AuraEnabled public Integer matchScore;
        @AuraEnabled public String rationale;
        @AuraEnabled public String subtopics;
    }

    public class IntentCount implements Comparable {
        @AuraEnabled public String intent;
        @AuraEnabled public Integer count;
        public Integer compareTo(Object o) {
            return ((IntentCount) o).count - this.count;
        }
    }

    public class TagCount implements Comparable {
        @AuraEnabled public String tagName;
        @AuraEnabled public Integer count;
        public Integer compareTo(Object o) {
            return ((TagCount) o).count - this.count;
        }
    }
}
