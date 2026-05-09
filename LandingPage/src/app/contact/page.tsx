import type { Metadata } from "next";
import ResourcePage from "@/components/agent-readiness/ResourcePage";

export const metadata: Metadata = {
  title: "Contact FlowDown AI",
  description:
    "Contact, support, GitHub, and community links for FlowDown AI.",
  alternates: {
    canonical: "/contact",
  },
};

export default function ContactPage() {
  return (
    <ResourcePage
      eyebrow="Contact"
      title="Contact FlowDown AI"
      description="Use these channels for FlowDown support, bug reports, documentation feedback, commercial license requests, and agent-readiness questions."
      sections={[
        {
          title: "Support channels",
          links: [
            {
              label: "Email",
              href: "mailto:flowdownapp@qaq.wiki",
              description:
                "Primary contact for support, licensing, and security coordination.",
            },
            {
              label: "GitHub Issues",
              href: "https://github.com/Lakr233/FlowDown/issues",
              description:
                "Bug reports, feature requests, and reproducible technical issues.",
            },
            {
              label: "Discord Community",
              href: "https://discord.gg/UHKMRyJcgc",
              description:
                "Community setup help, model configuration discussion, and release feedback.",
            },
            {
              label: "Privacy policy",
              href: "/docs/documents/legal/privacy",
              description: "Data handling, provider use, and contact details.",
            },
          ],
        },
        {
          title: "Before sending logs",
          items: [
            "Remove API keys, provider tokens, private URLs, and personal text.",
            "Blur sensitive fields in screenshots.",
            "Include the FlowDown version, platform, model provider, and reproduction steps.",
            "For App Store purchase issues, include the storefront region and purchase date.",
          ],
        },
      ]}
    />
  );
}
