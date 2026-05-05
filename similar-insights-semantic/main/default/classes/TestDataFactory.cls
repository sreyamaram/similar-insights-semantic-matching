@IsTest
public class TestDataFactory {
    public static MedicalInsight insight(String name, String content) {
        return new MedicalInsight(
            Name = name,
            Content = content,
            SourceType = 'MedicalInsightsTab'
        );
    }

    public static MedicalInsight insight(String name, String content, String intent) {
        MedicalInsight mi = insight(name, content);
        mi.Intent_Classification__c = intent;
        return mi;
    }
}
