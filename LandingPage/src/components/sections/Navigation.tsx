"use client";

import { useState } from "react";
import Link from "next/link";
import { AnimatePresence, motion } from "framer-motion";

export default function Navigation() {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <>
      <nav className="fixed top-0 left-0 right-0 bg-[#f6f6f6]/80 backdrop-blur-md z-50 border-b border-[#e5e5e5]/50 h-[72px]">
        <div className="max-w-[1280px] mx-auto flex items-center justify-between px-6 h-full">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 z-50">
            <img
              src="/icon-primary.png"
              alt="FlowDown"
              className="w-[38px] h-[38px] rounded-full"
            />
            <span className="text-base font-semibold text-[#242424]">
              FlowDown
            </span>
          </Link>

          {/* Desktop Nav */}
          <div className="hidden md:flex items-center gap-8">
            <Link
              href="/docs"
              className="text-base font-medium text-[#242424] hover:opacity-70 transition-opacity"
            >
              Documentation
            </Link>
            <Link
              href="/compare"
              className="text-base font-medium text-[#242424] hover:opacity-70 transition-opacity"
            >
              Compare
            </Link>
            <Link
              href="https://github.com/Lakr233/FlowDown"
              target="_blank"
              className="text-base font-medium text-[#242424] hover:opacity-70 transition-opacity"
            >
              Get Source Code
            </Link>
            <Link
              href="/docs/documents/models/cloud_models_setup"
              className="text-base font-medium text-[#242424] hover:opacity-70 transition-opacity"
            >
              Add Models
            </Link>
            <Link
              href="https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198"
              target="_blank"
              className="btn-primary text-white text-sm font-medium px-5 py-2.5 rounded-lg shadow-sm hover:opacity-90 transition-opacity"
            >
              Download
            </Link>
          </div>

          {/* Mobile Menu Button */}
          <button
            className="md:hidden flex flex-col justify-center items-center w-10 h-10 gap-1.5 z-50"
            onClick={() => setIsOpen(!isOpen)}
            aria-label="Toggle menu"
          >
            <motion.span
              animate={isOpen ? { rotate: 45, y: 8 } : { rotate: 0, y: 0 }}
              className="w-6 h-0.5 bg-[#242424] block rounded-full transition-transform"
            />
            <motion.span
              animate={isOpen ? { opacity: 0 } : { opacity: 1 }}
              className="w-6 h-0.5 bg-[#242424] block rounded-full transition-opacity"
            />
            <motion.span
              animate={isOpen ? { rotate: -45, y: -8 } : { rotate: 0, y: 0 }}
              className="w-6 h-0.5 bg-[#242424] block rounded-full transition-transform"
            />
          </button>
        </div>
      </nav>

      {/* Mobile Menu Overlay */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            initial={{ opacity: 0, y: -20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            className="fixed inset-0 bg-[#f6f6f6] z-40 md:hidden pt-[100px] px-6"
          >
            <div className="flex flex-col gap-6 text-center">
              <Link
                href="/docs"
                className="text-xl font-medium text-[#242424]"
                onClick={() => setIsOpen(false)}
              >
                Documentation
              </Link>
              <Link
                href="/compare"
                className="text-xl font-medium text-[#242424]"
                onClick={() => setIsOpen(false)}
              >
                Compare
              </Link>
              <Link
                href="https://github.com/Lakr233/FlowDown"
                target="_blank"
                className="text-xl font-medium text-[#242424]"
                onClick={() => setIsOpen(false)}
              >
                Get Source Code
              </Link>
              <Link
                href="/docs/documents/models/cloud_models_setup"
                className="text-xl font-medium text-[#242424]"
                onClick={() => setIsOpen(false)}
              >
                Add Models
              </Link>
              <Link
                href="https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198"
                target="_blank"
                className="btn-primary text-white text-lg font-medium px-5 py-3 rounded-xl shadow-sm hover:opacity-90 transition-opacity w-full max-w-[200px] mx-auto"
                onClick={() => setIsOpen(false)}
              >
                Download
              </Link>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
