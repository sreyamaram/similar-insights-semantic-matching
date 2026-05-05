// One-shot backfill script: classifies every MedicalInsight without an intent.
// Run with: sf apex run --file scripts/apex/backfill_intents.apex -o <target-org>

Set<Id> toClassify = new Set<Id>();
for (MedicalInsight mi : [
    SELECT Id FROM MedicalInsight
    WHERE Intent_Classification__c = null
    LIMIT 1000
]) {
    toClassify.add(mi.Id);
}
System.debug('Enqueuing intent classification for ' + toClassify.size() + ' insights');
if (!toClassify.isEmpty()) {
    System.enqueueJob(new IntentClassifierQueueable(toClassify));
}
