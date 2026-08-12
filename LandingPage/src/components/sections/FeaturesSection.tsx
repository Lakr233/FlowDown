"use client";

import { useState, useEffect } from "react";
import { FadeIn, StaggerContainer, StaggerItem } from "@/components/animations";

const workflowTexts = [
  "Vision Support: Interact with vision-capable models.",
  "Audio Support: Send audio messages to compatible models using attachments.",
  "File Attachments: Add files and documents to your conversations.",
  "Web Search: Grant the AI access to real-time information from the web.",
  "Reusable Templates: Save and quickly reuse your favorite prompts.",
  "Shortcuts Integration: Deep integration with system Shortcuts for automating your workflows.",
];

// Rotating text component with smooth vertical slide
function RotatingText() {
  const [currentIndex, setCurrentIndex] = useState(0);

  useEffect(() => {
    const interval = setInterval(() => {
      setCurrentIndex((prev) => (prev + 1) % workflowTexts.length);
    }, 3000);

    return () => clearInterval(interval);
  }, []);

  return (
    <div className="h-[28px] overflow-hidden relative">
      <div
        className="transition-transform duration-700 ease-[cubic-bezier(0.16,1,0.3,1)]"
        style={{ transform: `translateY(-${currentIndex * 28}px)` }}
      >
        {workflowTexts.map((text, index) => (
          <p
            key={index}
            className="text-lg text-[#828282] h-[28px] flex items-center whitespace-nowrap"
          >
            {text}
          </p>
        ))}
      </div>
    </div>
  );
}

// Glass icon component for feature cards
function GlassIcon({
  iconSrc,
  accentColor,
}: {
  iconSrc: string;
  accentColor?: string;
}) {
  return (
    <div className="relative group-hover:scale-110 transition-transform duration-500 ease-out">
      {/* Shadow ellipse - default gray */}
      <div className="absolute w-[40px] h-[42px] left-[30px] top-[50px] bg-[#e0e0e0] rounded-full blur-sm transition-all duration-500 ease-out group-hover:opacity-0" />
      {/* Shadow ellipse - colored hover state */}
      <div
        className="absolute w-[60px] h-[60px] left-[20px] top-[40px] rounded-full blur-xl opacity-0 transition-all duration-500 ease-out group-hover:opacity-60"
        style={{ backgroundColor: accentColor || "#e0e0e0" }}
      />

      {/* Glass container */}
      <div className="relative w-[100px] h-[100px] rounded-full border-2 border-white glass-icon flex items-center justify-center bg-white/10 backdrop-blur-md transition-all duration-500">
        <img src={iconSrc} alt="" className="w-[80px] h-[80px]" />
      </div>
    </div>
  );
}

// Feature card component
function FeatureCard({
  iconSrc,
  title,
  description,
  className = "",
  accentColor = "#242424", // Default accent color
}: {
  iconSrc: string;
  title: string;
  description: React.ReactNode;
  className?: string;
  accentColor?: string;
}) {
  return (
    <div
      className={`border border-[rgba(221,221,221,0.42)] rounded-[36px] feature-card-bg overflow-hidden h-full ${className} group transition-all duration-500 bg-white`}
      style={
        {
          "--accent-color": accentColor,
        } as React.CSSProperties
      }
    >
      <div className="p-6 flex flex-col items-center justify-between h-[340px]">
        <GlassIcon iconSrc={iconSrc} accentColor={accentColor} />
        <div className="w-full flex flex-col gap-2">
          <h3 className="text-lg font-semibold text-[#242424]">{title}</h3>
          <div className="text-sm text-[#828282] leading-relaxed [&>strong]:font-semibold [&>strong]:text-gray-900 group-hover:[&>strong]:text-[var(--accent-color)] [&>strong]:transition-colors [&>strong]:duration-300">
            {description}
          </div>
        </div>
      </div>
    </div>
  );
}

