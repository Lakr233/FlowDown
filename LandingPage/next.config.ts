import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,

  images: {
    unoptimized: true,
  },

  // Turbopack is off for MDX compatibility, via --webpack in the package.json scripts.
  // MDX is compiled by next-mdx-remote in the docs page, not by @next/mdx.
};

export default nextConfig;
