import { Metadata } from "next";
import Link from "next/link";
import { getDocsConfig } from "@/lib/docs-config";

export const metadata: Metadata = {
  title: "FlowDown Documentation",
  alternates: {
    canonical: "/docs",
  },
};

export default function DocsHomePage() {
  const config = getDocsConfig();

  return (
    <div>
      <h1 className="font-['Instrument_Serif'] text-4xl text-[#242424] tracking-[-0.5px] mb-3">
        FlowDown Documentation
      </h1>
      <p className="text-lg text-[#828282] mb-10">
        Welcome to the FlowDown documentation. Choose a topic to get started.
      </p>

      <div className="grid gap-4 md:grid-cols-2">
        {config.sidebarNav.map((section, idx) => (
          <div
            key={idx}
            className="bg-[#ebebeb] rounded-xl p-5 border border-[#e6e6e6] hover:border-[#d0d0d0] transition-colors"
          >
            <h2 className="font-semibold text-[#242424] mb-3 text-base">
              {section.title}
            </h2>
            <ul className="space-y-1.5">
              {section.items.slice(0, 4).map((item, itemIdx) => (
                <li key={itemIdx}>
                  <Link
                    href={item.href}
                    className="text-[#454545] hover:text-[#242424] text-sm transition-colors"
                  >
                    {item.title}
                  </Link>
                </li>
              ))}
              {section.items.length > 4 && (
                <li className="text-[#9d9d9d] text-sm">
                  +{section.items.length - 4} more...
                </li>
              )}
            </ul>
          </div>
        ))}
      </div>
    </div>
  );
}
