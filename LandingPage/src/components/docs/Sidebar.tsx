"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NavSection } from "@/lib/docs-config";

interface SidebarProps {
  items: NavSection[];
}

export function DocsNavSections({
  items,
  onNavigate,
}: {
  items: NavSection[];
  onNavigate?: () => void;
}) {
  const pathname = usePathname();

  return (
    <>
      {items.map((section, idx) => (
        <div key={idx}>
          <h4 className="font-semibold text-[#242424] text-sm mb-2 px-2">
            {section.title}
          </h4>
          <ul className="space-y-0.5">
            {section.items.map((item, itemIdx) => {
              const isActive = pathname === item.href;
              return (
                <li key={itemIdx}>
                  <Link
                    href={item.href}
                    onClick={onNavigate}
                    className={`block text-sm py-2 px-3 rounded-lg transition-all ${
                      isActive
                        ? "bg-[#ebebeb] text-[#242424] font-medium"
                        : "text-[#828282] hover:bg-[#ebebeb]/50 hover:text-[#242424]"
                    }`}
                  >
                    {item.title}
                  </Link>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </>
  );
}

export function Sidebar({ items }: SidebarProps) {
  return (
    <aside className="w-64 h-full shrink-0 border-r border-[#e6e6e6] bg-[#f6f6f6] flex flex-col">
      <nav className="flex-1 overflow-y-auto space-y-6 py-6 px-4">
        <DocsNavSections items={items} />
      </nav>
    </aside>
  );
}
