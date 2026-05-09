import type { Metadata } from "next";
import ResourcePage from "@/components/agent-readiness/ResourcePage";

export const metadata: Metadata = {
  title: "FlowDown AI Pricing",
  description:
    "FlowDown AI pricing timeline, App Store availability, and machine-readable pricing resources.",
  alternates: {
    canonical: "/pricing",
  },
};

export default function PricingPage() {
  return (
    <ResourcePage
      eyebrow="Pricing"
      title="FlowDown AI Pricing"
      description="FlowDown is distributed through the App Store for iPhone, iPad, and Mac. The US storefront pricing timeline steps down toward a free base app in June 2026."
      sections={[
        {
          title: "Pricing timeline",
          items: [
            "2025-11-10 to 2025-12-10: $14.99.",
            "2025-12-10 to 2026-01-10: $9.99.",
            "2026-01-10 to 2026-02-10: $8.99.",
            "2026-03-10 to 2026-04-10: $6.99.",
            "2026-04-10 to 2026-05-10: $5.99.",
            "2026-05-10 to 2026-06-10: $3.99.",
            "Starting 2026-06-10: $0.00 base app.",
          ],
        },
        {
          title: "Included capabilities",
          items: [
            "Native chat workspace for iOS, iPadOS, and macOS.",
            "OpenAI-compatible cloud model profiles.",
            "Local MLX and Apple Intelligence model workflows.",
            "MCP client integration, web search, attachments, memory, and Shortcuts automation.",
            "Local-first storage with optional iCloud sync.",
          ],
        },
        {
          title: "Machine-readable pricing",
          links: [
            {
              label: "pricing.md",
              href: "/pricing.md",
              description: "Markdown pricing file for agents.",
            },
            {
              label: "Pricing timeline docs",
              href: "/docs/documents/pricing_timeline",
              description: "Documentation page with the same timeline.",
            },
            {
              label: "App Store listing",
              href: "https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198",
              description:
                "Regional App Store pricing is the final source of purchase price.",
            },
          ],
        },
      ]}
    />
  );
}
