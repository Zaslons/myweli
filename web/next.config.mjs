/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  images: {
    // Hosts allowed for next/image. Salon photos come from the R2 public bucket
    // (R2_PUBLIC_BASE_URL = https://cdn.myweli.com at deploy); the R2 default
    // endpoint and the hermetic e2e stub host are allowed too.
    remotePatterns: [
      { protocol: 'https', hostname: 'cdn.myweli.com' },
      { protocol: 'https', hostname: '**.r2.cloudflarestorage.com' },
      { protocol: 'https', hostname: 'cdn.stub' }, // e2e stub images
    ],
  },
};

export default nextConfig;
