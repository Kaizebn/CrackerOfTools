/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        // Dark, dense theme
        ink: {
          950: '#0a0b0f',
          900: '#0f1117',
          850: '#151824',
          800: '#1a1e2e',
          700: '#232838',
          600: '#2e3448',
          500: '#3a4159',
        },
        brand: {
          DEFAULT: '#7c5cff',
          soft: '#9b82ff',
          dim: '#5b41c9',
        },
        accent: {
          green: '#2ecc9b',
          amber: '#f5a623',
          red: '#ff5c72',
          blue: '#3aa0ff',
          pink: '#ff6ec7',
        },
      },
      fontFamily: {
        sans: ['system-ui', '-apple-system', 'Segoe UI', 'Roboto', 'Inter', 'Helvetica', 'Arial', 'sans-serif'],
      },
      boxShadow: {
        card: '0 1px 0 0 rgba(255,255,255,0.03) inset, 0 8px 24px -12px rgba(0,0,0,0.6)',
        glow: '0 0 0 1px rgba(124,92,255,0.35), 0 8px 30px -8px rgba(124,92,255,0.4)',
      },
    },
  },
  plugins: [],
}
