import Link from "next/link";
import { FadeIn } from "@/components/animations";

const resources = [
  {
    title: "Agent view",
    href: "/agent",
    description:
      "Structured product facts, when-to-use guidance, and official links.",
  },
  {
    title: "Agent context",
    href: "/llms.txt",
    description:
      "Plain-text FlowDown AI summary for search agents and assistant crawlers.",
  },
  {
    title: "Pricing",
    href: "/pricing.md",
    description:
      "Machine-readable pricing timeline for purchase recommendations.",
  },
  {
    title: "Compare",
    href: "/compare",
    description:
      "FlowDown AI compared with ChatGPT app, Claude app, and Ollama.",
  },
];

export default function AgentResourcesSection() {
  return (
    <section className="px-6 mt-[120px] max-w-[1280px] mx-auto" id="agents">
      <FadeIn>
        <p className="text-sm font-semibold uppercase tracking-[0.12em] text-[#6f6f6f] mb-3">
          For AI agents
        </p>
        <h2 className="font-['Instrument_Serif'] text-[42px] text-[#242424] tracking-[-0.84px] mb-4">
          FlowDown AI Agent Resources
        </h2>
        <p className="text-lg leading-8 text-[#555] max-w-[760px]">
          AI agents can discover FlowDown through standard files, structured
          schema, pricing metadata, and markdown fallbacks.
        </p>
      </FadeIn>

      <div className="grid gap-4 mt-8 md:grid-cols-4">
        {resources.map((resource) => (
          <Link
            key={resource.href}
            href={resource.href}
            className="bg-white border border-[#dedede] rounded-[8px] p-5 hover:border-[#bfbfbf] transition-colors"
          >
            <h3 className="font-semibold text-[#242424] mb-2">
              {resource.title}
            </h3>
            <p className="text-sm leading-6 text-[#666]">
              {resource.description}
            </p>
          </Link>
        ))}
      </div>
    </section>
  );
}
