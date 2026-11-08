/** @type {import('next').NextConfig} */
const nextConfig = {
  // Statischer Export nach out/, lässt sich auf jedem Webspace / GitHub Pages hosten.
  output: "export",
  images: { unoptimized: true },
  // Für GitHub Pages unter /<repo>/: NEXT_PUBLIC_BASE_PATH=/grit npm run build
  basePath: process.env.NEXT_PUBLIC_BASE_PATH || "",
  trailingSlash: true,
};

export default nextConfig;
