// Seeds 4 distinct intent+subtopic clusters across multiple MSLs so the home-page
// Pattern Alerts LWC shows real, differentiated, trending signals.
//
// Clusters:
//   1. Reimbursement or Access / prior-authorization       (12 insights, 4 MSLs, 8 this week)
//   2. Trial Access Barrier / geographic-access            (9 insights, 3 MSLs, 5 this week)
//   3. Patient Education Gap / language-access             (7 insights, 3 MSLs, 4 this week)
//   4. Safety Signal / hematologic-toxicity                (5 insights, 2 MSLs, 4 this week, brand new)

List<User> fieldUsers = [
    SELECT Id FROM User
    WHERE IsActive = true
    AND Profile.Name != 'Integration User'
    AND Profile.Name != 'Analytics Cloud Security User'
    AND Profile.Name != 'Platform Integration User'
    AND Name != 'Automated Process'
    ORDER BY Name
    LIMIT 6
];
if (fieldUsers.size() < 4) {
    System.debug('Not enough users — aborting');
    return;
}

DateTime now = System.now();

// age = how many days ago the insight was created. Mix ages so trending score varies.
class Sample {
    String name;
    String content;
    String intent;
    String subtopics;
    Integer ageDays;
    Sample(String n, String c, String i, String s, Integer a) {
        this.name = n; this.content = c; this.intent = i; this.subtopics = s; this.ageDays = a;
    }
}

List<Sample> samples = new List<Sample>();

// Cluster 1: Prior Authorization (HOT — 8/12 in last 7 days)
samples.add(new Sample('Prior auth denied for Therapy Brand X', 'HCP reports prior authorization denied citing step therapy requirement not met for Therapy Brand X. Payer wants documentation of prior line first.', 'Reimbursement or Access', 'prior-authorization,payer-denial', 1));
samples.add(new Sample('PA denial — payer requires step therapy', 'Third prior auth rejection this month. Payer citing step therapy policy. Need playbook for appeal.', 'Reimbursement or Access', 'prior-authorization,payer-denial', 2));
samples.add(new Sample('Prior authorization rejected — need help', 'Physician frustrated with repeated prior authorization rejections for new therapy. Considering alternatives.', 'Reimbursement or Access', 'prior-authorization', 3));
samples.add(new Sample('HCP asks about PA appeal process', 'HCP asking about prior authorization appeal process after second denial. Patient cannot start treatment.', 'Reimbursement or Access', 'prior-authorization,payer-denial', 4));
samples.add(new Sample('Blue Cross prior auth hurdle', 'Blue Cross plan requires prior authorization with 5-day turnaround but consistently exceeding that. Blocking initiation.', 'Reimbursement or Access', 'prior-authorization', 5));
samples.add(new Sample('UnitedHealth PA denial — step therapy', 'UnitedHealth prior authorization denied citing step therapy policy not being met. Practice needs fast-track guidance.', 'Reimbursement or Access', 'prior-authorization,payer-denial', 6));
samples.add(new Sample('Prior auth: urgent case delayed 2 weeks', 'Urgent TNBC case delayed two weeks waiting on prior authorization. Oncologist escalating to medical director.', 'Reimbursement or Access', 'prior-authorization', 7));
samples.add(new Sample('PA denial requires peer-to-peer review', 'Prior authorization denial requires peer-to-peer review. MSL support needed for clinical argument.', 'Reimbursement or Access', 'prior-authorization', 9));
samples.add(new Sample('Payer prior auth form complexity', 'Practice staff complaining about prior authorization form complexity and frequent denials on first submission.', 'Reimbursement or Access', 'prior-authorization', 12));
samples.add(new Sample('Medicare Advantage PA issue', 'Medicare Advantage plan prior authorization requirements differ from commercial — causing confusion and delays.', 'Reimbursement or Access', 'prior-authorization,medicare-medicaid', 18));
samples.add(new Sample('Insurance denial for off-label indication', 'Payer denial for off-label indication despite NCCN compendium support. Prior auth appealed.', 'Reimbursement or Access', 'prior-authorization,payer-denial', 22));
samples.add(new Sample('Prior authorization training needed', 'Practice requesting prior authorization training and documentation templates after multiple denials.', 'Reimbursement or Access', 'prior-authorization', 26));

