/**
 * Home-page alerts that surface *actionable* intent+subtopic patterns, not coarse
 * subject buckets. Groups by (Intent_Classification__c, subtopic), computes trending
 * against the prior 3-week baseline, picks the centroid insight (the one whose subtopics
 * overlap most with the rest of the bucket) as the representative card.
 *
 * Guardrails:
 *   - Bucket must have >= MIN_INSIGHTS insights in last 30 days
 *   - Bucket must span >= MIN_MSLS distinct owners (kills single-rep false patterns)
 *   - Ranked by trendingScore (7-day volume relative to 3-week baseline), tiebreak by
 *     total volume.
 */
public with sharing class IntentPatternAlertController {

    private static final Integer MIN_INSIGHTS = 3;
    private static final Integer MIN_MSLS = 2;
    private static final Integer LOOKBACK_DAYS = 30;
    private static final Integer RECENT_DAYS = 7;
    private static final Integer MAX_ALERTS = 3;

    public class PatternAlertData implements Comparable {
        @AuraEnabled public Id insightId;
        @AuraEnabled public String insightName;
        @AuraEnabled public String insightPreview;
        @AuraEnabled public String intent;
        @AuraEnabled public String subtopic;
        @AuraEnabled public String bucketLabel;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer recentCount;
        @AuraEnabled public Integer mslCount;
        @AuraEnabled public Decimal trendingScore;
        @AuraEnabled public String trendingLabel;
        @AuraEnabled public Integer lookbackDays;

        public Integer compareTo(Object o) {
            PatternAlertData other = (PatternAlertData) o;
            // Primary: higher trendingScore first
            if (other.trendingScore != this.trendingScore) {
                return other.trendingScore > this.trendingScore ? 1 : -1;
            }
            // Tiebreak: higher totalCount first
            return other.totalCount - this.totalCount;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PatternAlertData> getPatternAlerts() {
        DateTime now = System.now();
        DateTime windowStart = now.addDays(-LOOKBACK_DAYS);
        DateTime recentStart = now.addDays(-RECENT_DAYS);

        // Use Intent_Classified_At__c as the activity timestamp — it's the moment the
        // classifier saw the insight, which is what "when did this pattern emerge" means.
        // Falls back to CreatedDate for records classified before this field was populated.
        List<MedicalInsight> recent = [
            SELECT Id, Name, Content, CreatedDate, OwnerId,
                   Intent_Classification__c, Intent_Subtopics__c, Intent_Classified_At__c
            FROM MedicalInsight
            WHERE (Intent_Classified_At__c >= :windowStart OR CreatedDate >= :windowStart)
            AND Intent_Classification__c != null
            AND ParentMedicalInsightId = null
            ORDER BY CreatedDate DESC
            LIMIT 1000
        ];

        if (recent.isEmpty()) {
            return new List<PatternAlertData>();
        }

        // Bucket by (intent, subtopic). Skip records with no subtopics — they're the low-signal ones.
        Map<String, Bucket> buckets = new Map<String, Bucket>();
        for (MedicalInsight mi : recent) {
            if (String.isBlank(mi.Intent_Subtopics__c)) continue;
            for (String st : mi.Intent_Subtopics__c.split(',')) {
                String subtopic = st.trim().toLowerCase();
                if (String.isBlank(subtopic)) continue;
                String key = mi.Intent_Classification__c + '::' + subtopic;
                if (!buckets.containsKey(key)) {
                    buckets.put(key, new Bucket(mi.Intent_Classification__c, subtopic));
                }
                buckets.get(key).add(mi, recentStart);
            }
        }

        List<PatternAlertData> alerts = new List<PatternAlertData>();
        for (Bucket b : buckets.values()) {
            if (b.insights.size() < MIN_INSIGHTS) continue;
            if (b.owners.size() < MIN_MSLS) continue;

            PatternAlertData a = new PatternAlertData();
            a.intent = b.intent;
            a.subtopic = b.subtopic;
            a.bucketLabel = b.intent + ' • ' + b.subtopic;
            a.totalCount = b.insights.size();
            a.recentCount = b.recentCount;
            a.mslCount = b.owners.size();
            a.lookbackDays = LOOKBACK_DAYS;
            a.trendingScore = computeTrendingScore(a.recentCount, a.totalCount);
            a.trendingLabel = buildTrendingLabel(a.recentCount, a.totalCount);

            MedicalInsight centroid = pickCentroid(b);
            a.insightId = centroid.Id;
            a.insightName = centroid.Name;
            a.insightPreview = centroid.Content != null ? centroid.Content.left(180) : '';

            alerts.add(a);
        }

        alerts.sort();

        List<PatternAlertData> top = new List<PatternAlertData>();
        for (Integer i = 0; i < Math.min(MAX_ALERTS, alerts.size()); i++) {
            top.add(alerts[i]);
        }
        return top;
    }

    /**
     * 7-day volume relative to the expected rate from the prior 3-week period.
     * score = recent7 / expected, where expected = (total - recent7) / 3 (3 weeks of baseline).
     * Steady-state = 1.0, accelerating = > 1.0, brand new = very high.
     */
    private static Decimal computeTrendingScore(Integer recent, Integer total) {
        Integer baseline = total - recent;
        if (baseline <= 0) {
            return recent >= MIN_INSIGHTS ? 3.0 : 1.0; // brand new cluster
        }
        Decimal baselinePerWeek = Decimal.valueOf(baseline).divide(3, 4);
        if (baselinePerWeek == 0) return 1.0;
        return Decimal.valueOf(recent).divide(baselinePerWeek, 2);
    }

    private static String buildTrendingLabel(Integer recent, Integer total) {
        Integer baseline = total - recent;
        if (baseline == 0) {
            return '+' + recent + ' this week (new pattern)';
        }
        Decimal perWeekBaseline = Decimal.valueOf(baseline).divide(3, 2);
        if (perWeekBaseline <= 0.5) {
            return '+' + recent + ' this week (ramping up)';
        }
        Decimal ratio = Decimal.valueOf(recent).divide(perWeekBaseline, 2);
        if (ratio >= 3) {
            return '+' + recent + ' this week — surging (>' + ratio.intValue() + 'x prior rate)';
        }
        Decimal pctChange = (ratio - 1) * 100;
        pctChange = pctChange.setScale(0);
        if (pctChange > 25) {
            return '+' + recent + ' this week, up ' + pctChange + '% vs prior 3-week avg';
        } else if (pctChange < -25) {
            return recent + ' this week, down ' + Math.abs(pctChange.intValue()) + '% vs prior 3-week avg';
        } else {
            return recent + ' this week (steady)';
        }
    }

    /**
     * The centroid is the insight whose own subtopic set has the most overlap with the
     * rest of the bucket — i.e. the most emblematic insight of the pattern.
     */
    private static MedicalInsight pickCentroid(Bucket b) {
        MedicalInsight best = b.insights[0];
        Integer bestOverlap = -1;
        for (MedicalInsight candidate : b.insights) {
            Set<String> candSubtopics = splitCsv(candidate.Intent_Subtopics__c);
            Integer overlap = 0;
            for (MedicalInsight other : b.insights) {
                if (other.Id == candidate.Id) continue;
                Set<String> otherSub = splitCsv(other.Intent_Subtopics__c);
                Set<String> inter = candSubtopics.clone();
                inter.retainAll(otherSub);
                overlap += inter.size();
            }
            if (overlap > bestOverlap) {
                bestOverlap = overlap;
                best = candidate;
            }
        }
        return best;
    }

    private static Set<String> splitCsv(String csv) {
        Set<String> out = new Set<String>();
        if (String.isBlank(csv)) return out;
        for (String s : csv.split(',')) {
            if (String.isNotBlank(s)) out.add(s.trim().toLowerCase());
        }
        return out;
    }

    private class Bucket {
        String intent;
        String subtopic;
        List<MedicalInsight> insights = new List<MedicalInsight>();
        Set<Id> owners = new Set<Id>();
        Integer recentCount = 0;

        Bucket(String intent, String subtopic) {
            this.intent = intent;
            this.subtopic = subtopic;
        }

        void add(MedicalInsight mi, DateTime recentStart) {
            insights.add(mi);
            if (mi.OwnerId != null) owners.add(mi.OwnerId);
            DateTime activityAt = (DateTime) mi.get('Intent_Classified_At__c');
            if (activityAt == null) activityAt = mi.CreatedDate;
            if (activityAt >= recentStart) recentCount++;
        }
    }
}
