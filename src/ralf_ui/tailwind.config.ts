import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: '#1f6feb',
          dark: '#1a4fb4'
        }
      }
    }
  },
  plugins: []
};

export default config;
