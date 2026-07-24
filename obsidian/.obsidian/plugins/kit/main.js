const { Plugin, ItemView, Notice, addIcon } = require("obsidian");

const VIEW_TYPE_KIT = "kit";
const UP_NEXT_CAP = 3;

// From assets/Kit-Logo-2424r.svg — scaled 24→100 for Obsidian's addIcon viewBox.
addIcon(
  "kit-logo",
  `<g transform="scale(4.1666667)"><path d="M3.192 12.586V18.196V20H-0.0199999V18.174V6.404V4.6H3.192V6.426V11.288L6.998 7.262L8.076 6.096L9.462 4.6H13.554C13.334 4.82 13.0627 5.106 12.74 5.458L10.914 7.35L6.58 11.794L12.014 17.932L12.806 18.856L13.818 20H9.55L3.192 12.586ZM14.8844 19.17V13.82V13H16.3444V13.83V19.18V20H14.8844V19.17ZM17.4266 13H23.3066V14.36H22.0066H21.0966V19.18V20H19.6366V19.09V14.36H18.7166H17.4266V13Z" fill="currentColor"/></g>`
);

// From assets/Kit-Logo-256.svg — fill uses currentColor for theme contrast.
const HERO_LOGO_SVG = `<svg class="kit-home__logo" viewBox="0 0 256 256" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M42.2753 131.64V203.04V226H1.39531V202.76V52.96V30H42.2753V53.24V115.12L90.7153 63.88L104.435 49.04L122.075 30H174.155C171.355 32.8 167.902 36.44 163.795 40.92L140.555 65L85.3953 121.56L154.555 199.68L164.635 211.44L177.515 226H123.195L42.2753 131.64ZM186.833 219.36V176.56V170H198.513V176.64V219.44V226H186.833V219.36ZM207.17 170H254.21V180.88H243.81H236.53V219.44V226H224.85V218.72V180.88H217.49H207.17V170Z" fill="currentColor"/></svg>`;

const URGENCY_RANK = { overdue: 0, soon: 1, today: 2 };

const INITIAL_ITEMS = [
  {
    id: "mine-rachel",
    verb: "Send Rachel the rollout risk summary",
    context: "Rachel · overdue · from rollout sync",
    lane: "mine",
    urgency: "overdue",
  },
  {
    id: "mine-devops",
    verb: "Ask DevOps whether the migration window can move",
    context: "DevOps · due soon · from planning",
    lane: "mine",
    urgency: "soon",
  },
  {
    id: "mine-marcus",
    verb: "Follow up with Marcus about staff-level scope",
    context: "Marcus · waiting on me · from 1:1",
    lane: "mine",
    urgency: "soon",
  },
  {
    id: "mine-project-x",
    verb: "Decide whether Project X remains a Q3 priority",
    context: "Leadership · due soon · from staff sync",
    lane: "mine",
    urgency: "soon",
  },
  {
    id: "waiting-priya",
    verb: "Priya will update the API proposal",
    context: "Priya · waiting on them",
    lane: "waiting",
    urgency: "soon",
  },
  {
    id: "waiting-data",
    verb: "Data team will confirm the event schema by Wednesday",
    context: "Data team · waiting on them",
    lane: "waiting",
    urgency: "soon",
  },
  {
    id: "prep-priya",
    verb: "Prep 1:1 with Priya — open loops from last week",
    context: "Priya · today · meeting prep",
    lane: "prep",
    urgency: "today",
  },
];

const TOOLS = [
  {
    id: "listen",
    name: "listen",
    purpose: "Records conversations and produces named-speaker transcripts.",
  },
  {
    id: "notice",
    name: "notice",
    purpose: "Extracts commitments, decisions, and open loops from transcripts.",
  },
  {
    id: "remember",
    name: "remember",
    purpose: "Routes extracted information into durable Obsidian notes.",
  },
  {
    id: "surface",
    name: "surface",
    purpose: "Shows what needs attention now.",
  },
  {
    id: "prepare",
    name: "prepare",
    purpose: "Builds context packs before important interactions.",
  },
  {
    id: "brief",
    name: "brief",
    purpose: "Generates leadership briefs and stakeholder updates.",
  },
  {
    id: "followup",
    name: "followup",
    purpose: "Tracks promises and helps close loops.",
  },
  {
    id: "reflect",
    name: "reflect",
    purpose: "Reviews patterns over time.",
  },
];

function sortMine(items) {
  return items
    .filter((item) => item.lane === "mine")
    .slice()
    .sort(
      (a, b) =>
        (URGENCY_RANK[a.urgency] ?? 99) - (URGENCY_RANK[b.urgency] ?? 99)
    );
}

function cloneItems(items) {
  return items.map((item) => ({ ...item }));
}

