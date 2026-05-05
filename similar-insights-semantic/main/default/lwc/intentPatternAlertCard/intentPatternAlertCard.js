import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPatternAlerts from '@salesforce/apex/IntentPatternAlertController.getPatternAlerts';

export default class IntentPatternAlertCard extends NavigationMixin(LightningElement) {
    alerts = [];
    error = null;
    isLoading = true;

    @wire(getPatternAlerts)
    wired({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.alerts = data;
            this.error = null;
        } else if (error) {
            this.error = error;
            this.alerts = [];
        }
    }

    get hasAlerts() {
        return this.alerts && this.alerts.length > 0;
    }

    get alertCount() {
        return this.alerts ? this.alerts.length : 0;
    }

    get processedAlerts() {
        return this.alerts.map((a, i) => ({
            ...a,
            index: i,
            coverageLabel: `${a.totalCount} insights across ${a.mslCount} MSLs in last ${a.lookbackDays} days`,
            isTrendingHot: a.trendingScore >= 1.5,
            variantClass: a.trendingScore >= 1.5 ? 'alert-card hot' : 'alert-card',
            iconName: a.trendingScore >= 1.5 ? 'utility:trending' : 'utility:warning'
        }));
    }

    handleViewInsights(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const alert = this.alerts[index];
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: alert.insightId,
                objectApiName: 'MedicalInsight',
                actionName: 'view'
            }
        });
    }

    handleDismiss(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.alerts = this.alerts.filter((_, i) => i !== index);
    }
}
