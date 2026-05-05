import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import analyzePattern from '@salesforce/apex/IntentInsightAnalyzer.analyzePattern';

export default class SimilarInsightsIntent extends NavigationMixin(LightningElement) {
    @api recordId;

    result = null;
    isLoading = true;
    error = null;

    connectedCallback() {
        this.load();
    }

    load() {
        this.isLoading = true;
        this.error = null;
        analyzePattern({ insightId: this.recordId })
            .then((r) => {
                this.result = r;
                this.isLoading = false;
            })
            .catch((e) => {
                this.error = (e && e.body && e.body.message) || 'Unable to analyze pattern';
                this.isLoading = false;
            });
    }

    handleRefresh() {
        this.load();
    }

    get hasResults() {
        return this.result && this.result.totalCount > 0;
    }

    get noResults() {
        return !this.isLoading && !this.error && this.result && this.result.totalCount === 0;
    }

    get currentIntent() {
        return this.result ? this.result.currentIntent : '';
    }

    get currentRationale() {
        return this.result ? this.result.currentRationale : '';
    }

    get currentConfidencePct() {
        if (!this.result || this.result.currentConfidence == null) return '';
        return `${Math.round(this.result.currentConfidence * 100)}%`;
    }

    get currentSubtopics() {
        if (!this.result || !this.result.currentSubtopics) return [];
        return this.result.currentSubtopics.split(',').map((s) => s.trim()).filter(Boolean);
    }

    get message() {
        return this.result ? this.result.message : '';
    }

    get patternSummary() {
        if (!this.result || !this.hasResults) return '';
        const topSubtopics = (this.result.intentBreakdown || [])
            .slice(0, 3)
            .map((i) => `${i.intent} (${i.count})`)
            .join(', ');
        const pieces = [
            `${this.result.totalCount} insights share intent "${this.result.currentIntent}" AND overlap on specific themes or language with this insight.`
        ];
        if (topSubtopics) {
            pieces.push(`Most common sub-topics across matches: ${topSubtopics}.`);
        }
        pieces.push(`Ranking combines shared sub-topics (weight 5 each), content overlap (0–10), and shared specific subjects (broad disease tags excluded).`);
        return pieces.join(' ');
    }

    get intentBreakdown() {
        return (this.result && this.result.intentBreakdown) || [];
    }

    get similarInsights() {
        if (!this.result || !this.result.similarInsights) return [];
        return this.result.similarInsights.map((i) => ({
            ...i,
            recordUrl: `/lightning/r/MedicalInsight/${i.insightId}/view`,
            intentLabel: i.intent || 'Unclassified',
            subtopicList: (i.subtopics || '').split(',').map((s) => s.trim()).filter(Boolean),
            scoreLabel: `Match: ${i.matchScore}`
        }));
    }

    handleNavigate(event) {
        event.preventDefault();
        const insightId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: insightId,
                objectApiName: 'MedicalInsight',
                actionName: 'view'
            }
        });
    }
}
