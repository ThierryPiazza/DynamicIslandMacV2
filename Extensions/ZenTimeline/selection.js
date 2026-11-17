/* One owner across tabs/frames. Polls of paused/inactive media never claim it. */
class MediaSelection {
  constructor() { this.items = new Map(); this.owner = null; }
  update(key, track, activeTab, now = Date.now()) {
    const old = this.items.get(key);
    if (!track) this.items.delete(key);
    else {
      const item = { ...track, key, seen: now };
      this.items.set(key, item);
      const owner = this.items.get(this.owner);
      const started = item.isPlaying && (!old?.isPlaying || old.identity !== item.identity);
      if (item.isPlaying && (!owner || (started && activeTab))) this.owner = key;
    }
    return this.current(now);
  }
  removeTab(tabID) {
    for (const [key, value] of this.items) if (value.tabID === tabID) this.items.delete(key);
    return this.current();
  }
  current(now = Date.now()) {
    for (const [key, item] of this.items) if (now - item.seen > 8000) this.items.delete(key);
    if (!this.items.has(this.owner)) {
      this.owner = [...this.items.values()].filter(x => x.isPlaying)
        .sort((a, b) => b.seen - a.seen)[0]?.key || null;
    }
    return this.items.get(this.owner) || null;
  }
}
