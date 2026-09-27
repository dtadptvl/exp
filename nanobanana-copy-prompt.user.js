// ==UserScript==
// @name         NanoBanana Copy Prompt - No Login
// @namespace    https://github.com/dtadptvl/exp
// @version      1.0.0
// @description  Copy visible NanoBanana prompts without triggering the site's login modal.
// @match        https://nanobanana.org/banana-prompts/*
// @run-at       document-start
// @grant        none
// ==/UserScript==

(() => {
    'use strict';

    const clean = (s) =>
        (s || '')
            .replace(/\u00a0/g, ' ')
            .replace(/[ \t]+\n/g, '\n')
            .trim();

    async function copyText(text) {
        try {
            await navigator.clipboard.writeText(text);
            return true;
        } catch {}

        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.cssText =
            'position:fixed;left:-9999px;top:-9999px;opacity:0;';
        document.body.appendChild(ta);
        ta.select();

        const ok = document.execCommand('copy');
        ta.remove();
        return ok;
    }

    function findCopyButton(target) {
        if (!(target instanceof Element)) return null;

        const btn = target.closest('button, [role="button"], a');
        if (!btn) return null;

        const label = clean([
            btn.innerText,
            btn.getAttribute('aria-label'),
            btn.getAttribute('title')
        ].filter(Boolean).join(' ')).toLowerCase();

        return /\bcopy\b/.test(label) ? btn : null;
    }

    function findCard(btn) {
        const explicit = btn.closest(
            'article, li, [class*="card"], [class*="Card"], [data-prompt]'
        );

        if (explicit) return explicit;

        let el = btn.parentElement;

        for (let i = 0; el && i < 8; i++, el = el.parentElement) {
            const text = clean(el.innerText);

            if (text.length >= 100 && text.length <= 15000) {
                return el;
            }
        }

        return null;
    }

    function extractPrompt(btn) {
        const card = findCard(btn);
        if (!card) return '';

        const nodes = [...card.querySelectorAll(
            'textarea, pre, code, p, div, [data-prompt]'
        )];

        const candidates = [];

        for (const el of nodes) {
            if (el.contains(btn) || btn.contains(el)) continue;

            const text = clean(
                'value' in el && typeof el.value === 'string'
                    ? el.value
                    : el.innerText
            );

            if (text.length < 60 || text.length > 12000) continue;
            if (/^(copy|nano banana(?: pro)?|image:?)$/i.test(text)) continue;

            const hasSimilarChild = [...el.children].some((child) => {
                const childText = clean(child.innerText);

                return (
                    childText.length >= 60 &&
                    childText.length >= text.length * 0.8
                );
            });

            if (hasSimilarChild) continue;

            let score = text.length;

            const hint = [
                el.className,
                el.id,
                el.getAttribute('data-prompt')
            ].join(' ').toLowerCase();

            if (hint.includes('prompt')) score += 5000;
            if (el.matches('textarea, pre, code')) score += 10000;

            candidates.push({ text, score });
        }

        candidates.sort((a, b) => b.score - a.score);
        return candidates[0]?.text || '';
    }

    function flash(btn, ok) {
        const oldText = btn.innerText;

        if (oldText && oldText.length < 40) {
            btn.innerText = ok ? 'Copied ✓' : 'Copy failed';

            setTimeout(() => {
                btn.innerText = oldText;
            }, 900);
        }
    }

    // Capture phase runs before the site's normal click/login handler.
    document.addEventListener('click', async (event) => {
        const btn = findCopyButton(event.target);
        if (!btn) return;

        const prompt = extractPrompt(btn);
        if (!prompt) return;

        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();

        const ok = await copyText(prompt);
        flash(btn, ok);
    }, true);
})();
