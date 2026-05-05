trigger MedicalInsightIntentTrigger on MedicalInsight (after insert, after update) {
    Set<Id> toClassify = new Set<Id>();
    for (MedicalInsight mi : Trigger.new) {
        if (String.isBlank((String) mi.get('Intent_Classification__c'))) {
            toClassify.add(mi.Id);
        }
    }
    if (!toClassify.isEmpty() && !System.isQueueable() && !System.isBatch() && !System.isFuture()) {
        System.enqueueJob(new IntentClassifierQueueable(toClassify));
    }
}