export default function FeaturesSection() {
  return (
    <section className="px-6 mt-[120px] max-w-[1280px] mx-auto" id="features">
      <FadeIn>
        <h2 className="font-['Instrument_Serif'] text-[42px] text-[#242424] tracking-[-0.84px] mb-4">
          Why Choose FlowDown
        </h2>
      </FadeIn>

      {/* Feature cards row 1 */}
      <StaggerContainer className="flex flex-wrap gap-6 mt-8">
        <StaggerItem className="flex-1 min-w-[280px]">
          <FeatureCard
            iconSrc="/why-choose-flowdown/private-first.svg"
            title="Privacy First"
            accentColor="#3b82f6" // Blue
            description={
              <>
                Your conversations and API credentials never leave your device.{" "}
                <strong>
                  All data is stored locally or synced via your private iCloud
                </strong>
                . We collect nothing.
              </>
            }
          />
        </StaggerItem>
        <StaggerItem className="flex-1 min-w-[280px]">
          <FeatureCard
            iconSrc="/why-choose-flowdown/native-performance.svg"
            title="Native Performance"
            accentColor="#f97316" // Orange
            description={
              <>
                Built with <strong>Swift</strong>, FlowDown is lightweight and
                incredibly fast. No web wrappers, just a seamless,{" "}
                <strong>native experience</strong> on iOS and macOS.
              </>
            }
          />
        </StaggerItem>
        <StaggerItem className="flex-1 min-w-[280px]">
          <FeatureCard
            iconSrc="/why-choose-flowdown/universal-compatibility.svg"
            title="Universal Compatibility"
            accentColor="#8b5cf6" // Violet
            description={
              <>
                Connect to any{" "}
                <strong>
                  OpenAI-compatible API, including self-hosted models
                </strong>
                , giving you complete freedom and control.
              </>
            }
          />
        </StaggerItem>
      </StaggerContainer>

      {/* Powerful Workflows Card */}
      <FadeIn delay={0.2} className="w-full">
        <div className="mt-8 bg-white rounded-[36px] border border-[rgba(221,221,221,0.42)] overflow-hidden h-[580px] relative">
          {/* Background image */}
          <div
            className="absolute inset-0 bg-cover bg-center blur-[8px]"
            style={{
              backgroundImage:
                "url('/powerful-workflow/powerful-workflow-bg.png')",
            }}
          />

          {/* Content */}
          <div className="absolute left-[40px] top-[40px] z-10">
            <h3 className="text-3xl font-semibold text-black mb-1">
              Powerful Workflows
            </h3>
            <RotatingText />
          </div>

          {/* iPhone mockups */}
          <div className="absolute inset-x-0 top-[190px] flex justify-center gap-6">
            {[1, 2, 3, 4].map((i) => (
              <img
                key={i}
                src={`/powerful-workflow/${i}.png`}
                alt={`Workflow ${i}`}
                className="h-[430px] w-auto"
              />
            ))}
          </div>
        </div>
      </FadeIn>

      {/* Feature cards row 2 */}
      <StaggerContainer className="flex flex-wrap gap-6 mt-8">
        <StaggerItem className="flex-1 min-w-[280px]">
          <FeatureCard
            iconSrc="/why-choose-flowdown/rich-user-experience.svg"
            title="Rich User Experience"
            accentColor="#eab308" // Yellow
            description={
              <>
                Enjoy <strong>full Markdown rendering</strong>, syntax
                highlighting, and a buttery-smooth interface that makes
                interacting with AI a pleasure.
              </>
            }
          />
        </StaggerItem>
        <StaggerItem className="flex-1 min-w-[280px]">
          <FeatureCard
            iconSrc="/why-choose-flowdown/icloud-sync.svg"
            title="iCloud Sync"
            accentColor="#0ea5e9" // Sky Blue
            description="Seamlessly syncs your conversations, settings, and custom models across all your Apple devices."
          />
        </StaggerItem>
        <StaggerItem className="flex-1 min-w-[280px]">
          <FeatureCard
            iconSrc="/why-choose-flowdown/open-source-compatibility.svg"
            title="Open Source Compatibility"
            accentColor="#22c55e" // Green
            description="FlowDown is fully open source under the AGPL-3.0 license. We invite you to inspect the code and verify our commitment to privacy and quality."
          />
        </StaggerItem>
      </StaggerContainer>
    </section>
  );
}
