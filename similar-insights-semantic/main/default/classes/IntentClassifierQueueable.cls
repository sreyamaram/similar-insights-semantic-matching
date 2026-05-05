/**
 * Async wrapper that classifies a batch of MedicalInsight records. Bulk-loads insights
 * + subjects in 2 SOQL queries total, then runs the rule-based classifier in-memory.
 */
public with sharing class IntentClassifierQueueable implements Queueable {
    private Set<Id> insightIds;

    public IntentClassifierQueueable(Set<Id> insightIds) {
        this.insightIds = insightIds;
    }

    public void execute(QueueableContext ctx) {
        if (insightIds == null || insightIds.isEmpty()) return;

        Map<Id, MedicalInsight> needsClassification = new Map<Id, MedicalInsight>([
            SELECT Id, Name, Content
            FROM MedicalInsight
            WHERE Id IN :insightIds AND Intent_Classification__c = null
        ]);
        if (needsClassification.isEmpty()) return;

        Map<Id, List<String>> subjectsByInsight = new Map<Id, List<String>>();
        for (SubjectAssignment sa : [
            SELECT AssignmentId, Subject.Name
            FROM SubjectAssignment
            WHERE AssignmentId IN :needsClassification.keySet()
        ]) {
            if (sa.Subject == null || sa.Subject.Name == null) continue;
            if (!subjectsByInsight.containsKey(sa.AssignmentId)) {
                subjectsByInsight.put(sa.AssignmentId, new List<String>());
            }
            subjectsByInsight.get(sa.AssignmentId).add(sa.Subject.Name);
        }

        List<MedicalInsight> toUpdate = new List<MedicalInsight>();
        for (MedicalInsight mi : needsClassification.values()) {
            List<String> subjectNames = subjectsByInsight.get(mi.Id);
            if (subjectNames == null) subjectNames = new List<String>();

            IntentClassifier.Classification c;
            try {
                c = IntentClassifier.classifyInMemory(mi, subjectNames);
            } catch (Exception e) {
                continue;
            }
            if (c == null || String.isBlank(c.intent)) continue;

            MedicalInsight upd = new MedicalInsight(Id = mi.Id);
            upd.put('Intent_Classification__c', c.intent);
            upd.put('Intent_Confidence__c', c.confidence);
            upd.put('Intent_Rationale__c', c.rationale);
            upd.put('Intent_Classified_At__c', System.now());
            upd.put('Intent_Subtopics__c', c.subtopics != null && !c.subtopics.isEmpty()
                ? String.join(c.subtopics, ',').left(255) : null);
            toUpdate.add(upd);
        }
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}
