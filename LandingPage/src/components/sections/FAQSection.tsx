"use client";

import Link from "next/link";
import { useState } from "react";
import { FadeIn, StaggerContainer, StaggerItem } from "@/components/animations";

// FAQ item component
function FAQItem({
  question,
  answer,
  isOpen,
  onClick,
}: {
  question: string;
  answer?: React.ReactNode;
  isOpen: boolean;
  onClick: () => void;
}) {
  return (
    <div className="flex flex-col w-full">
      <button
        onClick={onClick}
        className={`flex items-center justify-between font-['Instrument_Serif'] text-3xl tracking-[-0.72px] text-left transition-colors duration-300 ${
          isOpen ? "text-black" : "text-[#9d9d9d]"
        } hover:text-black`}
      >
        <span>{question}</span>
        <svg
          className={`w-[14px] h-[14px] flex-shrink-0 transition-transform duration-300 ease-out ${
            isOpen ? "rotate-180" : "rotate-0"
          }`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </button>
      <div
        className={`grid transition-all duration-300 ease-out ${
          isOpen
            ? "grid-rows-[1fr] opacity-100 mt-4"
            : "grid-rows-[0fr] opacity-0 mt-0"
        }`}
      >
        <div className="overflow-hidden">
          {answer && (
            <div className="text-[#1c1c1c] text-sm leading-relaxed">
              {answer}
            </div>
          )}
        </div>
      </div>
      <div className="h-px bg-[#dddddd] w-full mt-4" />
    </div>
  );
}

export default function FAQSection() {
  const [openFAQ, setOpenFAQ] = useState<number>(1);

  return (
    <section className="px-6 mt-[120px] max-w-[1280px] mx-auto" id="faq">
      <FadeIn>
        <h2 className="font-['Instrument_Serif'] text-[42px] text-[#242424] tracking-[-0.84px] mb-10">
          Frequently Asked Questions
        </h2>
      </FadeIn>

      <StaggerContainer className="flex flex-col gap-10">
        <StaggerItem>
          <FAQItem
            question="Which AI models does FlowDown support?"
            isOpen={openFAQ === 0}
            onClick={() => setOpenFAQ(openFAQ === 0 ? -1 : 0)}
            answer={
              <div className="space-y-4">
                {/* ... content ... */}
                <p>
                  FlowDown supports all models compatible with OpenAI API
                  format, including:
                </p>
                <ul className="list-disc ml-6 space-y-1">
                  <li>
                    <strong>Built-in free models:</strong> Ready to use without
                    configuration
                  </li>
                  <li>
                    <strong>Major service providers:</strong> OpenAI, Claude
                    (via OpenRouter), Alibaba Cloud, ByteDance, etc.
                  </li>
                  <li>
                    <strong>Local models:</strong> Support for Ollama and MLX
                    local deployment
                  </li>
                  <li>
                    <strong>Custom interfaces:</strong> Any service compatible
                    with OpenAI API
                  </li>
                </ul>
                <Link
                  href="https://flowdown.ai/en-US"
                  target="_blank"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  LEARN MORE →
                </Link>
                <img
                  src="/q-and-a-1.png"
                  alt="AI Models Support"
                  className="w-full h-[200px] object-cover rounded-lg mt-3"
                />
              </div>
            }
          />
        </StaggerItem>

        <StaggerItem>
          <FAQItem
            question="Which platforms does FlowDown support?"
            isOpen={openFAQ === 1}
            onClick={() => setOpenFAQ(openFAQ === 1 ? -1 : 1)}
            answer={
              <div className="space-y-4">
                <p>
                  FlowDown provides native app support across all platforms:
                </p>
                <ul className="list-disc ml-6 space-y-1">
                  <li>
                    <strong>macOS:</strong> Full-featured desktop application
                  </li>
                  <li>
                    <strong>iOS:</strong> Mobile app optimized for iPhone
                  </li>
                  <li>
                    <strong>iPadOS:</strong> Tablet app adapted for iPad
                  </li>
                </ul>
                <p>
                  All versions are native applications, not web-based, ensuring
                  optimal performance and user experience
                </p>
                <Link
                  href="https://flowdown.ai/en-US"
                  target="_blank"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  LEARN MORE →
                </Link>
                <img
                  src="/q-and-a-2.png"
                  alt="Platform Support"
                  className="w-full h-[200px] object-cover rounded-lg mt-3"
                />
              </div>
            }
          />
        </StaggerItem>

        <StaggerItem>
          <FAQItem
            question="How to use FlowDown's tool calling features?"
            isOpen={openFAQ === 2}
            onClick={() => setOpenFAQ(openFAQ === 2 ? -1 : 2)}
            answer={
              <div className="space-y-4">
                <p>FlowDown supports powerful Tool Call functionality:</p>
                <ul className="list-disc ml-6 space-y-1">
                  <li>
                    <strong>Web search:</strong> Real-time access to latest
                    information
                  </li>
                  <li>
                    <strong>Document processing:</strong> Analyze and process
                    various file types
                  </li>
                </ul>
                <p>
                  We recommend using models like Gemini Flash for the best tool
                  calling experience
                </p>
                <Link
                  href="https://flowdown.ai/en-US"
                  target="_blank"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  LEARN MORE →
                </Link>
                <img
                  src="/q-and-a-3.png"
                  alt="Tool Calling Features"
                  className="w-full h-[200px] object-cover rounded-lg mt-3"
                />
              </div>
            }
          />
        </StaggerItem>

        <StaggerItem>
          <FAQItem
            question="How is data security and privacy ensured?"
            isOpen={openFAQ === 3}
            onClick={() => setOpenFAQ(openFAQ === 3 ? -1 : 3)}
            answer={
              <div className="space-y-4">
                <ul className="list-disc ml-6 space-y-1">
                  <li>
                    <strong>Local storage:</strong> All conversation data is
                    stored on your device
                  </li>
                  <li>
                    <strong>No data collection:</strong> FlowDown does not
                    collect or store your conversation content
                  </li>
                  <li>
                    <strong>Direct connection:</strong> Communicates directly
                    with AI service providers without intermediaries
                  </li>
                  <li>
                    <strong>Open source transparency:</strong> Code is open
                    source to ensure transparency
                  </li>
                </ul>
                <Link
                  href="https://flowdown.ai/en-US"
                  target="_blank"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  LEARN MORE →
                </Link>
                <img
                  src="/q-and-a-4.png"
                  alt="Data Security"
                  className="w-full h-[200px] object-cover rounded-lg mt-3"
                />
              </div>
            }
          />
        </StaggerItem>

        <StaggerItem>
          <FAQItem
            question="How to obtain and configure models?"
            isOpen={openFAQ === 4}
            onClick={() => setOpenFAQ(openFAQ === 4 ? -1 : 4)}
            answer={
              <div className="space-y-4">
                <ul className="list-disc ml-6 space-y-1">
                  <li>
                    <strong>Zero configuration:</strong> Built-in free models,
                    ready to use after download
                  </li>
                  <li>
                    <strong>Custom configuration:</strong> Support for adding
                    your own API keys
                  </li>
                  <li>
                    <strong>Import/Export:</strong> Support for importing and
                    exporting model configurations
                  </li>
                  <li>
                    <strong>Technical support:</strong> Provides detailed
                    configuration guides and community support
                  </li>
                </ul>
                <Link
                  href="https://flowdown.ai/en-US"
                  target="_blank"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  LEARN MORE →
                </Link>
                <img
                  src="/q-and-a-5.png"
                  alt="Model Configuration"
                  className="w-full h-[200px] object-cover rounded-lg mt-3"
                />
              </div>
            }
          />
        </StaggerItem>

        <StaggerItem>
          <FAQItem
            question="Is FlowDown free?"
            isOpen={openFAQ === 5}
            onClick={() => setOpenFAQ(openFAQ === 5 ? -1 : 5)}
            answer={
              <div className="space-y-4">
                <p>
                  FlowDown follows a public App Store pricing timeline. The US
                  storefront price steps down to a zero-dollar base app on June
                  10, 2026, while regional App Store pricing remains the final
                  purchase source.
                </p>
                <ul className="list-disc ml-6 space-y-1">
                  <li>Core chat, model configuration, and local storage are included.</li>
                  <li>
                    Users can bring their own provider keys for OpenAI-compatible
                    services.
                  </li>
                  <li>
                    Future personalization features may use separate pricing.
                  </li>
                </ul>
                <Link
                  href="/pricing"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  VIEW PRICING →
                </Link>
              </div>
            }
          />
        </StaggerItem>

        <StaggerItem>
          <FAQItem
            question="How do I configure a custom API key?"
            isOpen={openFAQ === 6}
            onClick={() => setOpenFAQ(openFAQ === 6 ? -1 : 6)}
            answer={
              <div className="space-y-4">
                <p>
                  Add a cloud model profile, enter the OpenAI-compatible base
                  URL, paste the provider token, add any required headers or
                  body fields, then verify the model before chatting.
                </p>
                <ul className="list-disc ml-6 space-y-1">
                  <li>
                    Use headers for provider auth, tenant IDs, or gateway
                    routing.
                  </li>
                  <li>
                    Use body fields for reasoning toggles, modalities, sampling
                    settings, and provider flags.
                  </li>
                  <li>
                    Keep one profile per provider or model family for easier
                    switching.
                  </li>
                </ul>
                <Link
                  href="/docs/documents/models/cloud_models_setup"
                  className="text-base font-medium text-black inline-block mt-3"
                >
                  READ SETUP GUIDE →
                </Link>
              </div>
            }
          />
        </StaggerItem>
      </StaggerContainer>
    </section>
  );
}
