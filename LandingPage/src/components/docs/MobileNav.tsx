"use client";

import { useState } from "react";
import { NavSection } from "@/lib/docs-config";
import { DocsNavSections } from "./Sidebar";

interface MobileNavProps {
  items: NavSection[];
}

export function MobileNav({ items }: MobileNavProps) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      {/* Mobile menu button */}
      <button
        onClick={() => setIsOpen(true)}
        className="lg:hidden fixed bottom-6 right-6 z-40 bg-[#242424] text-white p-4 rounded-full shadow-lg hover:opacity-90 transition-opacity"
        aria-label="Open navigation menu"
      >
        <svg
          className="w-5 h-5"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M4 6h16M4 12h16M4 18h16"
          />
        </svg>
      </button>

      {/* Overlay */}
      {isOpen && (
        <div
          className="lg:hidden fixed inset-0 z-50 bg-black/30"
          onClick={() => setIsOpen(false)}
        />
      )}

      {/* Sidebar drawer */}
      <div
        className={`lg:hidden fixed inset-y-0 left-0 z-50 w-72 bg-[#f6f6f6] transform transition-transform duration-300 ease-in-out shadow-xl flex flex-col ${
          isOpen ? "translate-x-0" : "-translate-x-full"
        }`}
      >
        {/* Close button */}
        <button
          onClick={() => setIsOpen(false)}
          className="absolute top-6 right-4 p-2 text-[#828282] hover:text-[#242424] transition-colors z-10"
          aria-label="Close navigation menu"
        >
          <svg
            className="w-5 h-5"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto py-6 px-4 pt-16 space-y-6">
          <DocsNavSections items={items} onNavigate={() => setIsOpen(false)} />
        </nav>
      </div>
    </>
  );
}
