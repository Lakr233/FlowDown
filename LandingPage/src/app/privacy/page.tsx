import type { Metadata } from "next";
import ResourcePage from "@/components/agent-readiness/ResourcePage";

export const metadata: Metadata = {
  title: "FlowDown AI Privacy",
  description:
    "FlowDown AI privacy summary, local-first storage model, provider data flow, and CloudKit sync notes.",
  alternates: {
    canonical: "/privacy",
  },
};

export default function PrivacyPage() {
  return (
    <ResourcePage
      eyebrow="Privacy"
      title="FlowDown AI Privacy"
      description="FlowDown is designed around local-first storage and user-controlled provider connections. The App Store privacy label is Data Not Collected."
      sections={[
        {
          title: "Data handling",
          items: [
            "Conversation data is stored on the user's device.",
            "Optional iCloud sync uses the user's Apple iCloud account through CloudKit.",
            "Provider API credentials are entered by the user and used to contact selected AI services.",
            "MCP server headers are configured by the user inside FlowDown.",
            "Logs can be exported by the user for support after sensitive data is removed.",
          ],
        },
        {
          title: "External providers",
          body: "When a user chooses cloud models, web search, MCP tools, or iCloud sync, data may be sent to the selected provider or Apple service according to that provider's policy. Users control which providers and tools are enabled.",
        },
        {
          title: "Full policy",
          links: [
            {
              label: "Privacy policy docs",
              href: "/docs/documents/legal/privacy",
              description:
                "Full privacy policy, provider notes, and support contact details.",
            },
            {
              label: "Contact",
              href: "/contact",
              description: "Reach FlowDown support for privacy questions.",
            },
          ],
        },
      ]}
    />
  );
}