// Cluster 2: Trial geographic access (warm — 5/9 in last 7 days)
samples.add(new Sample('Patient 2 hours from nearest trial site', 'HCP reports patient is 2 hours driving distance from nearest enrolling trial site. Needs telemedicine option.', 'Trial Access Barrier', 'site-availability,geographic-access', 1));
samples.add(new Sample('Trial travel burden', 'Practice 90 minutes from enrolling center. Multiple patients declining trial due to travel distance.', 'Trial Access Barrier', 'site-availability,geographic-access', 2));
samples.add(new Sample('Regional trial site needed', 'HCP asking when regional trial sites will be enrolling. Currently sending patients 3+ hours away.', 'Trial Access Barrier', 'site-availability,geographic-access', 3));
samples.add(new Sample('Telemedicine follow-up for trial', 'Trial site too far for follow-up visits. Discussed telemedicine options but site does not offer them.', 'Trial Access Barrier', 'geographic-access', 5));
samples.add(new Sample('Rural practice trial access', 'Rural practice reports no trial sites within 150 miles. Patients losing trial option due to geographic access.', 'Trial Access Barrier', 'site-availability,geographic-access', 7));
samples.add(new Sample('Travel stipend question', 'Patient interested in trial but asking about travel stipend or lodging support. Geographic distance is barrier.', 'Trial Access Barrier', 'geographic-access,trial-financial', 11));
samples.add(new Sample('Site map out of date', 'Published trial site list appears out of date. Patients traveling to sites that have stopped enrolling.', 'Trial Access Barrier', 'site-availability', 15));
samples.add(new Sample('No local enrolling site', 'No local enrolling site within reasonable drive for patient. Referring out of state.', 'Trial Access Barrier', 'site-availability,geographic-access', 20));
samples.add(new Sample('Trial site consolidation concern', 'Academic center consolidated trial sites, leaving community hospital 2 hours away as only option.', 'Trial Access Barrier', 'site-availability,geographic-access', 24));

// Cluster 3: Language access (warm)
samples.add(new Sample('Spanish consent form needed', 'Spanish-speaking patient unable to enroll — consent form only available in English.', 'Patient Education Gap', 'language-access,consent-literacy', 1));
samples.add(new Sample('Translated education materials', 'Requesting translated patient education materials for Vietnamese and Mandarin speakers.', 'Patient Education Gap', 'language-access', 2));
samples.add(new Sample('Bilingual caregiver support', 'Non-English speaking patient needs bilingual caregiver materials for side effect management.', 'Patient Education Gap', 'language-access,caregiver-materials', 4));
samples.add(new Sample('Consent form language barrier', 'Consent documents only in English. Patient family needs translated version to make decision.', 'Patient Education Gap', 'language-access,consent-literacy', 6));
samples.add(new Sample('Health literacy challenge', 'Limited English proficiency patient struggling with health literacy. Simpler translated materials needed.', 'Patient Education Gap', 'language-access,consent-literacy', 10));
samples.add(new Sample('Language line for HCP consults', 'HCP asking for language line access during medical consultations with non-English patients.', 'Patient Education Gap', 'language-access', 16));
samples.add(new Sample('Translated side effect guide', 'Translated side effect guides needed — current English-only materials unusable for significant portion of patient population.', 'Patient Education Gap', 'language-access,side-effect-education', 23));

// Cluster 4: Hematologic toxicity (HOT — brand new, 4/5 in last 7 days)
samples.add(new Sample('Grade 3 neutropenia case', 'Grade 3 neutropenia observed requiring treatment delay. Third case this cycle.', 'Safety Signal', 'hematologic-toxicity', 1));
samples.add(new Sample('Dose hold for low blood counts', 'Low blood counts requiring dose hold. Multiple similar cases — worth flagging pattern.', 'Safety Signal', 'hematologic-toxicity,discontinuation', 2));
samples.add(new Sample('Thrombocytopenia emerging', 'Thrombocytopenia emerging after cycle 2. Not expected per trial data — may warrant investigation.', 'Safety Signal', 'hematologic-toxicity', 3));
samples.add(new Sample('Severe cytopenia — discontinuation', 'Patient discontinued due to severe cytopenia. Third discontinuation in 3 weeks from this practice.', 'Safety Signal', 'hematologic-toxicity,discontinuation', 5));
samples.add(new Sample('Anemia requiring transfusion', 'Anemia requiring transfusion support. Practice asking if dose reduction guidance exists.', 'Safety Signal', 'hematologic-toxicity', 8));

// Insert
List<MedicalInsight> toInsert = new List<MedicalInsight>();
for (Integer i = 0; i < samples.size(); i++) {
    Sample s = samples[i];
    MedicalInsight mi = new MedicalInsight(
        Name = s.name,
        Content = s.content,
        SourceType = 'MedicalInsightsTab',
        Intent_Classification__c = s.intent,
        Intent_Subtopics__c = s.subtopics,
        Intent_Confidence__c = 0.85,
        Intent_Rationale__c = 'Seeded for alert demo.',
        Intent_Classified_At__c = now.addDays(-s.ageDays),
        OwnerId = fieldUsers[Math.mod(i, fieldUsers.size())].Id
    );
    toInsert.add(mi);
}
insert toInsert;

// CreatedDate is not writable on insert, but we need backdated records so trending math
// is meaningful. Salesforce allows test-only backdating via auditFields, but only for
// specific orgs. For the demo, records are all "today" but trending score will still
// vary based on Intent_Classified_At__c which we DO control.
System.debug('Inserted ' + toInsert.size() + ' insights across ' + fieldUsers.size() + ' MSLs');
