import type { Metadata } from "next";
import Navigation from "@/components/sections/Navigation";
import { Sidebar, MobileNav } from "@/components/docs";
import { getDocsConfig } from "@/lib/docs-config";

const description =
  "FlowDown documentation - Learn how to use FlowDown, a privacy-first AI workspace for iOS and macOS.";

export const metadata: Metadata = {
  title: {
    template: "%s | FlowDown Docs",
    default: "FlowDown Documentation",
  },
  description,
  openGraph: {
    title: "FlowDown Documentation",
    description,
    type: "website",
  },
};

export default function DocsRootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const config = getDocsConfig();

  return (
    <div className="h-screen flex flex-col bg-[#f6f6f6] overflow-hidden">
      <Navigation />

      <div className="flex flex-1 pt-[72px] overflow-hidden">
        <div className="hidden lg:block h-full">
          <Sidebar items={config.sidebarNav} />
        </div>

        <main className="flex-1 min-w-0 overflow-y-auto">
          <div className="max-w-4xl mx-auto px-6 py-10">
            <article className="docs-content">{children}</article>
          </div>
        </main>

        <MobileNav items={config.sidebarNav} />
      </div>
    </div>
  );
}
