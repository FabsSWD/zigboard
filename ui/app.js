const API_BASE = 'http://127.0.0.1:8080';

class ClipboardUI {
    constructor() {
        this.items = [];
        this.selectedIndex = 0;
        this.viewItems = [];
        this.searchInput = document.getElementById('search-input');
        this.historyList = document.getElementById('history-list');
        this.statusBar = document.getElementById('status-bar');
        this.initKeyboardHandlers();
        this.initSearchHandler();
        this.refresh();
    }

    initKeyboardHandlers() {
        document.addEventListener('keydown', (e) => {
            if (e.key === 'ArrowDown') { e.preventDefault(); this.moveSelection(1); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); this.moveSelection(-1); }
            else if (e.key === 'Enter') { e.preventDefault(); this.copySelected(); }
            else if (e.key === 'Delete') { e.preventDefault(); this.deleteSelected(); }
            else if (e.ctrlKey && e.key === 'p') { e.preventDefault(); this.togglePinSelected(); }
            else if (e.key === 'Escape') window.close();
            else if (e.ctrlKey && e.key === 'f') { e.preventDefault(); this.searchInput.focus(); this.searchInput.select(); }
        });
    }

    initSearchHandler() {
        let debounce;
        this.searchInput.addEventListener('input', (e) => {
            clearTimeout(debounce);
            debounce = setTimeout(() => { this.searchQuery = e.target.value; this.refresh(); }, 150);
        });
    }

    async refresh() {
        try {
            const params = new URLSearchParams();
            if (this.searchQuery) params.set('q', this.searchQuery);
            const res = await fetch(`${API_BASE}/history?${params}`);
            const data = await res.json();
            const prevId = this.viewItems[this.selectedIndex]?.id;
            this.items = data.items || [];
            this.viewItems = this.computeViewItems(this.items);
            const foundIndex = prevId ? this.viewItems.findIndex(it => it.id === prevId) : -1;
            if (foundIndex >= 0) {
                this.selectedIndex = foundIndex;
            } else {
                this.selectedIndex = Math.min(this.selectedIndex, Math.max(0, this.viewItems.length - 1));
            }
            this.render();
            this.setStatus('Ready');
        } catch (err) { this.setStatus(`Error: ${err.message}`); }
    }

    render() {
        this.historyList.innerHTML = '';
        const grouped = this.groupItems(this.viewItems);
        let flatIndex = 0;
        
        grouped.forEach(group => {
            // Group header
            const header = document.createElement('div');
            header.className = 'group-header';
            header.textContent = group.title;
            this.historyList.appendChild(header);
            
            // Group items
            group.items.forEach(item => {
                const div = document.createElement('div');
                div.className = `history-item${item.pinned ? ' pinned' : ''}${flatIndex === this.selectedIndex ? ' selected' : ''}`;
                div.onclick = () => { this.selectedIndex = flatIndex; this.render(); };
                div.ondblclick = () => this.copySelected();
                
                const text = document.createElement('div');
                text.className = 'item-text';
                text.textContent = item.text.substring(0, 200) + (item.text.length > 200 ? '...' : '');
                
                const meta = document.createElement('div');
                meta.className = 'item-meta';
                const ts = new Date(item.ts / 1_000_000).toLocaleString();
                meta.textContent = `${ts} · ${item.text.length} chars`;

                // Actions (pin/unpin, delete)
                const actions = document.createElement('div');
                actions.className = 'item-actions';

                const pinBtn = document.createElement('span');
                pinBtn.className = 'material-symbols-outlined icon-btn';
                pinBtn.textContent = item.pinned ? 'keep_off' : 'keep';
                pinBtn.title = item.pinned ? 'Unpin' : 'Pin';
                pinBtn.onclick = (ev) => { ev.stopPropagation(); this.selectedIndex = flatIndex; this.togglePinSelected(); };

                const delBtn = document.createElement('span');
                delBtn.className = 'material-symbols-outlined icon-btn';
                delBtn.textContent = 'delete';
                delBtn.title = 'Delete';
                delBtn.onclick = (ev) => { ev.stopPropagation(); this.selectedIndex = flatIndex; this.deleteSelected(); };

                actions.appendChild(pinBtn);
                actions.appendChild(delBtn);
                
                div.appendChild(text);
                div.appendChild(meta);
                div.appendChild(actions);
                this.historyList.appendChild(div);
                flatIndex++;
            });
        });
    }
    
    groupItems(items) {
        const pinned = items.filter(i => i.pinned);
        const unpinned = items.filter(i => !i.pinned);
        const groups = [];
        
        if (pinned.length > 0) {
            groups.push({ title: `📌 Pinned (${pinned.length})`, items: pinned });
        }
        
        if (unpinned.length > 0) {
            groups.push({ title: `📋 Recent (${unpinned.length})`, items: unpinned });
        }
        
        return groups;
    }

    moveSelection(delta) {
        this.selectedIndex = Math.max(0, Math.min(this.viewItems.length - 1, this.selectedIndex + delta));
        this.render();
    }

    async copySelected() {
        const item = this.viewItems[this.selectedIndex];
        if (!item) return;
        try {
            await navigator.clipboard.writeText(item.text);
            this.setStatus('Copied');
        } catch { this.setStatus('Copy failed - use Ctrl+C'); }
    }

    async togglePinSelected() {
        const item = this.viewItems[this.selectedIndex];
        if (!item) return;
        const endpoint = item.pinned ? 'unpin' : 'pin';
        try {
            await fetch(`${API_BASE}/${endpoint}?id=${item.id}`, { method: 'POST' });
            this.setStatus(item.pinned ? 'Unpinned' : 'Pinned');
            await this.refresh();
        } catch (err) { this.setStatus(`Error: ${err.message}`); }
    }

    async deleteSelected() {
        const item = this.viewItems[this.selectedIndex];
        if (!item) return;
        if (!confirm('Delete?')) return;
        try {
            await fetch(`${API_BASE}/delete?id=${item.id}`, { method: 'DELETE' });
            this.setStatus('Deleted');
            await this.refresh();
        } catch (err) { this.setStatus(`Error: ${err.message}`); }
    }

    setStatus(msg) { this.statusBar.textContent = msg; }
}

ClipboardUI.prototype.computeViewItems = function(items) {
    const pinned = items.filter(i => i.pinned);
    const unpinned = items.filter(i => !i.pinned);
    return [...pinned, ...unpinned];
};

new ClipboardUI();
