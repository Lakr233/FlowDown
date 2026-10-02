import { getAllDocs } from "@/lib/docs";

export interface NavLink {
  title: string;
  href: string;
}

export interface NavSection {
  title: string;
  items: NavLink[];
}

const sectionTitles: Record<string, string> = {
  root: "Overview",
  quickstart: "Quickstart",
  guides: "Guides",
  capabilities: "Capabilities",
  configuration: "Configuration",
  models: "Models",
  settings: "Settings",
  troubleshooting: "Troubleshooting",
  architecture: "Architecture",
  legal: "Legal",
};

const sectionOrder = [
  "root",
  "quickstart",
  "guides",
  "capabilities",
  "configuration",
  "models",
  "settings",
  "troubleshooting",
  "architecture",
  "legal",
];

const docOrderOverrides: Record<string, string[]> = {
  root: ["welcome", "app_store", "pricing_timeline", "changelog"],
};

const getDocOrderIndex = (section: string, slug: string[]) => {
  const order = docOrderOverrides[section];
  if (!order) {
    return null;
  }
  const key = slug.join("/");
  const index = order.indexOf(key);
  return index === -1 ? null : index;
};

const sortDocs = (
  section: string,
  docs: { slug: string[]; title: string }[],
) => {
  return docs.sort((a, b) => {
    const orderA = getDocOrderIndex(section, a.slug);
    const orderB = getDocOrderIndex(section, b.slug);

    if (orderA !== null && orderB !== null) {
      return orderA - orderB;
    }
    if (orderA !== null) {
      return -1;
    }
    if (orderB !== null) {
      return 1;
    }

    return a.title.localeCompare(b.title);
  });
};

export const getDocsConfig = () => {
  const docs = getAllDocs();
  const sections = new Map<string, { slug: string[]; title: string }[]>();

  for (const doc of docs) {
    const items = sections.get(doc.section) || [];
    items.push({
      slug: doc.slug,
      title: doc.title,
    });
    sections.set(doc.section, items);
  }

  const remainingSections = Array.from(sections.keys())
    .filter((section) => !sectionOrder.includes(section))
    .sort((a, b) => a.localeCompare(b));
  const orderedKeys = [...sectionOrder, ...remainingSections];

  const sidebarNav: NavSection[] = [];

  for (const sectionKey of orderedKeys) {
    const items = sections.get(sectionKey);
    if (!items) {
      continue;
    }

    const sorted = sortDocs(sectionKey, items);

    sidebarNav.push({
      title: sectionTitles[sectionKey] || sectionKey,
      items: sorted.map((entry) => ({
        title: entry.title,
        href: `/docs/documents/${entry.slug.join("/")}`,
      })),
    });
  }

  return { sidebarNav };
};
