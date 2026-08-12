import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  agentRules: false,
  trailingSlash: true,
  images: {
    unoptimized: true,
  },
};

export default nextConfig;
