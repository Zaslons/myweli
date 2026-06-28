import type { Config } from 'tailwindcss';
import { colors, radius, spacing } from './styles/tokens';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors,
      borderRadius: radius,
      spacing,
    },
  },
  plugins: [],
};

export default config;
