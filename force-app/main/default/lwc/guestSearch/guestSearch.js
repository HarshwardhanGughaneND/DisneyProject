import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import searchGuests from '@salesforce/apex/TourBookingController.searchGuests';

const DEBOUNCE_DELAY = 300;

export default class GuestSearch extends NavigationMixin(LightningElement) {
    @track searchTerm = '';
    @track searchResults = [];
    @track isSearching = false;
    @track hasSearched = false;

    _debounceTimer = null;

    get hasResults() {
        return this.searchResults && this.searchResults.length > 0;
    }

    get resultCount() {
        return this.searchResults ? this.searchResults.length : 0;
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._debounceTimer);

        if (!this.searchTerm || this.searchTerm.trim().length < 2) {
            this.searchResults = [];
            this.hasSearched = false;
            this.isSearching = false;
            return;
        }

        this.isSearching = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._debounceTimer = setTimeout(() => {
            this.performSearch();
        }, DEBOUNCE_DELAY);
    }

    handleKeyUp(event) {
        if (event.key === 'Enter') {
            clearTimeout(this._debounceTimer);
            if (this.searchTerm && this.searchTerm.trim().length >= 2) {
                this.performSearch();
            }
        }
    }

    performSearch() {
        this.isSearching = true;
        searchGuests({ searchTerm: this.searchTerm.trim() })
            .then(results => {
                this.searchResults = results;
                this.hasSearched = true;
                this.isSearching = false;
            })
            .catch(error => {
                this.isSearching = false;
                this.hasSearched = true;
                this.searchResults = [];
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Search Error',
                        message: this.extractErrorMessage(error),
                        variant: 'error'
                    })
                );
            });
    }

    handleSelectGuest(event) {
        const guestId = event.currentTarget.dataset.id;
        const guest = this.searchResults.find(g => g.id === guestId);
        if (guest) {
            this.dispatchEvent(
                new CustomEvent('guest-selected', { detail: guest, bubbles: true, composed: true })
            );
        }
    }

    handleViewGuest(event) {
        const guestId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: guestId,
                actionName: 'view'
            }
        });
    }

    handleTapAction() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Tap Guest Media',
                message: 'Please tap the guest\'s media device to identify.',
                variant: 'info'
            })
        );
    }

    handleCameraAction() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Camera Scan',
                message: 'Please scan the guest\'s QR code or barcode.',
                variant: 'info'
            })
        );
    }

    handleCreateGuest() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Account',
                actionName: 'new'
            }
        });
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unknown error occurred.';
    }
}
