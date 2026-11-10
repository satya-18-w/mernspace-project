/** @type {import('next').NextConfig} */
const backendUrl = process.env.BACKEND_URL || 'http://13.207.240.55';

const nextConfig = {
    reactStrictMode: false,
    images: {
        remotePatterns: [
            {
                protocol: 'https',
                hostname: '**.amazonaws.com',
            },
        ],
    },
    async rewrites() {
        return [
            {
                source: '/api/catalog/:path*',
                destination: `${backendUrl}/api/catalog/:path*`,
            },
            {
                source: '/api/order/:path*',
                destination: `${backendUrl}/api/order/:path*`,
            },
        ];
    },
};

export default nextConfig;
