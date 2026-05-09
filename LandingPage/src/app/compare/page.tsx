import type { Metadata } from "next";
import Link from "next/link";
import Navigation from "@/components/sections/Navigation";
import Footer from "@/components/sections/Footer";

export const metadata: Metadata = {
  title: "FlowDown AI Compare",
  description:
    "Compare FlowDown AI with ChatGPT app, Claude app, and Ollama for local models, privacy, Apple platform support, and model flexibility.",
  alternates: {
    canonical: "/compare",
  },
};

const rows = [
  {
    capability: "Native Apple app",
    flowdown: "iOS, iPadOS, and macOS Catalyst",
    chatgpt: "iOS and macOS apps",
    claude: "iOS and macOS apps",
    ollama: "Local runtime plus companion apps",
  },
  {
    capability: "Local models",
    flowdown: "MLX and Apple Intelligence workflows",
    chatgpt: "Cloud-first official models",
    claude: "Cloud-first official models",
    ollama: "Local model runtime",
  },
  {
    capability: "Custom providers",
    flowdown: "OpenAI-compatible base URLs, headers, and body fields",
    chatgpt: "Official OpenAI services",
    claude: "Official Anthropic services",
    ollama: "Local and compatible clients",
  },
  {
    capability: "Automation",
    flowdown: "Apple Shortcuts, deep links, tools, and MCP client support",
    chatgpt: "GPTs and platform integrations",
    claude: "Projects and MCP ecosystem integrations",
    ollama: "CLI and local APIs",
  },
  {
    capability: "Data model",
    flowdown: "Local-first storage with optional iCloud sync",
    chatgpt: "Hosted account workspace",
    claude: "Hosted account workspace",
    ollama: "Local runtime state",
  },
];

export default function ComparePage() {
  return (
    <div className="bg-[#f6f6f6] min-h-screen text-[#242424]">
      <Navigation />
      <main className="pt-[132px] px-6 max-w-[1180px] mx-auto">
        <p className="text-sm font-semibold uppercase tracking-[0.12em] text-[#6f6f6f] mb-4">
          Compare
        </p>
        <h1 className="font-['Instrument_Serif'] text-[52px] leading-tight mb-5">
          FlowDown AI Compared With Other AI Apps
        </h1>
        <p className="text-lg leading-8 text-[#555] max-w-[820px]">
          FlowDown fits users who want a native Apple-platform AI workspace with
          local models, OpenAI-compatible provider choice, MCP client support,
          and local-first storage.
        </p>

        <div className="overflow-x-auto mt-12 border border-[#dedede] rounded-[8px] bg-white">
          <table className="w-full text-left border-collapse min-w-[900px]">
            <thead>
              <tr className="border-b border-[#dedede]">
                <th className="p-4 font-semibold">Capability</th>
                <th className="p-4 font-semibold">FlowDown AI</th>
                <th className="p-4 font-semibold">ChatGPT app</th>
                <th className="p-4 font-semibold">Claude app</th>
                <th className="p-4 font-semibold">Ollama</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.capability} className="border-b border-[#eeeeee]">
                  <td className="p-4 font-medium">{row.capability}</td>
                  <td className="p-4 text-[#444]">{row.flowdown}</td>
                  <td className="p-4 text-[#555]">{row.chatgpt}</td>
                  <td className="p-4 text-[#555]">{row.claude}</td>
                  <td className="p-4 text-[#555]">{row.ollama}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <section className="grid gap-6 mt-10 md:grid-cols-3">
          <div className="border border-[#dedede] bg-white rounded-[8px] p-5">
            <h2 className="font-['Instrument_Serif'] text-[30px] mb-3">
              For local AI
            </h2>
            <p className="leading-7 text-[#555]">
              Use FlowDown when you want MLX or Apple Intelligence workflows in
              the same app as cloud models and conversation tools.
            </p>
          </div>
          <div className="border border-[#dedede] bg-white rounded-[8px] p-5">
            <h2 className="font-['Instrument_Serif'] text-[30px] mb-3">
              For provider choice
            </h2>
            <p className="leading-7 text-[#555]">
              Use FlowDown when the workflow needs custom OpenAI-compatible
              endpoints, provider headers, and per-model request settings.
            </p>
          </div>
          <div className="border border-[#dedede] bg-white rounded-[8px] p-5">
            <h2 className="font-['Instrument_Serif'] text-[30px] mb-3">
              For Apple automation
            </h2>
            <p className="leading-7 text-[#555]">
              Use FlowDown when Shortcuts, deep links, attachments, MCP client
              tools, and iCloud sync matter to the workflow.
            </p>
          </div>
        </section>

        <Link
          href="/agent"
          className="inline-flex mt-10 bg-[#242424] text-white text-base font-medium px-5 py-3 rounded-[8px]"
        >
          View Agent Resources
        </Link>
      </main>
      <Footer />
    </div>
  );
}
