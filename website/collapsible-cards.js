/**
 * Turn Server Info configuration cards into collapsed-by-default sections.
 */

(function configureCollapsibleCards() {
    'use strict';

    let generatedCardId = 0;

    function directChild(card, selector) {
        return Array.from(card.children).find((child) => child.matches(selector));
    }

    function cardTitle(card) {
        return directChild(card, '.card-collapse-header')
            ?.querySelector('h2')?.textContent?.trim() || '';
    }

    function setExpanded(card, expanded) {
        const body = directChild(card, '.card-collapse-body');
        const toggle = directChild(card, '.card-collapse-header')
            ?.querySelector('.card-collapse-toggle');
        if (!body || !toggle) {
            return;
        }
        body.hidden = !expanded;
        card.classList.toggle('card-expanded', expanded);
        toggle.setAttribute('aria-expanded', String(expanded));
        toggle.textContent = expanded ? '−' : '+';
        toggle.setAttribute(
            'aria-label',
            `${expanded ? 'Collapse' : 'Expand'} ${cardTitle(card)}`
        );
    }

    function initializeCard(card) {
        if (card.dataset.collapsibleInitialized === 'true') {
            return;
        }
        const heading = directChild(card, 'h2');
        if (!heading) {
            return;
        }
        card.dataset.collapsibleInitialized = 'true';
        card.classList.add('collapsible-card');

        const header = document.createElement('div');
        header.className = 'card-collapse-header';
        card.insertBefore(header, heading);
        header.appendChild(heading);

        const summary = document.createElement('span');
        summary.className = 'card-collapse-summary';
        summary.textContent = card.dataset.collapseSummary || 'Settings';
        header.appendChild(summary);

        const body = document.createElement('div');
        body.className = 'card-collapse-body';
        const cardId = card.id || `collapsible-card-${++generatedCardId}`;
        card.id = cardId;
        body.id = `${cardId}-body`;
        while (header.nextSibling) {
            body.appendChild(header.nextSibling);
        }
        card.appendChild(body);

        const toggle = document.createElement('button');
        toggle.className = 'card-collapse-toggle';
        toggle.type = 'button';
        toggle.setAttribute('aria-controls', body.id);
        header.appendChild(toggle);
        toggle.addEventListener('click', () => {
            setExpanded(card, toggle.getAttribute('aria-expanded') !== 'true');
        });
        header.addEventListener('click', (event) => {
            if (event.target.closest('button')) {
                return;
            }
            toggle.click();
        });
        setExpanded(card, false);
    }

    window.setCollapsibleCardSummary = function setCollapsibleCardSummary(
        cardId, text, state = ''
    ) {
        const summary = document.getElementById(cardId)
            ?.querySelector('.card-collapse-summary');
        if (!summary) {
            return;
        }
        summary.textContent = text;
        summary.className = state
            ? `card-collapse-summary summary-${state}`
            : 'card-collapse-summary';
    };

    window.initializeCollapsibleCards = function initializeCollapsibleCards() {
        document.querySelectorAll('#config-section > .card:not(.actions)')
            .forEach(initializeCard);
    };
}());
