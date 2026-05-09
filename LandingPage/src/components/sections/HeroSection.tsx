import Link from "next/link";
import { FadeIn } from "@/components/animations";

export default function HeroSection() {
  return (
    <>
      {/* Hero Section */}
      <section className="pt-[180px] px-6 max-w-[1280px] mx-auto">
        <div className="max-w-[720px]">
          {/* Headline */}
          <FadeIn delay={0.1}>
            <h1 className="font-['Instrument_Serif'] text-[48px] text-[#242424] tracking-[-0.96px] leading-tight mb-4">
              AI That Works Even Without Us
            </h1>
          </FadeIn>

          {/* Subheadline */}
          <FadeIn delay={0.2}>
            <p className="text-lg text-[rgba(0,0,0,0.75)] leading-relaxed mb-6">
              You can OWN a blazing fast and smooth Agent app. Switch between
              your AI services, connect MCP tools, automate with Shortcuts, or
              use local models on your device.
            </p>
          </FadeIn>

          {/* CTA */}
          <FadeIn delay={0.3}>
            <div className="flex flex-col gap-2">
              <Link
                href="https://apps.apple.com/us/app/flowdown-open-fast-ai/id6740553198"
                target="_blank"
                className="inline-flex bg-[#242424] text-white text-lg font-medium px-6 py-4 rounded-full shadow-sm hover:bg-[#1a1a1a] transition-colors w-fit"
              >
                Download from App Store
              </Link>
              <p className="text-xs text-[#828282]">
                Available on iOS 17+ / macOS 14+ / Supports Apple Silicon &
                Intel
              </p>
            </div>
          </FadeIn>
        </div>
      </section>

      {/* App Screenshot */}
      <section className="px-6 mt-6 max-w-[1280px] mx-auto">
        <FadeIn delay={0.5} direction="up" className="w-full">
          <img
            src="/hero-image.png"
            alt="FlowDown App Screenshot"
            className="w-full h-[869px] object-cover rounded-sm shadow-lg"
          />
        </FadeIn>

        {/* Read the User Guide button */}
        <FadeIn delay={0.6}>
          <Link
            href="/docs/documents/welcome"
            className="inline-flex items-center text-lg font-medium text-[#242424] hover:opacity-70 transition-opacity mt-8"
          >
            Read the User Guide →
          </Link>
        </FadeIn>
      </section>
    </>
  );
}