class KitView extends ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
    this.items = cloneItems(INITIAL_ITEMS);
  }

  getViewType() {
    return VIEW_TYPE_KIT;
  }

  getDisplayText() {
    return "Kit";
  }

  getIcon() {
    return "kit-logo";
  }

  async onOpen() {
    this.render();
  }

  async onClose() {
    this.contentEl.empty();
  }

  getPrimary() {
    return sortMine(this.items)[0] ?? null;
  }

  getUpNext() {
    return sortMine(this.items).slice(1, 1 + UP_NEXT_CAP);
  }

  getLane(lane) {
    return this.items.filter((item) => item.lane === lane);
  }

  removeItem(id) {
    this.items = this.items.filter((item) => item.id !== id);
  }

  snoozeItem(id) {
    const item = this.items.find((entry) => entry.id === id);
    if (!item || item.lane !== "mine") return;
    this.items = this.items.filter((entry) => entry.id !== id);
    this.items.push(item);
  }

  handleAction(action, item) {
    if (action === "do") {
      new Notice(`Mock — done: ${item.verb}`);
      this.removeItem(item.id);
    } else if (action === "snooze") {
      new Notice(`Mock — snoozed: ${item.verb}`);
      this.snoozeItem(item.id);
    } else if (action === "not-mine") {
      new Notice(`Mock — not mine: ${item.verb}`);
      this.removeItem(item.id);
    }
    this.render();
  }

  render() {
    const root = this.contentEl;
    root.empty();
    root.addClass("kit-home");

    this.buildHeader(root);
    this.buildPrimary(root);
    this.buildUpNext(root);
    this.buildLaneSection(root, "Waiting on others", this.getLane("waiting"));
    this.buildLaneSection(root, "Meeting prep", this.getLane("prep"));
    this.buildTools(root);
  }

  buildHeader(root) {
    const header = root.createDiv({ cls: "kit-home__header" });
    header.innerHTML = HERO_LOGO_SVG;
  }

  buildPrimary(root) {
    const section = root.createDiv({ cls: "kit-home__primary" });
    section.createEl("h1", {
      text: "Close this next",
      cls: "kit-home__headline",
    });

    const item = this.getPrimary();
    if (!item) {
      section.createEl("p", {
        cls: "kit-home__empty",
        text: "You’re clear. Nothing to close right now.",
      });
      return;
    }

    const body = section.createDiv({ cls: "kit-home__primary-body" });
    body.createEl("p", { cls: "kit-home__verb", text: item.verb });
    body.createEl("p", { cls: "kit-home__context", text: item.context });
    this.buildActions(body, item, true);
  }

  buildUpNext(root) {
    const section = root.createDiv({ cls: "kit-home__lane" });
    section.createEl("h2", { text: "Up next" });

    const items = this.getUpNext();
    if (items.length === 0) {
      section.createEl("p", {
        cls: "kit-home__lane-empty",
        text: "Nothing queued behind the primary.",
      });
      return;
    }

    const list = section.createDiv({ cls: "kit-home__rows" });
    for (const item of items) {
      this.buildRow(list, item);
    }
  }

  buildLaneSection(root, title, items) {
    const section = root.createDiv({ cls: "kit-home__lane" });
    section.createEl("h2", { text: title });

    if (items.length === 0) {
      section.createEl("p", {
        cls: "kit-home__lane-empty",
        text: "None right now.",
      });
      return;
    }

    const list = section.createDiv({ cls: "kit-home__rows" });
    for (const item of items) {
      const row = list.createDiv({ cls: "kit-home__row kit-home__row--static" });
      row.createEl("p", { cls: "kit-home__verb", text: item.verb });
      row.createEl("p", { cls: "kit-home__context", text: item.context });
    }
  }

  buildRow(parent, item) {
    const row = parent.createDiv({ cls: "kit-home__row" });
    row.createEl("p", { cls: "kit-home__verb", text: item.verb });
    row.createEl("p", { cls: "kit-home__context", text: item.context });
    this.buildActions(row, item, false);
  }

  buildActions(parent, item, isPrimary) {
    const actions = parent.createDiv({
      cls: isPrimary
        ? "kit-home__actions kit-home__actions--primary"
        : "kit-home__actions",
    });

    const doBtn = actions.createEl("button", {
      text: "Do it",
      cls: isPrimary ? "mod-cta" : "kit-home__action",
      attr: { type: "button" },
    });
    this.registerDomEvent(doBtn, "click", () => this.handleAction("do", item));

    const snoozeBtn = actions.createEl("button", {
      text: "Snooze",
      cls: "kit-home__action",
      attr: { type: "button" },
    });
    this.registerDomEvent(snoozeBtn, "click", () =>
      this.handleAction("snooze", item)
    );

    const notMineBtn = actions.createEl("button", {
      text: "Not mine",
      cls: "kit-home__action",
      attr: { type: "button" },
    });
    this.registerDomEvent(notMineBtn, "click", () =>
      this.handleAction("not-mine", item)
    );
  }

  buildTools(root) {
    const details = root.createEl("details", { cls: "kit-home__tools" });
    details.createEl("summary", { text: "Tools" });

    const list = details.createDiv({ cls: "kit-home__tool-list" });
    for (const tool of TOOLS) {
      const row = list.createEl("button", {
        cls: "kit-home__tool-row",
        attr: { type: "button", "data-tool": tool.id },
      });
      row.createEl("span", {
        cls: "kit-home__tool-name",
        text: `kit ${tool.name}`,
      });
      row.createEl("span", {
        cls: "kit-home__tool-purpose",
        text: tool.purpose,
      });
      this.registerDomEvent(row, "click", () => {
        new Notice(`Mock — kit ${tool.name} is not wired`);
      });
    }
  }
}

module.exports = class KitPlugin extends Plugin {
  async onload() {
    this.registerView(VIEW_TYPE_KIT, (leaf) => new KitView(leaf, this));

    this.addRibbonIcon("kit-logo", "Open Kit", () => {
      this.activateKit();
    });

    this.addCommand({
      id: "open-kit",
      name: "Open Kit",
      callback: () => this.activateKit(),
    });
  }

  async onunload() {}

  async activateKit() {
    const { workspace } = this.app;
    const leaves = workspace.getLeavesOfType(VIEW_TYPE_KIT);

    let leaf =
      leaves.find((candidate) => candidate.getRoot() === workspace.rootSplit) ??
      null;

    if (!leaf) {
      for (const extra of leaves) {
        extra.detach();
      }
      leaf = workspace.getLeaf("tab");
      await leaf.setViewState({
        type: VIEW_TYPE_KIT,
        active: true,
      });
    }

    workspace.revealLeaf(leaf);
  }
};
