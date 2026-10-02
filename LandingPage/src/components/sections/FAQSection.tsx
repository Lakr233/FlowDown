"use client";

import Link from "next/link";
import { useState } from "react";
import { FadeIn, StaggerContainer, StaggerItem } from "@/components/animations";

const faqs = [
  {
    question: "Which AI models does FlowDown support?",
    answer: (
      <>
        <p>
          FlowDown supports all models compatible with OpenAI API
          format, including:
        </p>
        <ul className="list-disc ml-6 space-y-1">
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
      </>
    ),
    link: { href: "https://flowdown.ai/en-US", label: "LEARN MORE →", external: true },
    image: { src: "/q-and-a-1.png", alt: "AI Models Support" },
  },
  {
    question: "Which platforms does FlowDown support?",
    answer: (
      <>
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
      </>
    ),
    link: { href: "https://flowdown.ai/en-US", label: "LEARN MORE →", external: true },
    image: { src: "/q-and-a-2.png", alt: "Platform Support" },
  },
  {
    question: "How to use FlowDown's tool calling features?",
    answer: (
      <>
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
      </>
    ),
    link: { href: "https://flowdown.ai/en-US", label: "LEARN MORE →", external: true },
    image: { src: "/q-and-a-3.png", alt: "Tool Calling Features" },
  },
  {
    question: "How is data security and privacy ensured?",
    answer: (
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
    ),
    link: { href: "https://flowdown.ai/en-US", label: "LEARN MORE →", external: true },
    image: { src: "/q-and-a-4.png", alt: "Data Security" },
  },
  {
    question: "How to obtain and configure models?",
    answer: (
      <ul className="list-disc ml-6 space-y-1">
        <li>
          <strong>On-device models:</strong> Use Apple Intelligence or
          download an MLX model on supported hardware
        </li>
        <li>
          <strong>Custom configuration:</strong> Support for bringing
          your own API
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
    ),
    link: { href: "https://flowdown.ai/en-US", label: "LEARN MORE →", external: true },
    image: { src: "/q-and-a-5.png", alt: "Model Configuration" },
  },
  {
    question: "Is FlowDown free?",
    answer: (
      <>
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
      </>
    ),
    link: { href: "/pricing", label: "VIEW PRICING →" },
  },
  {
    question: "How do I bring my own API?",
    answer: (
      <>
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
      </>
    ),
    link: { href: "/docs/documents/models/cloud_models_setup", label: "READ SETUP GUIDE →" },
  },
];

function FAQItem({
  question,
  answer,
  isOpen,
  onClick,
}: {
  question: string;
  answer: React.ReactNode;
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
          <div className="text-[#1c1c1c] text-sm leading-relaxed">
            {answer}
          </div>
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
        {faqs.map((faq, index) => (
          <StaggerItem key={index}>
            <FAQItem
              question={faq.question}
              isOpen={openFAQ === index}
              onClick={() => setOpenFAQ(openFAQ === index ? -1 : index)}
              answer={
                <div className="space-y-4">
                  {faq.answer}
                  <Link
                    href={faq.link.href}
                    target={faq.link.external ? "_blank" : undefined}
                    className="text-base font-medium text-black inline-block mt-3"
                  >
                    {faq.link.label}
                  </Link>
                  {faq.image && (
                    <img
                      src={faq.image.src}
                      alt={faq.image.alt}
                      className="w-full h-[200px] object-cover rounded-lg mt-3"
                    />
                  )}
                </div>
              }
            />
          </StaggerItem>
        ))}
      </StaggerContainer>
    </section>
  );
}
