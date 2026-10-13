import fs from "node:fs";
import path from "node:path";

export interface DocEntry {
  slug: string[];
  section: string;
  title: string;
}

const docsRoot = path.join(process.cwd(), "src", "app", "docs", "documents");

const markdownExtension = /\.(md|mdx)$/;

const isMarkdownFile = (fileName: string) => markdownExtension.test(fileName);

const stripMarkdown = (value: string) =>
  value
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/[*_`>#]/g, "")
    .replace(/!\s*\[[^\]]*\]\([^)]+\)/g, "")
    .trim();

const extractTitle = (content: string) => {
  const match = content.match(/^#\s+(.+)$/m);
  return match?.[1]?.trim() || "Untitled";
};

const extractDescription = (content: string) => {
  const lines = content.split(/\r?\n/);
  let inCodeBlock = false;

  for (const line of lines) {
    const trimmed = line.trim();

    if (trimmed.startsWith("```")) {
      inCodeBlock = !inCodeBlock;
      continue;
    }

    if (inCodeBlock || trimmed.length === 0) {
      continue;
    }

    if (
      trimmed.startsWith("#") ||
      trimmed.startsWith("![") ||
      trimmed === "---"
    ) {
      continue;
    }

    const cleaned = stripMarkdown(trimmed);
    if (cleaned.length > 0) {
      return cleaned;
    }
  }

  return "FlowDown documentation.";
};

const toSlug = (relativePath: string) =>
  relativePath.replace(markdownExtension, "").split(path.sep);

const toSection = (slug: string[]) => (slug.length > 1 ? slug[0] : "root");

const walkFiles = (directory: string): string[] => {
  if (!fs.existsSync(directory)) {
    return [];
  }

  const entries = fs.readdirSync(directory, { withFileTypes: true });
  const files: string[] = [];

  for (const entry of entries) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...walkFiles(entryPath));
      continue;
    }

    if (entry.isFile() && isMarkdownFile(entry.name)) {
      files.push(entryPath);
    }
  }

  return files;
};

export const fixImagePaths = (content: string) => {
  const markdownImages = content.replace(
    /\((\.\.?\/)+res\/([^)]+)\)/g,
    "(/docs/res/$2)",
  );

  return markdownImages.replace(
    /src=["'](\.\.?\/)+res\/([^"']+)["']/g,
    'src="/docs/res/$2"',
  );
};

const docSlugs = () =>
  walkFiles(docsRoot).map((filePath) => ({
    filePath,
    slug: toSlug(path.relative(docsRoot, filePath)),
  }));

export const getAllDocs = (): DocEntry[] =>
  docSlugs().map(({ filePath, slug }) => {
    const content = fs.readFileSync(filePath, "utf8");
    const title = extractTitle(content);

    return {
      slug,
      section: toSection(slug),
      title,
    };
  });

export const getAllDocPaths = () => docSlugs().map(({ slug }) => ({ slug }));

export const getDocBySlug = (slug: string[]) => {
  const relativePath = slug.join(path.sep);
  const candidates = [
    path.join(docsRoot, `${relativePath}.md`),
    path.join(docsRoot, `${relativePath}.mdx`),
  ];

  const filePath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!filePath) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf8");
  const title = extractTitle(content);
  const description = extractDescription(content);

  return {
    title,
    description,
    content,
  };
};
