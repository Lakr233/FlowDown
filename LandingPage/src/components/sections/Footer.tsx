import Link from "next/link";
import { FadeIn } from "@/components/animations";

const footerColumns: { heading: string; links: { href: string; label: string; external?: boolean }[] }[] = [
  {
    heading: "Download",
    links: [
      {
        href: "https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198",
        label: "iOS App Store",
        external: true,
      },
      {
        href: "https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198",
        label: "macOS App Store",
        external: true,
      },
      { href: "https://github.com/Lakr233/FlowDown", label: "Get Source Code", external: true },
    ],
  },
  {
    heading: "Doc",
    links: [
      { href: "/docs/documents/models/inference_configuration", label: "Get Local Models" },
      { href: "/docs/documents/models/cloud_models_setup", label: "Get Cloud Models" },
      { href: "/docs/documents/quickstart/basic_usage", label: "Basic Usage" },
      { href: "/docs/documents/troubleshooting/faq", label: "FAQ" },
    ],
  },
  {
    heading: "Others",
    links: [
      { href: "/pricing", label: "Price" },
      { href: "/compare", label: "Compare" },
      { href: "/about", label: "About" },
      { href: "/contact", label: "Contact" },
      { href: "/privacy", label: "Privacy" },
      { href: "/docs/documents/legal/software_license", label: "Terms of Service" },
    ],
  },
];

export default function Footer() {
  return (
    <footer className="bg-white mt-[120px] relative overflow-hidden">
      {/* Texture Filter Definition */}
      <svg className="absolute w-0 h-0" aria-hidden="true">
        <filter id="roughpaper">
          <feTurbulence
            type="fractalNoise"
            baseFrequency="0.03"
            numOctaves="5"
          />
          <feDiffuseLighting lightingColor="#ffffff" surfaceScale="2">
            <feDistantLight azimuth="45" elevation="70" />
          </feDiffuseLighting>
        </filter>
      </svg>

      {/* Rough Paper Texture */}
      <div
        className="absolute inset-0 opacity-50"
        style={{ filter: "url(#roughpaper) brightness(1.1)" }}
      />

      {/* Grid pattern overlay */}
      <div
        className="absolute inset-0 opacity-20"
        style={{
          backgroundImage: `repeating-linear-gradient(0deg, transparent, transparent 367px, #d9d9d9 367px, #d9d9d9 368px),
                           repeating-linear-gradient(90deg, transparent, transparent 367px, #d9d9d9 367px, #d9d9d9 368px)`,
        }}
      />

      <div className="border-t border-[#dddddd]" />

      <div className="max-w-[1280px] mx-auto px-6 py-12 relative">
        <FadeIn>
          <div className="flex flex-col md:flex-row md:justify-between gap-12">
            {/* Left side - Logo & info & Pigeon */}
            <div className="flex flex-col gap-4">
              <div>
                <p className="text-lg text-[#242424]">FlowDown.ai</p>
                <p className="text-sm font-medium text-[#aeaeae] mt-2">
                  © 2025-2026 FlowDown Team. All rights reserved.
                </p>
              </div>
              <img
                src="/gugugu.png"
                alt="Decorative pigeon"
                className="w-[80px] h-[60px] object-cover rounded-[30px] opacity-50 mix-blend-hard-light mt-4 transition-all duration-300 hover:opacity-100 hover:mix-blend-normal"
              />
            </div>

            {/* Right side - Links */}
            <div className="grid grid-cols-2 md:grid-cols-3 gap-x-12 gap-y-8">
              {footerColumns.map((column) => (
                <div key={column.heading} className="flex flex-col gap-4">
                  <p className="text-sm font-medium text-[#242424]">{column.heading}</p>
                  <div className="flex flex-col gap-3 text-sm font-medium text-[#454545]">
                    {column.links.map((link) => (
                      <Link
                        key={link.label}
                        href={link.href}
                        target={link.external ? "_blank" : undefined}
                        className="hover:text-[#242424] transition-colors"
                      >
                        {link.label}
                      </Link>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* Social icons */}
          <div className="flex gap-2 mt-12 md:mt-[80px] mix-blend-plus-darker">
            {/* GitHub */}
            <Link
              href="https://github.com/Lakr233/FlowDown"
              target="_blank"
              className="w-10 h-10 flex items-center justify-center rounded text-[#8e8e8e] hover:bg-gray-100 hover:text-black transition-colors"
            >
              <svg className="w-6 h-6" fill="currentColor" viewBox="0 0 24 24">
                <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
              </svg>
            </Link>
            {/* Email */}
            <Link
              href="mailto:flowdownapp@qaq.wiki"
              className="w-10 h-10 flex items-center justify-center rounded text-[#8e8e8e] hover:bg-gray-100 hover:text-black transition-colors"
            >
              <svg
                className="w-6 h-6"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
            </Link>
          </div>
        </FadeIn>
      </div>
    </footer>
  );
}
