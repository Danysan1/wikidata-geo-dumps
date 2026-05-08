const container = document.getElementById('wgd-dumps-container');

function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;',
        '"': '&quot;', "'": '&#39;'
    })[c]);
}

function formatBytes(bytes) {
    if (!Number.isFinite(bytes)) return '';
    if (bytes < 1024) return `${bytes} B`;
    const units = ['KB', 'MB', 'GB', 'TB'];
    let value = bytes / 1024;
    let unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
        value /= 1024;
        unitIndex++;
    }
    return `${value.toFixed(1)} ${units[unitIndex]}`;
}

function render(dumps) {
    if (!dumps || dumps.length === 0) {
        container.innerHTML = '<p class="wgd-status">No dumps available yet.</p>';
        container.removeAttribute('aria-busy');
        return;
    }
    container.innerHTML = dumps.map(dump => {
        const date = escapeHtml(dump.date);
        const items = (dump.files || []).map(f => {
            const name = escapeHtml(f.name);
            const href = `dumps/${encodeURIComponent(dump.date)}/${encodeURIComponent(f.name)}`;
            return `<li>
                        <a href="${href}" download><code>${name}</code></a>
                        <span class="wgd-file-size">${escapeHtml(formatBytes(f.size))}</span>
                    </li>`;
        }).join('');
        return `<section>
                    <h3 id="dump-${date}">${date}</h3>
                    ${items ? `<ul>${items}</ul>` : '<p class="wgd-status">No files.</p>'}
                </section>`;
    }).join('');
    container.removeAttribute('aria-busy');
}

fetch('dumps/index.json', { cache: 'no-cache' })
    .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
    })
    .then(data => render(data.dumps))
    .catch(err => {
        console.error('Failed to load dump index', err);
        container.innerHTML =
            '<p class="wgd-status">Could not load the dump list. ' +
            'The index may not have been generated yet.</p>';
        container.removeAttribute('aria-busy');
    });
