import type { Metadata } from "next";
import ResourcePage from "@/components/agent-readiness/ResourcePage";

export const metadata: Metadata = {
  title: "About FlowDown AI",
  description:
    "About FlowDown AI, the native privacy-first AI workspace for iOS, iPadOS, and macOS.",
  alternates: {
    canonical: "/about",
  },
};

export default function AboutPage() {
  return (
    <ResourcePage
      eyebrow="About"
      title="About FlowDown AI"
      description="FlowDown is built for people who want a fast native AI workspace on Apple platforms while keeping control over models, providers, context, and stored data."
      sections={[
        {
          title: "What FlowDown is",
          body: "FlowDown combines local-first conversations, OpenAI-compatible cloud providers, on-device model options, rich Markdown rendering, attachments, web search, memory, MCP client support, and Shortcuts automation in one native iPhone, iPad, and Mac app.",
        },
        {
          title: "Project principles",
          items: [
            "Privacy-first defaults: conversation data is stored locally, with optional iCloud sync controlled by the user.",
            "Model choice: users can switch between local MLX, Apple Intelligence, self-hosted endpoints, and other OpenAI-compatible services.",
            "Native performance: the app is written for Apple platforms with Swift and UIKit.",
            "Open development: the source code is available on GitHub under AGPL-3.0.",
          ],
        },
        {
          title: "Team and support",
          body: "FlowDown is maintained by the FlowDown team and community contributors. Support is available through GitHub issues, Discord, and the in-app support flow that exports logs after the user removes sensitive data.",
          links: [
            {
              label: "GitHub repository",
              href: "https://github.com/Lakr233/FlowDown",
              description: "Source code, issues, releases, and development history.",
            },
            {
              label: "Contact",
              href: "/contact",
              description: "Email and support links.",
            },
          ],
        },
      ]}
    />
  );
}
